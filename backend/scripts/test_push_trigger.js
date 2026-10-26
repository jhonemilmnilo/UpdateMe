const { Client } = require('pg');

async function testPush() {
  const backendUrl = 'https://update-me-backend.nilojhonemil1.workers.dev';
  
  // Test moment ID from Jhon Emil Maganis to Jhon Emil Nilo
  const testMomentId = 'ea50b3ac-a255-4838-8ae5-d9362eaa610a';
  
  console.log('Testing PATCH /api/updates/:id/react with reaction trigger to send push notification...');
  
  const response = await fetch(`${backendUrl}/api/updates/${testMomentId}/react`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ isReacted: true })
  });

  const resJson = await response.json();
  console.log('Backend response:', resJson);
}

testPush().catch(console.error);
