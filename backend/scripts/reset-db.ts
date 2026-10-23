import { Client } from 'pg'
import dotenv from 'dotenv'

dotenv.config()

const client = new Client({
  connectionString: process.env.DATABASE_URL
})

async function resetDatabase() {
  await client.connect()
  console.log('Connected to PostgreSQL database...')

  try {
    console.log('Dropping old tables and functions...')
    await client.query(`
      DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users CASCADE;
      DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;
      DROP TABLE IF EXISTS public.widget_updates CASCADE;
      DROP TABLE IF EXISTS public.profiles CASCADE;
    `)
    console.log('Successfully dropped old database tables and triggers!')
  } catch (error) {
    console.error('Error dropping tables:', error)
  } finally {
    await client.end()
  }
}

resetDatabase()
