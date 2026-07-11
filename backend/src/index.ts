import express from 'express';

const app = express();
app.use(express.json());

app.get('/health', (_req, res) => {
  res.json({
    status: 'ok',
    service: 'navish-backend',
    time: new Date().toISOString(),
  });
});

const PORT = process.env.PORT ?? 4000;
app.listen(PORT, () => {
  console.log(`Navish backend running on http://localhost:${PORT}`);
});