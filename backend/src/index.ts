import { Hono } from 'hono'
import { cors } from 'hono/cors'
import { createClient } from '@supabase/supabase-js'
import { sendPushNotification } from './fcm'
import { cleanupPreviousUpdates, verifyCronRequest } from './cron'

type Bindings = {
  SUPABASE_URL: string
  SUPABASE_SERVICE_ROLE_KEY: string
  FIREBASE_SERVICE_ACCOUNT_JSON: string
  PASSWORD_SALT: string
  QSTASH_CURRENT_SIGNING_KEY?: string
  QSTASH_NEXT_SIGNING_KEY?: string
  CRON_SECRET?: string
}

const app = new Hono<{ Bindings: Bindings }>()

app.use('*', cors())

function getSupabase(c: { env: Bindings }) {
  const url = c.env.SUPABASE_URL
  const key = c.env.SUPABASE_SERVICE_ROLE_KEY
  if (!url || !key) {
    throw new Error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY worker secrets.')
  }
  return createClient(url, key)
}

// Health Check
app.get('/', (c) => {
  return c.json({
    status: 'online',
    service: 'update_me API',
    version: '1.0.0',
    timestamp: new Date().toISOString()
  })
})

// 0. Frictionless Google Auth Sync (Neon / Supabase User Profile)
app.post('/api/auth/google', async (c) => {
  try {
    const supabase = getSupabase(c)
    const { email, displayName, avatarUrl } = await c.req.json<{
      email: string
      displayName?: string
      avatarUrl?: string
    }>()

    if (!email) {
      return c.json({ error: 'Email is required' }, 400)
    }

    const cleanEmail = email.trim().toLowerCase()

    // 1. Check if user already exists
    const { data: existingUser } = await supabase
      .from('User')
      .select('*, partner:User!partner_id(*)')
      .eq('email', cleanEmail)
      .maybeSingle()

    if (existingUser) {
      // Update profile info if changed
      const { data: updatedUser } = await supabase
        .from('User')
        .update({
          display_name: displayName || existingUser.display_name,
          avatar_url: avatarUrl || existingUser.avatar_url,
          updated_at: new Date().toISOString()
        })
        .eq('id', existingUser.id)
        .select('*, partner:User!partner_id(*)')
        .single()

      return c.json({
        success: true,
        user: updatedUser || existingUser
      })
    }

    // 2. Generate unique pair code (e.g. UM-7X9B)
    const randomHex = Math.random().toString(36).substring(2, 6).toUpperCase()
    const pairCode = `UM-${randomHex}`
    const username = cleanEmail.split('@')[0] + '-' + Math.floor(Math.random() * 1000)

    // 3. Insert new user
    const { data: newUser, error: insertErr } = await supabase
      .from('User')
      .insert({
        id: crypto.randomUUID(),
        email: cleanEmail,
        username,
        display_name: displayName || cleanEmail.split('@')[0],
        avatar_url: avatarUrl,
        pair_code: pairCode,
        updated_at: new Date().toISOString()
      })
      .select('*, partner:User!partner_id(*)')
      .single()

    if (insertErr) {
      return c.json({ error: insertErr.message }, 500)
    }

    return c.json({
      success: true,
      user: newUser
    })
  } catch (error: any) {
    return c.json({ error: error.message }, 500)
  }
})

// Simple SHA-256 helper with secret salt from Worker environment
async function hashPassword(password: string, salt: string): Promise<string> {
  if (!salt) {
    throw new Error('Missing PASSWORD_SALT worker secret.')
  }
  const enc = new TextEncoder()
  const data = enc.encode(`${password}:${salt}`)
  const digest = await crypto.subtle.digest('SHA-256', data)
  return Array.from(new Uint8Array(digest))
    .map(b => b.toString(16).padStart(2, '0'))
    .join('')
}

