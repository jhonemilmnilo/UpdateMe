import { JWT } from 'google-auth-library'
import serviceAccount from '../service-account.json'

let cachedToken: { token: string; expiresAt: number } | null = null

/**
 * Generates an OAuth2 Google Access Token using the Firebase Service Account.
 * Automatically caches token until near expiration.
 */
async function getGoogleAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  if (cachedToken && cachedToken.expiresAt > now + 60) {
    return cachedToken.token
  }

  const jwtClient = new JWT({
    email: serviceAccount.client_email,
    key: serviceAccount.private_key,
    scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
  })

  const tokens = await jwtClient.authorize()
  if (!tokens.access_token) {
    throw new Error('Failed to obtain Google access token for FCM')
  }

  cachedToken = {
    token: tokens.access_token,
    expiresAt: tokens.expiry_date ? Math.floor(tokens.expiry_date / 1000) : now + 3500,
  }

  return cachedToken.token
}

interface PushMessageOptions {
  token: string
  title: string
  body: string
  data?: Record<string, string>
}

/**
 * Sends a high-priority push notification to a device via Firebase Cloud Messaging HTTP v1 API.
 * Ensures heads-up display on Android even when the phone screen is off or app is closed.
 */
export async function sendPushNotification(options: PushMessageOptions): Promise<boolean> {
  try {
    if (!options.token) {
      console.warn('[FCM] No recipient device token provided. Skipping push.')
      return false
    }

    const accessToken = await getGoogleAccessToken()
    const projectId = serviceAccount.project_id

    const fcmUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`

    const payload = {
      message: {
        token: options.token,
        notification: {
          title: options.title,
          body: options.body,
        },
        android: {
          priority: 'HIGH',
          notification: {
            channel_id: 'updateme_high_importance',
            sound: 'default',
            priority: 'HIGH',
            default_sound: true,
            default_vibrate_timings: true,
            visibility: 'PUBLIC',
          },
        },
        data: options.data || {},
      },
    }

    const response = await fetch(fcmUrl, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
    })

    if (!response.ok) {
      const errText = await response.text()
      console.error(`[FCM] Push notification send failed (${response.status}):`, errText)
      return false
    }

    const resJson = await response.json()
    console.log('[FCM] Push notification sent successfully! 🚀 Message ID:', (resJson as any).name)
    return true
  } catch (error) {
    console.error('[FCM] Error in sendPushNotification:', error)
    return false
  }
}
