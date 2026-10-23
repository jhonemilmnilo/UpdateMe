import { Hono } from 'hono'
import { cors } from 'hono/cors'
import { createClient } from '@supabase/supabase-js'

type Bindings = {
  SUPABASE_URL?: string
  SUPABASE_SERVICE_ROLE_KEY?: string
}

const app = new Hono<{ Bindings: Bindings }>()

app.use('*', cors())

function getSupabase(c: any) {
  const url = c.env.SUPABASE_URL || 'https://afxnbhuabjppjlijmcly.supabase.co'
  const key = c.env.SUPABASE_SERVICE_ROLE_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFmeG5iaHVhYmpwcGpsaWptY2x5Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc5MjcwNzcwNSwiZXhwIjoyMTA4MjgzNzA1fQ.ONuCafolyJO7EKeciAFcDX7EmLGF1oE8Dle77X1jYjg'
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

// 3. Post a Widget Update
app.post('/api/updates', async (c) => {
  try {
    const supabase = getSupabase(c)
    const { senderId, imageUrl, caption, locationName } = await c.req.json<{
      senderId: string
      imageUrl: string
      caption?: string
      locationName?: string
    }>()

    if (!senderId || !imageUrl) {
      return c.json({ error: 'senderId and imageUrl are required' }, 400)
    }

    const { data: newUpdate, error } = await supabase
      .from('widget_updates')
      .insert({
        sender_id: senderId,
        image_url: imageUrl,
        caption,
        location_name: locationName
      })
      .select('*')
      .single()

    if (error) {
      return c.json({ error: error.message }, 500)
    }

    return c.json({
      success: true,
      update: newUpdate
    })
  } catch (error: any) {
    return c.json({ error: error.message }, 500)
  }
})

// 4. Get Latest Update for Home Widget
app.get('/api/updates/latest/:userId', async (c) => {
  try {
    const supabase = getSupabase(c)
    const userId = c.req.param('userId')

    const { data: user } = await supabase
      .from('User')
      .select('partner_id')
      .eq('id', userId)
      .single()

    if (!user || !user.partner_id) {
      return c.json({ error: 'User or partner not found' }, 404)
    }

    const { data: latestUpdate } = await supabase
      .from('widget_updates')
      .select('*')
      .eq('sender_id', user.partner_id)
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle()

    return c.json({ latestUpdate })
  } catch (error: any) {
    return c.json({ error: error.message }, 500)
  }
})

export default app
