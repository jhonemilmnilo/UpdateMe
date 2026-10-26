const { Client } = require('pg');

const client = new Client({
  connectionString: 'postgresql://postgres.afxnbhuabjppjlijmcly:Jhonemilnilo%2312@aws-0-ap-northeast-1.pooler.supabase.com:5432/postgres'
});

async function run() {
  await client.connect();
  const testId = 'ea50b3ac-a255-4838-8ae5-d9362eaa610a';
  console.log('Toggling reaction on test moment...');
  const res = await client.query('UPDATE "Updates" SET is_reacted = NOT is_reacted WHERE id = $1 RETURNING id, is_reacted;', [testId]);
  console.log('Update result:', res.rows[0]);
  await client.end();
}

run().catch(console.error);
