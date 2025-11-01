import fetch from 'node-fetch';

const testLogin = async (employeeId, pin) => {
  try {
    const response = await fetch('http://localhost:5000/api/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ employee_id: employeeId, pin }),
    });
    
    const data = await response.json();
    console.log(`\n🔐 Login attempt for ${employeeId}:`);
    console.log('Status:', response.status);
    console.log('Response:', JSON.stringify(data, null, 2));
  } catch (err) {
    console.error('Error:', err.message);
  }
};

// Test with common PINs
await testLogin('OWNER001', '1234');
await testLogin('ll', '1234');
await testLogin('mody', '1234');
