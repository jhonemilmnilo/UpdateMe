import { Receiver } from '@upstash/qstash'
import type { SupabaseClient } from '@supabase/supabase-js'

const PH_OFFSET_MS = 8 * 60 * 60 * 1000 // Asia/Manila (UTC+8, no DST)
const STORAGE_BUCKET = 'UpdateMe'
const STORAGE_PUBLIC_MARKER = `/storage/v1/object/public/${STORAGE_BUCKET}/`

export interface PhCutoffWindow {
  phDate: string
  cutoffIso: string
}

/**
 * Computes the exact start of the current Philippine calendar day (00:00:00 +08:00)
 * expressed in UTC ISO-8601 format.
 * Example: At Nov 24 00:01 PH Time (Nov 23 16:01Z), cutoff is Nov 23 16:00:00.000Z.
 * Everything strictly before this cutoff belongs to previous days and will be deleted.
 */
export function getStartOfTodayPhUtc(now: Date = new Date()): PhCutoffWindow {
  const phNow = new Date(now.getTime() + PH_OFFSET_MS)
  const phDate = phNow.toISOString().slice(0, 10)
  const startOfTodayPh = new Date(`${phDate}T00:00:00+08:00`)

  return {
    phDate,
    cutoffIso: startOfTodayPh.toISOString(),
  }
}

/**
 * Extracts the bucket-relative object path from a Supabase Storage public URL.
 * Returns null if the URL does not point to the UpdateMe bucket.
 */
export function extractStorageObjectPath(imageUrl: string | null | undefined): string | null {
  if (!imageUrl || typeof imageUrl !== 'string') return null
  const markerIndex = imageUrl.indexOf(STORAGE_PUBLIC_MARKER)
  if (markerIndex === -1) return null

  const rawPath = imageUrl.slice(markerIndex + STORAGE_PUBLIC_MARKER.length).split('?')[0].trim()
  if (!rawPath) return null

  try {
    return decodeURIComponent(rawPath)
  } catch {
    return rawPath
  }
}

export interface QStashVerificationResult {
  authorized: boolean
  status: 200 | 401 | 500
  error?: string
  method?: 'qstash-signature' | 'cron-secret'
}

/**
 * Verifies that the incoming request is genuinely signed by Upstash QStash
 * (or authorized via optional CRON_SECRET Bearer token if configured).
 */
export async function verifyCronRequest(params: {
  signature: string | undefined
  authHeader: string | undefined
  body: string
  url: string
  currentSigningKey?: string
  nextSigningKey?: string
  cronSecret?: string
}): Promise<QStashVerificationResult> {
  const {
    signature,
    authHeader,
    body,
    url,
    currentSigningKey,
    nextSigningKey,
    cronSecret,
  } = params

  // 1. Optional manual trigger via Bearer CRON_SECRET (only when explicitly configured)
  if (cronSecret && authHeader && authHeader === `Bearer ${cronSecret}`) {
    return { authorized: true, status: 200, method: 'cron-secret' }
  }

  // 2. Primary cryptographic verification via Upstash QStash signature
  if (!currentSigningKey || !nextSigningKey) {
    console.error('[Cron] Missing QSTASH_CURRENT_SIGNING_KEY or QSTASH_NEXT_SIGNING_KEY secrets.')
    return {
      authorized: false,
      status: 500,
      error: 'QStash signing keys are not configured on the worker.',
    }
  }

  if (!signature) {
    return {
      authorized: false,
      status: 401,
      error: 'Missing Upstash-Signature header.',
    }
  }

  try {
    const receiver = new Receiver({
      currentSigningKey,
      nextSigningKey,
    })

    const isValid = await receiver.verify({
      signature,
      body,
      url,
    })

    if (!isValid) {
      return {
        authorized: false,
        status: 401,
        error: 'Invalid Upstash-Signature.',
      }
    }

    return { authorized: true, status: 200, method: 'qstash-signature' }
  } catch (err: any) {
    console.error('[Cron] QStash signature verification failed:', err?.message || err)
    return {
      authorized: false,
      status: 401,
      error: `Signature verification failed: ${err?.message || 'invalid signature'}`,
    }
  }
}

export interface CleanupUpdatesResult {
  success: boolean
  phDate: string
  cutoffUtc: string
  deletedRows: number
  deletedImages: number
  skippedSharedImages: number
  storageErrors: string[]
}

