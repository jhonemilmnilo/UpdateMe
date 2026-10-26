const { Client } = require('pg');

const client = new Client({
  connectionString: 'postgresql://postgres.afxnbhuabjppjlijmcly:Jhonemilnilo%2312@aws-0-ap-northeast-1.pooler.supabase.com:5432/postgres'
});

async function run() {
  await client.connect();
  const users = await client.query('SELECT id, email, display_name, partner_id, fcm_token FROM "User";');
  console.log('=== USERS ===');
  console.log(JSON.stringify(users.rows, null, 2));

  const updates = await client.query('SELECT id, sender_id, receiver_id, created_at, is_reacted, caption FROM "Updates" ORDER BY created_at DESC LIMIT 5;');
  console.log('=== LATEST UPDATES ===');
  console.log(JSON.stringify(updates.rows, null, 2));

  const pub = await client.query("SELECT pubname, schemaname, tablename FROM pg_publication_tables WHERE pubname = 'supabase_realtime';");
  console.log('=== REALTIME TABLES ===');
  console.log(JSON.stringify(pub.rows, null, 2));

  await client.end();
}

run().catch(console.error);
