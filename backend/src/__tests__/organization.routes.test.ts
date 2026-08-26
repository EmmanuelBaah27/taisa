import express from 'express';
import request from 'supertest';

import { createOrganizationRouter, type OrganizationAnalyzer } from '../routes/organization';

function record(index: number) {
  return {
    id: `record-${index}`, kind: 'task', title: `Task ${index}`, status: 'open',
    revision: 1, projectId: null,
  };
}

const validRequest = {
  requestId: '11111111-1111-4111-8111-111111111111',
  submittedAt: '2026-08-26T08:00:00Z',
  scope: 'week',
  records: [record(1)],
  conversations: [{ id: 'conversation-1', summary: 'Planned Task 1', revision: 2 }],
};

function testApp(analyzer: OrganizationAnalyzer) {
  const app = express();
  app.use(express.json());
  app.use('/api/v1/organization', createOrganizationRouter(analyzer));
  return app;
}

test('rejects week payloads above the 30-record cap before provider invocation', async () => {
  const analyzer: OrganizationAnalyzer = { analyze: jest.fn() };
  const response = await request(testApp(analyzer))
    .post('/api/v1/organization/analyze')
    .send({ ...validRequest, records: Array.from({ length: 31 }, (_, index) => record(index)) });

  expect(response.status).toBe(400);
  expect(analyzer.analyze).not.toHaveBeenCalled();
});

test('rejects full-archive fields and task scopes above 20 conversations', async () => {
  const analyzer: OrganizationAnalyzer = { analyze: jest.fn() };
  const app = testApp(analyzer);

  const fullArchive = await request(app)
    .post('/api/v1/organization/analyze')
    .send({ ...validRequest, fullArchive: true });
  const tooManyConversations = await request(app)
    .post('/api/v1/organization/analyze')
    .send({
      ...validRequest,
      scope: 'conversation_task',
      conversations: Array.from({ length: 21 }, (_, index) => ({
        id: `conversation-${index}`, summary: `Summary ${index}`, revision: 1,
      })),
    });

  expect(fullArchive.status).toBe(400);
  expect(tooManyConversations.status).toBe(400);
  expect(analyzer.analyze).not.toHaveBeenCalled();
});

test('valid bounded input calls the stateless analyzer exactly once', async () => {
  const analyzer: OrganizationAnalyzer = {
    analyze: jest.fn().mockResolvedValue({ requestId: validRequest.requestId, proposals: [] }),
  };

  const response = await request(testApp(analyzer))
    .post('/api/v1/organization/analyze')
    .set('x-user-id', 'device-1')
    .send(validRequest);

  expect(response.status).toBe(200);
  expect(response.body).toEqual({
    success: true,
    data: { requestId: validRequest.requestId, proposals: [] },
  });
  expect(analyzer.analyze).toHaveBeenCalledTimes(1);
  expect(analyzer.analyze).toHaveBeenCalledWith(validRequest);
});

test('rejects a provider proposal whose effect does not match its type', async () => {
  const analyzer: OrganizationAnalyzer = {
    analyze: jest.fn().mockResolvedValue({
      requestId: validRequest.requestId,
      proposals: [{
        id: 'proposal-1', type: 'project_association', sourceId: 'conversation-1',
        sourceRevision: 2, evidenceIds: ['conversation-1'], evidenceFingerprint: 'fp-1',
        reasoning: 'Explicit project reference', effect: { recordId: 'record-1' },
        ambiguity: 'strong', admission: 'pending', resolution: 'unapplied',
        revalidation: 'valid', createdAt: validRequest.submittedAt,
        updatedAt: validRequest.submittedAt,
      }],
    } as never),
  };

  const response = await request(testApp(analyzer))
    .post('/api/v1/organization/analyze')
    .send(validRequest);

  expect(response.status).toBe(502);
  expect(response.body.error.code).toBe('INVALID_ORGANIZATION_OUTPUT');
});
