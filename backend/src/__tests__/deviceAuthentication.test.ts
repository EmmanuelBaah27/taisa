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
