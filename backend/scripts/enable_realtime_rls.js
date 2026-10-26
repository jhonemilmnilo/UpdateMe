const { Client } = require('pg');

const client = new Client({
  connectionString: 'postgresql://postgres.afxnbhuabjppjlijmcly:Jhonemilnilo%2312@aws-0-ap-northeast-1.pooler.supabase.com:5432/postgres'
});

async function run() {
  await client.connect();
  console.log('Connected to Supabase PostgreSQL!');

  const sql = `
    -- 1. Enable RLS and add full SELECT policy on Updates table
    ALTER TABLE "Updates" ENABLE ROW LEVEL SECURITY;
    
    DROP POLICY IF EXISTS "Allow Read Updates" ON "Updates";
    DROP POLICY IF EXISTS "Allow All Updates" ON "Updates";

    CREATE POLICY "Allow Read Updates"
    ON "Updates" FOR SELECT
    TO anon, authenticated
    USING ( true );

    -- 2. Verify publication contains Updates table
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'Updates'
      ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE "Updates";
      END IF;
    END $$;

    -- 3. Set REPLICA IDENTITY FULL to ensure all fields are broadcasted on update
    ALTER TABLE "Updates" REPLICA IDENTITY FULL;
  `;

  await client.query(sql);
  console.log('Successfully configured Realtime RLS policies and publication on Updates table! ⚡');

  // Verify
  const policies = await client.query(`
    SELECT policyname, permissive, roles, cmd, qual 
    FROM pg_policies 
    WHERE tablename = 'Updates';
  `);
  console.log('Active Policies:', policies.rows);

  await client.end();
}

run().catch(err => {
  console.error('Error:', err);
  process.exit(1);
});
