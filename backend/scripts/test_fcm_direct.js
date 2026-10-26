const { JWT } = require('google-auth-library');
const serviceAccount = require('../service-account.json');

async function testDirectFCM() {
  console.log('1. Testing JWT authorization with Google Auth...');
  const jwtClient = new JWT({
    email: serviceAccount.client_email,
    key: serviceAccount.private_key,
    scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
  });

  const tokens = await jwtClient.authorize();
  console.log('2. Access token obtained:', tokens.access_token?.substring(0, 20) + '...');

  const recipientToken = 'f7Xbx9d-SDiXV-VXdJNWi0:APA91bHjiZvNWzrAvqyt3es4Y7FrFLAyPlKscPCrZNdhMvQEDx-XMySVWr6Jh2bsgZIYvt7gayp1zXVQYLJ3MbAG3qovEW2g3A-6-KHM_5eSZ6RjKTncC4g';
  const fcmUrl = `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`;

  const payload = {
    message: {
      token: recipientToken,
      notification: {
        title: 'UpdateMe 📸 Direct Test',
        body: 'Testing notification direct to phone! Can you see this?',
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
        test: 'true'
      }
    }
  };

  console.log('3. Sending push message to FCM HTTP v1...');
  const response = await fetch(fcmUrl, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${tokens.access_token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });

  console.log('4. FCM Response Status:', response.status);
  const text = await response.text();
  console.log('5. FCM Response Body:', text);
}

testDirectFCM().catch(console.error);