// 0.1 Set / Create Master Passcode
app.post('/api/auth/set-password', async (c) => {
  try {
    const supabase = getSupabase(c)
    const { userId, password } = await c.req.json<{
      userId: string
      password: string
    }>()

    if (!userId || !password || password.trim().length < 4) {
      return c.json({ error: 'Passcode must be at least 4 characters' }, 400)
    }

    const hashedPassword = await hashPassword(password.trim(), c.env.PASSWORD_SALT)

    const { data: updatedUser, error } = await supabase
      .from('User')
      .update({
        password: hashedPassword,
        have_password: true,
        updated_at: new Date().toISOString()
      })
      .eq('id', userId)
      .select('*, partner:User!partner_id(*)')
      .single()

    if (error || !updatedUser) {
      return c.json({ error: error?.message || 'Failed to update passcode' }, 500)
    }

    return c.json({
      success: true,
      user: updatedUser
    })
  } catch (error: any) {
    return c.json({ error: error.message }, 500)
  }
})

// 0.15 Update User FCM Device Token
app.patch('/api/users/:userId/fcm-token', async (c) => {
  try {
    const supabase = getSupabase(c)
    const userId = c.req.param('userId')
    const { token } = await c.req.json<{ token: string }>()

    if (!token) {
      return c.json({ error: 'FCM token is required' }, 400)
    }

    const { error } = await supabase
      .from('User')
      .update({ fcm_token: token, updated_at: new Date().toISOString() })
      .eq('id', userId)

    if (error) {
      return c.json({ error: error.message }, 500)
    }

    return c.json({ success: true })
  } catch (error: any) {
    return c.json({ error: error.message }, 500)
  }
})

// 0.2 Verify Master Passcode with Brute-Force Protection
app.post('/api/auth/verify-password', async (c) => {
  try {
    const supabase = getSupabase(c)
    const { userId, password } = await c.req.json<{
      userId: string
      password: string
    }>()

    if (!userId || !password) {
      return c.json({ error: 'User ID and passcode are required' }, 400)
    }

    const { data: user, error } = await supabase
      .from('User')
      .select('*, partner:User!partner_id(*)')
      .eq('id', userId)
      .single()

    if (error || !user) {
      return c.json({ error: 'User not found' }, 404)
    }

    const now = new Date()

    // 1. Check if user was previously locked out
    if (user.lock_until) {
      const lockUntil = new Date(user.lock_until)
      if (lockUntil > now) {
        // Still locked
        const remainingMinutes = Math.ceil((lockUntil.getTime() - now.getTime()) / (1000 * 60))
        return c.json({
          error: `Account locked due to too many failed attempts. Try again in ${remainingMinutes} minute${remainingMinutes > 1 ? 's' : ''}.`,
          isLocked: true,
          remainingMinutes,
        }, 423)
      } else {
        // Lockout period has EXPIRED! Automatically reset counter and unlock
        user.failed_attempts = 0
        user.lock_until = null
        await supabase
          .from('User')
          .update({
            failed_attempts: 0,
            lock_until: null,
            updated_at: now.toISOString()
          })
          .eq('id', userId)
      }
    }

    const hashedInput = await hashPassword(password.trim(), c.env.PASSWORD_SALT)

    // 2. Passcode Mismatch -> Increment failed_attempts & lock if threshold reached
    if (user.password !== hashedInput) {
      const currentAttempts = (user.failed_attempts || 0) + 1
      const maxAttempts = 5

      if (currentAttempts >= maxAttempts) {
        const lockDurationMinutes = 15
        const lockUntil = new Date(now.getTime() + lockDurationMinutes * 60 * 1000).toISOString()

        await supabase
          .from('User')
          .update({
            failed_attempts: currentAttempts,
            lock_until: lockUntil,
            updated_at: now.toISOString()
          })
          .eq('id', userId)

        return c.json({
          error: `Account locked for ${lockDurationMinutes} minutes due to ${maxAttempts} consecutive failed attempts.`,
          isLocked: true,
          remainingMinutes: lockDurationMinutes,
        }, 423)
      }

      // Not locked yet, save incremented attempts
      await supabase
        .from('User')
        .update({
          failed_attempts: currentAttempts,
          updated_at: now.toISOString()
        })
        .eq('id', userId)

      const remainingAttempts = maxAttempts - currentAttempts
      return c.json({
        error: `Incorrect passcode. ${remainingAttempts} attempt${remainingAttempts > 1 ? 's' : ''} remaining.`,
        isLocked: false,
        remainingAttempts,
      }, 401)
    }

    // 3. Success -> Reset failed_attempts and lock_until
    if ((user.failed_attempts || 0) > 0 || user.lock_until != null) {
      await supabase
        .from('User')
        .update({
          failed_attempts: 0,
          lock_until: null,
          updated_at: now.toISOString()
        })
        .eq('id', userId)
    }

    return c.json({
      success: true,
      user
    })
  } catch (error: any) {
    return c.json({ error: error.message }, 500)
  }
})

