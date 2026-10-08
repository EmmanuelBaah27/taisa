import express from 'express';
import request from 'supertest';
import { DeviceCredentialStore } from '../auth/deviceCredentials';
import { createDeviceAuthentication } from '../middleware/deviceAuthentication';
import { createDeviceEnrollmentRouter } from '../routes/deviceEnrollment';

const CODE = 'single-use-enrollment-code';
const PEPPER = 'test-only-pepper-with-enough-entropy';
const future = '2099-01-01T00:00:00.000Z';

function testApp(store: DeviceCredentialStore) {
  const app = express();
  app.use(express.json());
  app.use('/enroll', createDeviceEnrollmentRouter(store));
  app.get('/private', createDeviceAuthentication(store), (_req, res) => res.json({ ok: true }));
  return app;
}

test('enrollment code is single-use across store restarts and only token digest is persisted', async () => {
  const path = `/tmp/taisa-device-auth-${process.pid}-${Date.now()}.sqlite`;
  const first = new DeviceCredentialStore({ databasePath: path, pepper: PEPPER });
  first.registerEnrollmentCode(CODE, future);
  const app = testApp(first);

  const enrolled = await request(app).post('/enroll').send({ code: CODE });
  expect(enrolled.status).toBe(201);
  expect(enrolled.body.data.token).toMatch(/^[A-Za-z0-9_-]{40,}$/);
  expect(first.inspectPersistedValues()).not.toContain(enrolled.body.data.token);
  first.close();

  const reopened = new DeviceCredentialStore({ databasePath: path, pepper: PEPPER });
  reopened.registerEnrollmentCode(CODE, future);
  const reused = await request(testApp(reopened)).post('/enroll').send({ code: CODE });
  expect(reused.status).toBe(401);
  reopened.close();
});

test('expired enrollment code is rejected without issuing a credential', async () => {
  const store = new DeviceCredentialStore({ pepper: PEPPER });
  store.registerEnrollmentCode(CODE, '2000-01-01T00:00:00.000Z');
  const response = await request(testApp(store)).post('/enroll').send({ code: CODE });
  expect(response.status).toBe(401);
  expect(store.listActiveCredentialIds()).toEqual([]);
  store.close();
});

test('private route requires a valid bearer credential and revocation is immediate', async () => {
  const store = new DeviceCredentialStore({ pepper: PEPPER });
  store.registerEnrollmentCode(CODE, future);
  const app = testApp(store);
  const enrolled = await request(app).post('/enroll').send({ code: CODE });
  const token = enrolled.body.data.token as string;

  expect((await request(app).get('/private')).status).toBe(401);
  expect((await request(app).get('/private').set('authorization', 'Bearer wrong')).status).toBe(401);
  expect((await request(app).get('/private').set('authorization', `Bearer ${token}`)).status).toBe(200);

  store.revokeCredential(enrolled.body.data.credentialId);
  expect((await request(app).get('/private').set('authorization', `Bearer ${token}`)).status).toBe(401);
  store.close();
});

test('authentication comparison handles equal-length invalid tokens without throwing', () => {
  const store = new DeviceCredentialStore({ pepper: PEPPER });
  store.registerEnrollmentCode(CODE, future);
  const credential = store.enroll(CODE);
  expect(store.authenticate(`${credential.token.slice(0, -1)}x`)).toBeNull();
  store.close();
});

test('enrolled bearer credentials guard both production voice route families', async () => {
  const store = new DeviceCredentialStore({ pepper: PEPPER });
  store.registerEnrollmentCode(CODE, future);
  const app = express();
  app.use(express.json());
  app.use('/api/v1/device-enrollments', createDeviceEnrollmentRouter(store));
  app.use('/api/v1', createDeviceAuthentication(store));
  app.post('/api/v1/transcribe', (_req, res) => res.status(422).json({ code: 'VOICE_CONTRACT_REACHED' }));
  app.post('/api/v1/coaching/respond', (_req, res) => res.status(422).json({ code: 'VOICE_CONTRACT_REACHED' }));

  const enrolled = await request(app)
    .post('/api/v1/device-enrollments')
    .send({ code: CODE });
  const token = enrolled.body.data.token as string;

  for (const route of ['/api/v1/transcribe', '/api/v1/coaching/respond']) {
    const unauthenticated = await request(app).post(route).send({});
    expect(unauthenticated.status).toBe(401);
    expect(unauthenticated.body).toEqual({
      success: false,
      error: {
        code: 'DEVICE_AUTHENTICATION_REQUIRED',
        message: 'Device authentication required',
      },
    });

    const uuidBearer = await request(app)
      .post(route)
      .set('authorization', 'Bearer 11111111-1111-4111-8111-111111111111')
      .send({});
    expect(uuidBearer.status).toBe(401);

    const authenticated = await request(app)
      .post(route)
      .set('authorization', `Bearer ${token}`)
      .send({});
    expect(authenticated.status).toBe(422);
    expect(authenticated.body.code).toBe('VOICE_CONTRACT_REACHED');
  }
  store.close();
});

test('all rejected auth inputs return the same content-free response', async () => {
  const privateToken = 'private-invalid-bearer-value';
  const store = new DeviceCredentialStore({ pepper: PEPPER });
  const app = express();
  app.get('/private', createDeviceAuthentication(store), (_req, res) => res.json({ ok: true }));

  for (const authorization of [undefined, 'Basic private-value', `Bearer ${privateToken}`]) {
    const pending = request(app).get('/private');
    const response = await (authorization ? pending.set('authorization', authorization) : pending);
    expect(response.status).toBe(401);
    expect(JSON.stringify(response.body)).not.toContain(privateToken);
    expect(response.body.error.code).toBe('DEVICE_AUTHENTICATION_REQUIRED');
  }
  store.close();
});
