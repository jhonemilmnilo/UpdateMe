import serviceAccount from '../service-account.json'

let cachedToken: { token: string; expiresAt: number } | null = null

/**
 * Base64URL encoder helper for Edge / Workers
 */
function base64UrlEncode(str: string): string {
  return btoa(str)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '')
}

function arrayBufferToBase64Url(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer)
  let binary = ''
  for (let i = 0; i < bytes.byteLength; i++) {
    binary += String.fromCharCode(bytes[i])
  }
  return btoa(binary)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '')
}

/**
 * Converts a PEM formatted PKCS#8 private key into a CryptoKey using Web Crypto API.
 * 100% compatible with Cloudflare Workers, Node.js 18+, V8, and Edge runtimes.
 */
async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const pemHeader = '-----BEGIN PRIVATE KEY-----'
  const pemFooter = '-----END PRIVATE KEY-----'
  const pemContents = pem
    .replace(pemHeader, '')
    .replace(pemFooter, '')
    .replace(/\s+/g, '')

  const binaryDerString = atob(pemContents)
  const binaryDer = new Uint8Array(binaryDerString.length)
  for (let i = 0; i < binaryDerString.length; i++) {
    binaryDer[i] = binaryDerString.charCodeAt(i)
  }

  return await crypto.subtle.importKey(
    'pkcs8',
    binaryDer.buffer,
    {
      name: 'RSASSA-PKCS1-v1_5',
      hash: 'SHA-256',
    },
    false,
    ['sign']
  )
}

/**
 * Signs a JWT with RS256 using the native Web Crypto API and exchanges it with Google OAuth2
 */
async function getGoogleAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  if (cachedToken && cachedToken.expiresAt > now + 60) {
    return cachedToken.token
  }

  const header = {
    alg: 'RS256',
    typ: 'JWT',
  }

  const claimSet = {
    iss: serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    exp: now + 3600,
    iat: now,
  }

  const encodedHeader = base64UrlEncode(JSON.stringify(header))
  const encodedClaimSet = base64UrlEncode(JSON.stringify(claimSet))
  const signingInput = `${encodedHeader}.${encodedClaimSet}`

  const privateKey = await importPrivateKey(serviceAccount.private_key)
  const encoder = new TextEncoder()
  const signatureBuffer = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    privateKey,
    encoder.encode(signingInput)
  )

  const encodedSignature = arrayBufferToBase64Url(signatureBuffer)
  const assertion = `${signingInput}.${encodedSignature}`

  // Exchange assertion for Google OAuth2 Access Token
  const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  })

  if (!tokenResponse.ok) {
    const errorText = await tokenResponse.text()
    throw new Error(`Google OAuth2 token exchange failed: ${tokenResponse.status} ${errorText}`)
  }

  const tokenData = await tokenResponse.json() as { access_token: string; expires_in: number }

  cachedToken = {
    token: tokenData.access_token,
    expiresAt: now + (tokenData.expires_in || 3600),
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