/**
 * Deletes all Updates rows strictly older than today's PH calendar date (00:00 +08:00)
 * along with their associated photo objects in Supabase Storage (skipping any file
 * still referenced by a kept current-date row).
 */
export async function cleanupPreviousUpdates(
  supabase: SupabaseClient,
  now: Date = new Date()
): Promise<CleanupUpdatesResult> {
  const { phDate, cutoffIso } = getStartOfTodayPhUtc(now)

  // 1. Fetch all outdated rows strictly before today's PH midnight
  const { data: outdatedRows, error: fetchErr } = await supabase
    .from('Updates')
    .select('id, image_url')
    .lt('created_at', cutoffIso)

  if (fetchErr) {
    console.error('[Cron] Error querying outdated updates:', fetchErr.message)
    throw new Error(`Failed to query outdated updates: ${fetchErr.message}`)
  }

  if (!outdatedRows || outdatedRows.length === 0) {
    console.log(`[Cron] No outdated updates before ${cutoffIso} (PH date ${phDate}). Nothing to delete.`)
    return {
      success: true,
      phDate,
      cutoffUtc: cutoffIso,
      deletedRows: 0,
      deletedImages: 0,
      skippedSharedImages: 0,
      storageErrors: [],
    }
  }

  // 2. Collect storage paths still referenced by kept today rows so we never delete a shared image
  const { data: keptRows, error: keptErr } = await supabase
    .from('Updates')
    .select('image_url')
    .gte('created_at', cutoffIso)

  if (keptErr) {
    console.error('[Cron] Error querying kept updates for storage safety check:', keptErr.message)
    throw new Error(`Failed to verify kept updates: ${keptErr.message}`)
  }

  const protectedPaths = new Set<string>()
  for (const row of keptRows || []) {
    const path = extractStorageObjectPath(row.image_url)
    if (path) protectedPaths.add(path)
  }

  // 3. Deduplicate candidate storage paths and exclude protected ones
  const candidatePaths = new Set<string>()
  let skippedSharedImages = 0

  for (const row of outdatedRows) {
    const path = extractStorageObjectPath(row.image_url)
    if (!path) continue
    if (protectedPaths.has(path)) {
      skippedSharedImages++
      continue
    }
    candidatePaths.add(path)
  }

  // 4. Batch-delete storage files in chunks of 100
  const pathsToDelete = Array.from(candidatePaths)
  let deletedImages = 0
  const storageErrors: string[] = []
  const STORAGE_CHUNK_SIZE = 100

  for (let i = 0; i < pathsToDelete.length; i += STORAGE_CHUNK_SIZE) {
    const chunk = pathsToDelete.slice(i, i + STORAGE_CHUNK_SIZE)
    const { data: removed, error: removeErr } = await supabase.storage
      .from(STORAGE_BUCKET)
      .remove(chunk)

    if (removeErr) {
      console.error(`[Cron] Storage remove error (chunk ${i}):`, removeErr.message)
      storageErrors.push(removeErr.message)
    } else {
      deletedImages += removed?.length ?? chunk.length
    }
  }

  // 5. Delete exact matched outdated rows from Updates table in chunks of 200
  const outdatedIds = outdatedRows.map((r) => r.id)
  let deletedRows = 0
  const DB_CHUNK_SIZE = 200

  for (let i = 0; i < outdatedIds.length; i += DB_CHUNK_SIZE) {
    const idChunk = outdatedIds.slice(i, i + DB_CHUNK_SIZE)
    const { error: deleteErr } = await supabase
      .from('Updates')
      .delete()
      .in('id', idChunk)

    if (deleteErr) {
      console.error(`[Cron] DB delete error (chunk ${i}):`, deleteErr.message)
      throw new Error(`Failed to delete outdated updates: ${deleteErr.message}`)
    }
    deletedRows += idChunk.length
  }

  console.log(
    `[Cron] Cleanup complete for PH date ${phDate} (cutoff ${cutoffIso}): deletedRows=${deletedRows}, deletedImages=${deletedImages}, skippedShared=${skippedSharedImages}`
  )

  return {
    success: true,
    phDate,
    cutoffUtc: cutoffIso,
    deletedRows,
    deletedImages,
    skippedSharedImages,
    storageErrors,
  }
}