// 1. Get or Fetch User Profile
app.get('/api/user/:userId', async (c) => {
  try {
    const supabase = getSupabase(c)
    const userId = c.req.param('userId')

    const { data: user, error } = await supabase
      .from('User')
      .select('*, partner:User!partner_id(*)')
      .eq('id', userId)
      .single()

    if (error || !user) {
      return c.json({ error: 'User not found' }, 404)
    }

    return c.json({ user })
  } catch (error: any) {
    return c.json({ error: error.message }, 500)
  }
})

// 2. Link with Partner via Pair Code
app.post('/api/pair', async (c) => {
  try {
    const supabase = getSupabase(c)
    const { userId, pairCode } = await c.req.json<{
      userId: string
      pairCode: string
    }>()

    const { data: partnerUser, error: partnerErr } = await supabase
      .from('User')
      .select('*')
      .eq('pair_code', pairCode.trim().toUpperCase())
      .single()

    if (partnerErr || !partnerUser) {
      return c.json({ error: 'Pair code not found' }, 404)
    }

    if (partnerUser.id === userId) {
      return c.json({ error: 'You cannot pair with yourself' }, 400)
    }

    // Link both users
    await supabase.from('User').update({ partner_id: partnerUser.id }).eq('id', userId)
    await supabase.from('User').update({ partner_id: userId }).eq('id', partnerUser.id)

    return c.json({
      success: true,
      message: 'Paired successfully!',
      partner: partnerUser
    })
  } catch (error: any) {
    return c.json({ error: error.message }, 500)
  }
})

