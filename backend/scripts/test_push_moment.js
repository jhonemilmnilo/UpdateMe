const { Client } = require('pg');
const { JWT } = require('google-auth-library');
const https = require('https');
const serviceAccount = require('../service-account.json');

async function getAccessToken() {
  const jwt = new JWT({
    email: serviceAccount.client_email,
    key: serviceAccount.private_key,
    scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
  });
  const res = await jwt.authorize();
  return res.access_token;
}

async function testPush() {
  const client = new Client({
    connectionString: 'postgresql://postgres.afxnbhuabjppjlijmcly:Jhonemilnilo%2312@aws-0-ap-northeast-1.pooler.supabase.com:5432/postgres'
  });
  await client.connect();

  const senderId = '7068d17a-8130-4ab4-9c6b-d84ecfa94949';
  const targetReceiverId = 'e6247193-5176-4039-b7fa-41df91576604';

  const resReceiver = await client.query('SELECT fcm_token, display_name FROM "User" WHERE id = $1', [targetReceiverId]);
  const receiver = resReceiver.rows[0];
  console.log('Receiver:', receiver);

  const resSender = await client.query('SELECT display_name, email FROM "User" WHERE id = $1', [senderId]);
  const senderInfo = resSender.rows[0];
  console.log('Sender:', senderInfo);

  const token = await getAccessToken();

  const payload = {
    message: {
      token: receiver.fcm_token,
      notification: {
        title: 'UpdateMe 📸',
        body: `${senderInfo.display_name}: "nakakdkamx"`,
      },
      android: {
        priority: 'HIGH',
        notification: {
          channel_id: 'updateme_high_importance',
          sound: 'default',
          default_sound: true,
          default_vibrate_timings: true,
          visibility: 'PUBLIC',
        },
      },
      data: {
        type: 'new_moment',
        caption: 'nakakdkamx',
      },
    },
  };

  const req = https.request(
    `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
      },
    },
    (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => console.log('FCM response status:', res.statusCode, body));
    }
  );

  req.write(JSON.stringify(payload));
  req.end();

  await client.end();
}

testPush().catch(console.error);
