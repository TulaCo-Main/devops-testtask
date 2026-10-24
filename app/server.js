const express = require('express');

const app = express();

const PORT = parseInt(process.env.PORT, 10) || 3000;
const HOST = process.env.HOST || '0.0.0.0';
let shuttingDown = false;

app.get('/', (req, res) => {
  const body = {
    message: 'Hello from the DevOps test-task Node.js app',
    hostname: require('os').hostname(),
    podIP: process.env.POD_IP || null,
    time: new Date().toISOString(),
  };
  res.json(body);
});

app.get('/health', (req, res) => {
  res.status(shuttingDown ? 503 : 200).json({ status: shuttingDown ? 'draining' : 'ok' });
});

const server = app.listen(PORT, HOST, () => {
  console.log(`nodeapp listening on http://${HOST}:${PORT}`);
});

// Graceful shutdown so Kubernetes terminations are clean.
const shutdown = (signal) => () => {
  if (shuttingDown) return;
  shuttingDown = true;
  console.log(`Received ${signal}, shutting down.`);
  const timeout = setTimeout(() => {
    console.error('Shutdown timed out; closing remaining connections.');
    server.closeAllConnections();
    process.exit(1);
  }, 20000);
  timeout.unref();
  server.close((error) => {
    clearTimeout(timeout);
    process.exit(error ? 1 : 0);
  });
};
process.on('SIGTERM', shutdown('SIGTERM'));
process.on('SIGINT', shutdown('SIGINT'));
