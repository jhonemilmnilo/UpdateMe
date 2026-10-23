import { Hono } from 'hono'
import { cors } from 'hono/cors'
import { PrismaClient } from '@prisma/client'
import { PrismaPg } from '@prisma/adapter-pg'
import { Pool } from 'pg'

type Bindings = {
  DATABASE_URL: string
  FIREBASE_PROJECT_ID?: string
  FIREBASE_CLIENT_EMAIL?: string
  FIREBASE_PRIVATE_KEY?: string
}

const app = new Hono<{ Bindings: Bindings }>()

app.use('*', cors())

// Helper to get Prisma client with pg driver adapter on Cloudflare Workers
function getPrisma(databaseUrl: string) {
  const pool = new Pool({ connectionString: databaseUrl })
  const adapter = new PrismaPg(pool)
  return new PrismaClient({ adapter })
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

// 1. Get or Create Profile
app.post('/api/profile', async (c) => {
  const db = getPrisma(c.env.DATABASE_URL)
  const body = await c.req.json<{
    username: string
    displayName?: string
    fcmToken?: string
  }>()

  if (!body.username) {
    return c.json({ error: 'Username is required' }, 400)
  }

  // Generate a random pair code e.g. EMIL-8492
  const pairCode = `${body.username.toUpperCase().slice(0, 4)}-${Math.floor(1000 + Math.random() * 9000)}`

  const profile = await db.profile.upsert({
    where: { username: body.username },
    update: {
      displayName: body.displayName,
      fcmToken: body.fcmToken,
    },
    create: {
      username: body.username,
      displayName: body.displayName || body.username,
      pairCode: pairCode,
      fcmToken: body.fcmToken,
    },
    include: {
      partner: true
    }
  })

  return c.json({ profile })
})

// 2. Link with Partner via Pair Code
app.post('/api/pair', async (c) => {
  const db = getPrisma(c.env.DATABASE_URL)
  const { userId, pairCode } = await c.req.json<{
    userId: string
    pairCode: string
  }>()

  const partnerProfile = await db.profile.findUnique({
    where: { pairCode: pairCode.trim().toUpperCase() }
  })

  if (!partnerProfile) {
    return c.json({ error: 'Pair code not found' }, 404)
  }

  if (partnerProfile.id === userId) {
    return c.json({ error: 'You cannot pair with yourself' }, 400)
  }

  // Link both users to each other
  await db.$transaction([
    db.profile.update({
      where: { id: userId },
      data: { partnerId: partnerProfile.id }
    }),
    db.profile.update({
      where: { id: partnerProfile.id },
      data: { partnerId: userId }
    })
  ])

  return c.json({
    success: true,
    message: 'Paired successfully!',
    partner: partnerProfile
  })
})

// 3. Post a Widget Update & Notify Partner
app.post('/api/updates', async (c) => {
  const db = getPrisma(c.env.DATABASE_URL)
  const { senderId, imageUrl, caption, locationName } = await c.req.json<{
    senderId: string
    imageUrl: string
    caption?: string
    locationName?: string
  }>()

  if (!senderId || !imageUrl) {
    return c.json({ error: 'senderId and imageUrl are required' }, 400)
  }

  const newUpdate = await db.widgetUpdate.create({
    data: {
      senderId,
      imageUrl,
      caption,
      locationName
    },
    include: {
      sender: {
        include: {
          partner: true
        }
      }
    }
  })

  // Partner's FCM Token for push notification
  const partnerFcmToken = newUpdate.sender.partner?.fcmToken

  return c.json({
    success: true,
    update: newUpdate,
    partnerFcmToken: partnerFcmToken || null
  })
})

// 4. Get Latest Update for Home Widget
app.get('/api/updates/latest/:userId', async (c) => {
  const db = getPrisma(c.env.DATABASE_URL)
  const userId = c.req.param('userId')

  const user = await db.profile.findUnique({
    where: { id: userId },
    include: { partner: true }
  })

  if (!user || !user.partnerId) {
    return c.json({ error: 'User or partner not found' }, 404)
  }

  const latestUpdate = await db.widgetUpdate.findFirst({
    where: { senderId: user.partnerId },
    orderBy: { createdAt: 'desc' },
    include: { sender: true }
  })

  return c.json({ latestUpdate })
})

export default app
