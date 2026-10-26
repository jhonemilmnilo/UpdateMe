const { Client } = require('pg');

const client = new Client({
  connectionString: 'postgresql://postgres.afxnbhuabjppjlijmcly:Jhonemilnilo%2312@aws-0-ap-northeast-1.pooler.supabase.com:5432/postgres'
});

async function run() {
  await client.connect();
  const rls = await client.query(`
    SELECT tablename, rowsecurity 
    FROM pg_tables 
    WHERE schemaname = 'public' AND tablename = 'Updates';
  `);
  console.log('RLS Status:', rls.rows);

  const policies = await client.query(`
    SELECT policyname, permissive, roles, cmd, qual, with_check 
    FROM pg_policies 
    WHERE tablename = 'Updates';
  `);
  console.log('Policies:', policies.rows);

  await client.end();
}

run().catch(console.error);
