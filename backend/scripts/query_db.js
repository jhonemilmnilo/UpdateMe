const { Client } = require('pg');

async function main() {
  const client = new Client({
    connectionString: 'postgresql://postgres.afxnbhuabjppjlijmcly:Jhonemilnilo%2312@aws-0-ap-northeast-1.pooler.supabase.com:5432/postgres'
  });
  await client.connect();
  const res = await client.query('SELECT id, sender_id, receiver_id, caption, created_at FROM "Updates" ORDER BY created_at DESC LIMIT 10;');
  console.log(JSON.stringify(res.rows, null, 2));
  await client.end();
}

main().catch(console.error);
