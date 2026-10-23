import { Client } from 'pg'
import dotenv from 'dotenv'

dotenv.config()

const client = new Client({
  connectionString: process.env.DATABASE_URL
})

async function setupAuthTrigger() {
  await client.connect()
  console.log('Connecting to apply auth.users -> public.profiles foreign key and trigger...')

  try {
    await client.query(`
      -- 1. Add foreign key from public.profiles.id to auth.users.id
      ALTER TABLE public.profiles 
      DROP CONSTRAINT IF EXISTS profiles_id_fkey,
      ADD CONSTRAINT profiles_id_fkey 
      FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;

      -- 2. Create the auto-profile trigger function
      CREATE OR REPLACE FUNCTION public.handle_new_user()
      RETURNS trigger AS $$
      DECLARE
        clean_username text;
        generated_code text;
      BEGIN
        clean_username := lower(coalesce(new.raw_user_meta_data->>'username', split_part(new.email, '@', 1)));
        generated_code := upper(substring(clean_username from 1 for 4)) || '-' || floor(1000 + random() * 9000)::text;

        INSERT INTO public.profiles (id, username, display_name, pair_code)
        VALUES (
          new.id,
          clean_username,
          coalesce(new.raw_user_meta_data->>'display_name', clean_username),
          generated_code
        )
        ON CONFLICT (id) DO NOTHING;

        RETURN new;
      END;
      $$ LANGUAGE plpgsql SECURITY DEFINER;

      -- 3. Attach trigger to auth.users
      DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
      CREATE TRIGGER on_auth_user_created
        AFTER INSERT ON auth.users
        FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

      -- 4. Enable Row Level Security (RLS)
      ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
      ALTER TABLE public.widget_updates ENABLE ROW LEVEL SECURITY;

      DROP POLICY IF EXISTS "Allow authenticated read profiles" ON public.profiles;
      CREATE POLICY "Allow authenticated read profiles"
      ON public.profiles FOR SELECT TO authenticated USING (true);

      DROP POLICY IF EXISTS "Allow users update own profile" ON public.profiles;
      CREATE POLICY "Allow users update own profile"
      ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = id);

      DROP POLICY IF EXISTS "Allow couple read widget updates" ON public.widget_updates;
      CREATE POLICY "Allow couple read widget updates"
      ON public.widget_updates FOR SELECT TO authenticated
      USING (
        sender_id = auth.uid() OR 
        sender_id IN (SELECT partner_id FROM public.profiles WHERE id = auth.uid())
      );

      DROP POLICY IF EXISTS "Allow user insert own updates" ON public.widget_updates;
      CREATE POLICY "Allow user insert own updates"
      ON public.widget_updates FOR INSERT TO authenticated
      WITH CHECK (sender_id = auth.uid());
    `)

    console.log('Successfully configured auth.users Foreign Key, Triggers, and RLS Policies!')
  } catch (error) {
    console.error('Error applying trigger:', error)
  } finally {
    await client.end()
  }
}

setupAuthTrigger()