// 3. Post a Widget Photo Update to Partner
app.post('/api/updates', async (c) => {
  try {
    const supabase = getSupabase(c)
    const { senderId, receiverId, imageUrl, caption, locationName, latitude, longitude, createdAt, id } = await c.req.json<{
      senderId: string
      receiverId?: string
      imageUrl: string
      caption?: string
      locationName?: string
      latitude?: number
      longitude?: number
      createdAt?: string
      id?: string
    }>()

    if (!senderId || !imageUrl) {
      return c.json({ error: 'senderId and imageUrl are required' }, 400)
    }

    // Preserve offline capture timestamp with bounds checking (not > 10m future, not > 48h past)
    const now = new Date()
    let finalCreatedAt = now.toISOString()
    if (createdAt) {
      const parsed = Date.parse(createdAt)
      if (!isNaN(parsed)) {
        const clientDate = new Date(parsed)
        const diffMs = now.getTime() - clientDate.getTime()
        // If not more than 10 mins in the future and not older than 48 hours
        if (diffMs > -10 * 60 * 1000 && diffMs < 48 * 60 * 60 * 1000) {
          finalCreatedAt = clientDate.toISOString()
        }
      }
    }

    // If receiverId not passed, look up sender's partner
    let targetReceiverId = receiverId
    if (!targetReceiverId) {
      const { data: sender } = await supabase
        .from('User')
        .select('partner_id')
        .eq('id', senderId)
        .single()

      if (!sender || !sender.partner_id) {
        return c.json({ error: 'Sender does not have an active partner to receive updates.' }, 400)
      }
      targetReceiverId = sender.partner_id
    }

    const insertPayload: any = {
      sender_id: senderId,
      receiver_id: targetReceiverId,
      image_url: imageUrl,
      caption: caption?.slice(0, 140) || null,
      location_name: locationName || null,
      latitude: latitude || null,
      longitude: longitude || null,
      created_at: finalCreatedAt,
      is_read: false
    }

    if (id) {
      insertPayload.id = id
    }

    const { data: newUpdate, error } = await supabase
      .from('Updates')
      .upsert(insertPayload, { onConflict: 'id' })
      .select('*')
      .single()

    if (error) {
      return c.json({ error: error.message }, 500)
    }

    // Trigger high-priority push notification to partner's phone
    try {
      const { data: receiver } = await supabase
        .from('User')
        .select('fcm_token, display_name')
        .eq('id', targetReceiverId)
        .maybeSingle()

      const { data: senderInfo } = await supabase
        .from('User')
        .select('display_name, email')
        .eq('id', senderId)
        .maybeSingle()

      const senderDisplayName = senderInfo?.display_name || senderInfo?.email?.split('@')[0] || 'Your partner'

      if (receiver && receiver.fcm_token) {
        const pushPromise = sendPushNotification(
          {
            token: receiver.fcm_token,
            title: 'UpdateMe 📸',
            body: caption ? `${senderDisplayName}: "${caption}"` : `${senderDisplayName} posted a new update!`,
            data: {
              type: 'new_moment',
              updateId: newUpdate.id,
              senderId: senderId,
              imageUrl: imageUrl,
              caption: caption || '',
              locationName: locationName || '',
              createdAt: newUpdate.created_at,
            },
          },
          c.env
        )

        if (c.executionCtx && typeof c.executionCtx.waitUntil === 'function') {
          c.executionCtx.waitUntil(pushPromise)
        } else {
          await pushPromise
        }
      }
    } catch (pushErr) {
      console.error('[FCM] Error triggering new moment push notification:', pushErr)
    }

    return c.json({
      success: true,
      update: newUpdate
    })
  } catch (error: any) {
    return c.json({ error: error.message }, 500)
  }
})

// 4. Get Latest Update for Home Widget (by User / Receiver ID)
app.get('/api/updates/latest/:userId', async (c) => {
  try {
    const supabase = getSupabase(c)
    const userId = c.req.param('userId')

    const { data: latestUpdate, error } = await supabase
      .from('Updates')
      .select('*, sender:User!sender_id(id, display_name, avatar_url, username)')
      .eq('receiver_id', userId)
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle()

    if (error) {
      return c.json({ error: error.message }, 500)
    }

    return c.json({ latestUpdate })
  } catch (error: any) {
    return c.json({ error: error.message }, 500)
  }
})

// 5. Get Updates History / Feed between couple
app.get('/api/updates/feed/:userId', async (c) => {
  try {
    const supabase = getSupabase(c)
    const userId = c.req.param('userId')

    const { data: user } = await supabase
      .from('User')
      .select('partner_id')
      .eq('id', userId)
      .single()

    if (!user || !user.partner_id) {
      return c.json({ updates: [] })
    }

    const { data: feed, error } = await supabase
      .from('Updates')
      .select('*, sender:User!sender_id(id, display_name, avatar_url)')
      .or(`and(sender_id.eq.${userId},receiver_id.eq.${user.partner_id}),and(sender_id.eq.${user.partner_id},receiver_id.eq.${userId})`)
      .order('created_at', { ascending: false })
      .limit(30)

    if (error) {
      return c.json({ error: error.message }, 500)
    }

    return c.json({ updates: feed || [] })
  } catch (error: any) {
    return c.json({ error: error.message }, 500)
  }
})

