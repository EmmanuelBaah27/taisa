import type { OrganizationRequest } from '@taisa/shared';

import { createOrganizationClient } from '../organization';

const organizationRequest: OrganizationRequest = {
  requestId: '11111111-1111-4111-8111-111111111111',
  submittedAt: '2026-08-26T08:00:00Z',
  scope: 'week',
  records: [{
    id: 'task-1', kind: 'task', title: 'Send proposal', status: 'open',
    revision: 1, projectId: null,
  }],
  conversations: [{ id: 'conversation-1', summary: 'Planned the proposal', revision: 2 }],
};

test('cancelled preview sends nothing', async () => {
  const http = { post: jest.fn() };
  const submit = createOrganizationClient(http);

  await expect(submit({ request: organizationRequest, approved: false }))
    .resolves.toEqual({ kind: 'cancelled' });
  expect(http.post).not.toHaveBeenCalled();
});

test('approved preview sends exactly the bounded request once', async () => {
  const http = {
    post: jest.fn().mockResolvedValue({
      data: { success: true, data: { requestId: organizationRequest.requestId, proposals: [] } },
    }),
  };
  const submit = createOrganizationClient(http);

  await expect(submit({ request: organizationRequest, approved: true })).resolves.toEqual({
    kind: 'received', response: { requestId: organizationRequest.requestId, proposals: [] },
  });
  expect(http.post).toHaveBeenCalledTimes(1);
  expect(http.post).toHaveBeenCalledWith('/organization/analyze', organizationRequest, {
    headers: { 'x-request-id': organizationRequest.requestId },
  });
});

test('mismatched response request ID is rejected without local mutation', async () => {
  const http = {
    post: jest.fn().mockResolvedValue({
      data: { success: true, data: { requestId: '22222222-2222-4222-8222-222222222222', proposals: [] } },
    }),
  };
  const submit = createOrganizationClient(http);

  await expect(submit({ request: organizationRequest, approved: true }))
    .rejects.toMatchObject({ code: 'INVALID_ORGANIZATION_RESPONSE' });
});
