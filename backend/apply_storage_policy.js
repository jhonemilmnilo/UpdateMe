const { Client } = require('pg');

const client = new Client({
  connectionString: 'postgresql://postgres.afxnbhuabjppjlijmcly:Jhonemilnilo%2312@aws-0-ap-northeast-1.pooler.supabase.com:5432/postgres'
});

async function run() {
  await client.connect();
  console.log('Connected to Supabase PostgreSQL!');

  const sql = `
    DROP POLICY IF EXISTS "Public Read UpdateMe" ON storage.objects;
    DROP POLICY IF EXISTS "Allow Upload UpdateMe" ON storage.objects;
    DROP POLICY IF EXISTS "Allow Update UpdateMe" ON storage.objects;

    CREATE POLICY "Public Read UpdateMe"
    ON storage.objects FOR SELECT
    USING ( bucket_id = 'UpdateMe' );

    CREATE POLICY "Allow Upload UpdateMe"
    ON storage.objects FOR INSERT
    WITH CHECK ( bucket_id = 'UpdateMe' );

    CREATE POLICY "Allow Update UpdateMe"
    ON storage.objects FOR UPDATE
    USING ( bucket_id = 'UpdateMe' );
  `;

  await client.query(sql);
  console.log('Successfully applied UpdateMe bucket storage policies!');

  await client.end();
}

run().catch(err => {
  console.error('Error:', err);
  process.exit(1);
});