// 6. Get Today's Moments (Strictly filtered to recent 24h / current date, received vs sent)
app.get('/api/updates/today/:userId', async (c) => {
  try {
    const supabase = getSupabase(c)
    const userId = c.req.param('userId')
    const type = c.req.query('type') || 'received' // 'received' (From Partner) or 'sent' (Sent Moments)

    // Robust rolling 24-hour window for current day moments across any client timezone
    const now = new Date()
    const rollingStart = new Date(now.getTime() - 24 * 60 * 60 * 1000).toISOString()

    let query = supabase
      .from('Updates')
      .select('*, sender:User!sender_id(id, display_name, avatar_url, username)')
      .gte('created_at', rollingStart)
      .order('created_at', { ascending: true }) // chronological order for carousel stories

    if (type === 'sent') {
      query = query.eq('sender_id', userId)
    } else {
      query = query.eq('receiver_id', userId)
    }

    const { data: updates, error } = await query

    if (error) {
      return c.json({ error: error.message }, 500)
    }

    return c.json({ updates: updates || [] })
  } catch (error: any) {
    return c.json({ error: error.message }, 500)
  }
})

// 7. Toggle Reaction on a Moment
app.patch('/api/updates/:id/react', async (c) => {
  try {
    const supabase = getSupabase(c)
    const updateId = c.req.param('id')
    const { isReacted } = await c.req.json<{ isReacted: boolean }>()

    const { data: updated, error } = await supabase
      .from('Updates')
      .update({ is_reacted: isReacted })
      .eq('id', updateId)
      .select('*')
      .single()

    if (error) {
      return c.json({ error: error.message }, 500)
    }

    // Trigger high-priority push notification when reacted
    if (isReacted && updated) {
      try {
        // Find the sender (author) of the moment and who reacted to it
        const { data: author } = await supabase
          .from('User')
          .select('id, fcm_token')
          .eq('id', updated.sender_id)
          .maybeSingle()

        const { data: reactor } = await supabase
          .from('User')
          .select('display_name, email')
          .eq('id', updated.receiver_id)
          .maybeSingle()

        const reactorDisplayName = reactor?.display_name || reactor?.email?.split('@')[0] || 'Your partner'

        if (author && author.fcm_token) {
          const reactionPushPromise = sendPushNotification(
            {
              token: author.fcm_token,
              title: 'UpdateMe ❤️',
              body: `${reactorDisplayName} reacted to your update!`,
              data: {
                type: 'heart_reaction',
                updateId: updated.id,
              },
            },
            c.env
          )

          if (c.executionCtx && typeof c.executionCtx.waitUntil === 'function') {
            c.executionCtx.waitUntil(reactionPushPromise)
          } else {
            await reactionPushPromise
          }
        }

        // Direct Realtime Broadcast to Author's private channel (<100ms instant reaction)
        try {
          const authorChannel = supabase.channel(`user-channel-${updated.sender_id}`)
          await authorChannel.send({
            type: 'broadcast',
            event: 'moment_reacted',
            payload: {
              updateId: updated.id,
              isReacted: isReacted,
              reactorDisplayName: reactorDisplayName,
            },
          })
          await supabase.removeChannel(authorChannel)
        } catch (realtimeErr) {
          console.error('[Realtime Broadcast] Error broadcasting reaction event:', realtimeErr)
        }
      } catch (pushErr) {
        console.error('[FCM] Error sending reaction push notification:', pushErr)
      }
    }

    return c.json({ success: true, update: updated })
  } catch (error: any) {
    return c.json({ error: error.message }, 500)
  }
})

