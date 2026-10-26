const https = require('https');

const postData = JSON.stringify({
  senderId: '7068d17a-8130-4ab4-9c6b-d84ecfa94949',
  receiverId: 'e6247193-5176-4039-b7fa-41df91576604',
  imageUrl: 'https://afxnbhuabjppjlijmcly.supabase.co/storage/v1/object/public/UpdateMe/photos/7068d17a-8130-4ab4-9c6b-d84ecfa94949_1792993343510.jpg',
  caption: 'Live test notification from worker!',
  locationName: 'DAGUPAN, Rehiyong Ilocos',
});

const req = https.request('https://update-me-backend.nilojhonemil1.workers.dev/api/updates', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(postData),
  },
}, (res) => {
  let body = '';
  res.on('data', chunk => body += chunk);
  res.on('end', () => console.log('POST status:', res.statusCode, body));
});

req.on('error', console.error);
req.write(postData);
req.end();
