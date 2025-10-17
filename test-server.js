import http from 'http';

const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ status: 'ok', message: 'Test server works!' }));
});

server.listen(5000, '0.0.0.0', () => {
  console.log('✅ Test server running on http://localhost:5000');
});

server.on('error', (error) => {
  console.error('❌ Server error:', error);
  process.exit(1);
});