// 8. Reply to a Moment (Strict 1-is-to-1 reply rule)
app.post('/api/updates/:id/reply', async (c) => {
  try {
    const supabase = getSupabase(c)
    const updateId = c.req.param('id')
    const { replyText, replyCreatedAt } = await c.req.json<{ replyText: string; replyCreatedAt?: string }>()

    if (!replyText || replyText.trim().length === 0) {
      return c.json({ error: 'Reply text cannot be empty' }, 400)
    }

    // 1. Fetch existing moment to enforce 1-is-to-1 gate
    const { data: existing, error: fetchErr } = await supabase
      .from('Updates')
      .select('*')
      .eq('id', updateId)
      .single()

    if (fetchErr || !existing) {
      return c.json({ error: 'Moment not found' }, 404)
    }

    if (existing.is_replied) {
      return c.json({ error: 'This update already has a reply' }, 409)
    }

    // Respect original offline client timestamp if valid, fallback to current server time
    const replyTimestamp = replyCreatedAt && !isNaN(Date.parse(replyCreatedAt))
      ? new Date(replyCreatedAt).toISOString()
      : new Date().toISOString()

    // 2. Persist reply to database
    const { data: updated, error: updateErr } = await supabase
      .from('Updates')
      .update({
        reply_text: replyText.trim(),
        reply_created_at: replyTimestamp,
        is_replied: true,
      })
      .eq('id', updateId)
      .select('*')
      .single()

    if (updateErr) {
      return c.json({ error: updateErr.message }, 500)
    }

    // 3. Fire FCM Push Notification & Realtime Broadcast in background
    try {
      const { data: author } = await supabase
        .from('User')
        .select('id, fcm_token')
        .eq('id', updated.sender_id)
        .maybeSingle()

      const { data: replier } = await supabase
        .from('User')
        .select('display_name, email')
        .eq('id', updated.receiver_id)
        .maybeSingle()

      const replierDisplayName = replier?.display_name || replier?.email?.split('@')[0] || 'Your partner'

      if (author && author.fcm_token) {
        const replyPushPromise = sendPushNotification(
          {
            token: author.fcm_token,
            title: 'UpdateMe 💬',
            body: `${replierDisplayName} replied: "${replyText.trim()}"`,
            data: {
              type: 'moment_reply',
              updateId: updated.id,
              replyText: replyText.trim(),
            },
          },
          c.env
        )

        if (c.executionCtx && typeof c.executionCtx.waitUntil === 'function') {
          c.executionCtx.waitUntil(replyPushPromise)
        } else {
          await replyPushPromise
        }
      }

      // Direct Realtime Broadcast to Author's private channel (<100ms instant perceived latency)
      try {
        const authorChannel = supabase.channel(`user-channel-${updated.sender_id}`)
        await authorChannel.send({
          type: 'broadcast',
          event: 'moment_replied',
          payload: {
            updateId: updated.id,
            replyText: replyText.trim(),
            replyCreatedAt: replyTimestamp,
            replierDisplayName: replierDisplayName,
          },
        })
        await supabase.removeChannel(authorChannel)
      } catch (realtimeErr) {
        console.error('[Realtime Broadcast] Error broadcasting reply event:', realtimeErr)
      }
    } catch (pushErr) {
      console.error('[FCM] Error sending reply push notification:', pushErr)
    }

    return c.json({ success: true, update: updated })
  } catch (error: any) {
    return c.json({ error: error.message }, 500)
  }
})

// 9. Scheduled Daily Cleanup via Upstash QStash (12:01 AM PH Time)
// Deletes all previous-day Updates rows and their Supabase Storage images,
// strictly preserving all moments from the current PH calendar date.
app.post('/api/cron/cleanup-updates', async (c) => {
  try {
    const rawBody = await c.req.text()
    const verification = await verifyCronRequest({
      signature: c.req.header('Upstash-Signature'),
      authHeader: c.req.header('Authorization'),
      body: rawBody,
      url: c.req.url,
      currentSigningKey: c.env.QSTASH_CURRENT_SIGNING_KEY,
      nextSigningKey: c.env.QSTASH_NEXT_SIGNING_KEY,
      cronSecret: c.env.CRON_SECRET,
    })

    if (!verification.authorized) {
      return c.json({ success: false, error: verification.error }, verification.status)
    }

    const supabase = getSupabase(c)
    const result = await cleanupPreviousUpdates(supabase)
    return c.json(result, 200)
  } catch (error: any) {
    console.error('[Cron] Unhandled cleanup error:', error?.message || error)
    return c.json({ success: false, error: error?.message || 'Cleanup failed' }, 500)
  }
})

export default app

