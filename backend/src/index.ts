import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import { getDb } from './db/connection';

import rateLimit from 'express-rate-limit';

import profileRouter from './routes/profile';
import entriesRouter from './routes/entries';
import transcribeRouter from './routes/transcribe';
import analyzeRouter from './routes/analyze';
import reviewsRouter from './routes/reviews';
import goalsRouter from './routes/goals';
import actionItemsRouter from './routes/actionItems';
import trajectoryRouter from './routes/trajectory';
import notificationsRouter from './routes/notifications';
import chatRouter from './routes/chat';
import todayRouter from './routes/today';
import coachingRouter from './routes/coaching';
import { getConfiguredProvider } from './services/coaching/provider';
import { coachingRateLimit } from './middleware/coachingRateLimit';
import { contentSafeErrorHandler, requestContext } from './middleware/requestContext';
import { readDeviceAuthConfig } from './config/deviceAuth';
import { DeviceCredentialStore } from './auth/deviceCredentials';
import { createDeviceAuthentication } from './middleware/deviceAuthentication';
import { createDeviceEnrollmentRouter } from './routes/deviceEnrollment';

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(requestContext);
app.use(helmet());
app.use(cors());
app.use(express.json({ limit: '10mb' }));

// Init DB on startup
getDb();

// Validate provider, model, and pricing configuration before accepting traffic.
getConfiguredProvider();

const deviceAuthConfig = readDeviceAuthConfig();
let deviceCredentialStore: DeviceCredentialStore | null = null;
if (deviceAuthConfig.required) {
  deviceCredentialStore = new DeviceCredentialStore({
    databasePath: deviceAuthConfig.databasePath,
    pepper: deviceAuthConfig.pepper,
  });
  deviceCredentialStore.registerEnrollmentCode(
    deviceAuthConfig.enrollmentCode,
    deviceAuthConfig.enrollmentExpiresAt,
  );
}

// Legacy limiter for existing AI-heavy routes.
const aiRateLimit = rateLimit({
  windowMs: 60 * 1000,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, error: { code: 'RATE_LIMITED', message: 'Too many requests, please wait a moment.' } },
});

const enrollmentRateLimit = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    error: { code: 'RATE_LIMITED', message: 'Too many enrollment attempts, please wait.' },
  },
});

// Routes
if (deviceCredentialStore !== null) {
  app.use(
    '/api/v1/device-enrollments',
    enrollmentRateLimit,
    createDeviceEnrollmentRouter(deviceCredentialStore),
  );
  app.use('/api/v1', createDeviceAuthentication(deviceCredentialStore));
}
app.use('/api/v1/profile', profileRouter);
app.use('/api/v1/entries', entriesRouter);
app.use('/api/v1/transcribe', aiRateLimit, transcribeRouter);
app.use('/api/v1/analyze', aiRateLimit, analyzeRouter);
app.use('/api/v1/reviews', reviewsRouter);
app.use('/api/v1/goals', goalsRouter);
app.use('/api/v1/action-items', actionItemsRouter);
app.use('/api/v1/trajectory', trajectoryRouter);
app.use('/api/v1/notifications', notificationsRouter);
app.use('/api/v1/chat', aiRateLimit, chatRouter);
app.use('/api/v1/today', todayRouter);
app.use('/api/v1/coaching', coachingRateLimit, coachingRouter);

// Health check
app.get('/health', (_req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Error handler
app.use(contentSafeErrorHandler);

app.listen(PORT, () => {
  console.log(`Taisa backend running on http://localhost:${PORT}`);
});

export default app;
