const { Client } = require('pg');

async function main() {
  const client = new Client({
    connectionString: 'postgresql://postgres.afxnbhuabjppjlijmcly:Jhonemilnilo%2312@aws-0-ap-northeast-1.pooler.supabase.com:5432/postgres'
  });
  await client.connect();

  const user1 = 'e6247193-5176-4039-b7fa-41df91576604';
  const user2 = '7068d17a-8130-4ab4-9c6b-d84ecfa94949';

  const res1 = await client.query('SELECT count(*) FROM "Updates" WHERE sender_id = $1 AND receiver_id = $2;', [user1, user2]);
  const res2 = await client.query('SELECT count(*) FROM "Updates" WHERE sender_id = $2 AND receiver_id = $1;', [user2, user1]);

  console.log(`Updates sent by user1 (${user1}) to user2 (${user2}): ${res1.rows[0].count}`);
  console.log(`Updates sent by user2 (${user2}) to user1 (${user1}): ${res2.rows[0].count}`);

  const user1Sent = await client.query('SELECT id, caption, created_at FROM "Updates" WHERE sender_id = $1 ORDER BY created_at ASC;', [user1]);
  console.log('\n--- All updates sent by user1 (e6247...) ---');
  console.table(user1Sent.rows);

  const user2Sent = await client.query('SELECT id, caption, created_at FROM "Updates" WHERE sender_id = $1 ORDER BY created_at ASC;', [user2]);
  console.log('\n--- All updates sent by user2 (7068d...) ---');
  console.table(user2Sent.rows);

  await client.end();
}

main().catch(console.error);
