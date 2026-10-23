import { Client } from 'pg'
import dotenv from 'dotenv'

dotenv.config()

const client = new Client({
  connectionString: process.env.DATABASE_URL
})

async function setupUserAuthTrigger() {
  await client.connect()
  console.log('Connecting to apply auth.users -> public."User" trigger & foreign key...')

  try {
    await client.query(`
      -- 1. Foreign Key from public."User".id to auth.users.id
      ALTER TABLE public."User" 
      DROP CONSTRAINT IF EXISTS user_id_fkey,
      ADD CONSTRAINT user_id_fkey 
      FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;

      -- 2. Trigger function to sync Google OAuth / Auth user into public."User"
      CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
      RETURNS trigger AS $$
      DECLARE
        user_email text;
        clean_username text;
        user_display_name text;
        user_avatar_url text;
        generated_code text;
      BEGIN
        user_email := coalesce(new.email, '');
        
        -- Extract display name and avatar from Google OAuth metadata
        user_display_name := coalesce(
          new.raw_user_meta_data->>'full_name',
          new.raw_user_meta_data->>'name',
          split_part(user_email, '@', 1)
        );
        
        user_avatar_url := coalesce(
          new.raw_user_meta_data->>'avatar_url',
          new.raw_user_meta_data->>'picture',
          null
        );

        -- Generate unique username based on email or name
        clean_username := lower(regexp_replace(coalesce(new.raw_user_meta_data->>'name', split_part(user_email, '@', 1)), '[^a-zA-Z0-9]', '', 'g'));
        IF clean_username = '' THEN
          clean_username := 'user' || floor(1000 + random() * 9000)::text;
        END IF;

        -- Generate pair code e.g. EMIL-4819
        generated_code := upper(substring(clean_username from 1 for 4)) || '-' || floor(1000 + random() * 9000)::text;

        INSERT INTO public."User" (
          id,
          email,
          username,
          display_name,
          avatar_url,
          pair_code,
          have_password,
          failed_attempts
        )
        VALUES (
          new.id,
          user_email,
          clean_username || '_' || floor(100 + random() * 900)::text,
          user_display_name,
          user_avatar_url,
          generated_code,
          false,
          0
        )
        ON CONFLICT (id) DO UPDATE SET
          email = EXCLUDED.email,
          display_name = COALESCE(public."User".display_name, EXCLUDED.display_name),
          avatar_url = COALESCE(public."User".avatar_url, EXCLUDED.avatar_url);

        RETURN new;
      END;
      $$ LANGUAGE plpgsql SECURITY DEFINER;

      -- 3. Attach trigger to auth.users
      DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
      CREATE TRIGGER on_auth_user_created
        AFTER INSERT ON auth.users
        FOR EACH ROW EXECUTE FUNCTION public.handle_new_auth_user();

      -- 4. Enable Row Level Security (RLS)
      ALTER TABLE public."User" ENABLE ROW LEVEL SECURITY;
      ALTER TABLE public.widget_updates ENABLE ROW LEVEL SECURITY;

      DROP POLICY IF EXISTS "Allow authenticated read users" ON public."User";
      CREATE POLICY "Allow authenticated read users"
      ON public."User" FOR SELECT TO authenticated USING (true);

      DROP POLICY IF EXISTS "Allow users update own profile" ON public."User";
      CREATE POLICY "Allow users update own profile"
      ON public."User" FOR UPDATE TO authenticated USING (auth.uid() = id);

      DROP POLICY IF EXISTS "Allow couple read widget updates" ON public.widget_updates;
      CREATE POLICY "Allow couple read widget updates"
      ON public.widget_updates FOR SELECT TO authenticated
      USING (
        sender_id = auth.uid() OR 
        sender_id IN (SELECT partner_id FROM public."User" WHERE id = auth.uid())
      );

      DROP POLICY IF EXISTS "Allow user insert own updates" ON public.widget_updates;
      CREATE POLICY "Allow user insert own updates"
      ON public.widget_updates FOR INSERT TO authenticated
      WITH CHECK (sender_id = auth.uid());
    `)

    console.log('Successfully configured auth.users -> public."User" sync trigger and RLS!')
  } catch (error) {
    console.error('Error applying user trigger:', error)
  } finally {
    await client.end()
  }
}

setupUserAuthTrigger()
