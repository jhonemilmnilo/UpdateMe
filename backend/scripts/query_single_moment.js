const { Client } = require('pg');

async function main() {
  const client = new Client({
    connectionString: 'postgresql://postgres.afxnbhuabjppjlijmcly:Jhonemilnilo%2312@aws-0-ap-northeast-1.pooler.supabase.com:5432/postgres'
  });
  await client.connect();

  const res = await client.query('SELECT * FROM "Updates" WHERE id = $1;', ['e8adcbb3-8927-429d-83f6-d07ddbb0a82c']);
  console.log(JSON.stringify(res.rows[0], null, 2));

  await client.end();
}

main().catch(console.error);
