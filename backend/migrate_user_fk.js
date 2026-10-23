const { Client } = require('pg');

const client = new Client({
  connectionString: 'postgresql://postgres.afxnbhuabjppjlijmcly:Jhonemilnilo%2312@aws-0-ap-northeast-1.pooler.supabase.com:5432/postgres'
});

async function run() {
  await client.connect();
  console.log('Connected to Supabase PostgreSQL!');

  await client.query('ALTER TABLE "User" DROP CONSTRAINT IF EXISTS user_id_fkey;');
  console.log('Successfully dropped user_id_fkey constraint!');

  await client.query('ALTER TABLE "User" ALTER COLUMN id SET DEFAULT gen_random_uuid();');
  console.log('Successfully set id DEFAULT gen_random_uuid()!');

  await client.end();
}

run().catch(err => {
  console.error('Error running migration:', err);
  process.exit(1);
});
