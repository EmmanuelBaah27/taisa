import {
  createStreamingTranscriptionClient,
  TranscriptionClientError,
} from '../streamingTranscription';

const requestId = '00000000-0000-4000-8000-000000000001';

class FakeXMLHttpRequest {
  responseText = '';
  status = 200;
  timeout = 0;
  method = '';
  url = '';
  body: Document | XMLHttpRequestBodyInit | null = null;
  headers: Record<string, string> = {};
  aborted = false;
  onprogress: ((event: ProgressEvent<EventTarget>) => void) | null = null;
  onload: ((event: ProgressEvent<EventTarget>) => void) | null = null;
  onerror: ((event: ProgressEvent<EventTarget>) => void) | null = null;
  ontimeout: ((event: ProgressEvent<EventTarget>) => void) | null = null;
  onabort: ((event: ProgressEvent<EventTarget>) => void) | null = null;

  open(method: string, url: string) {
    this.method = method;
    this.url = url;
  }

  setRequestHeader(name: string, value: string) {
    this.headers[name] = value;
  }

  send(body: Document | XMLHttpRequestBodyInit | null) {
    this.body = body;
  }

  abort() {
    this.aborted = true;
    this.onabort?.({} as ProgressEvent<EventTarget>);
  }

  progress(chunk: string) {
    this.responseText += chunk;
    this.onprogress?.({} as ProgressEvent<EventTarget>);
  }

  finish(status = 200) {
    this.status = status;
    this.onload?.({} as ProgressEvent<EventTarget>);
  }
}

function createHarness() {
  const xhr = new FakeXMLHttpRequest();
  const onEvent = jest.fn();
  const start = createStreamingTranscriptionClient({
    createRequest: () => xhr as unknown as XMLHttpRequest,
    getInstallationId: async () => 'installation-1',
    getDeviceCredential: async () => 'x'.repeat(32),
    baseUrl: 'https://api.taisa.test/api/v1',
  });
  return { xhr, onEvent, start };
}

test('parses split NDJSON records incrementally and delivers them exactly once', async () => {
  const { xhr, onEvent, start } = createHarness();
  const subscription = await start({
    requestId,
    audioUri: 'file:///private/original.m4a',
    durationSeconds: 12,
  }, onEvent);

  xhr.progress('{"type":"transcript.del');
  expect(onEvent).not.toHaveBeenCalled();
  xhr.progress(`ta","requestId":"${requestId}","sequence":0,"delta":"I led "}\n`);
  expect(onEvent).toHaveBeenCalledWith(expect.objectContaining({
    type: 'transcript.delta',
    delta: 'I led ',
  }));
  xhr.progress(`{"type":"transcript.completed","requestId":"${requestId}","sequence":1,`);
  xhr.progress('"transcript":"I led the review","durationSeconds":12,"quality":"clear",');
  xhr.progress('"usage":{"provider":"openai","model":"fixture","audioSeconds":12,"estimatedCostUsd":0.0012}}\n');
  xhr.finish();

  await expect(subscription.completed).resolves.toMatchObject({
    type: 'transcript.completed',
    quality: 'clear',
  });
  expect(onEvent).toHaveBeenCalledTimes(2);
  expect(xhr.method).toBe('POST');
  expect(xhr.url).toBe('https://api.taisa.test/api/v1/transcribe');
  expect(xhr.headers).toEqual({
    'x-user-id': 'installation-1',
    'x-request-id': requestId,
    Authorization: `Bearer ${'x'.repeat(32)}`,
  });
  expect(Object.keys(xhr.headers)).not.toContain('Content-Type');
  expect(xhr.body).toBeInstanceOf(FormData);
});

test('rejects malformed or regressing events without exposing response content', async () => {
  const { xhr, start } = createHarness();
  const subscription = await start({
    requestId,
    audioUri: 'file:///private/original.m4a',
    durationSeconds: 12,
  }, jest.fn());

  xhr.progress('{"private":"raw transcript"}\n');

  await expect(subscription.completed).rejects.toBeInstanceOf(TranscriptionClientError);
  await subscription.completed.catch((error) => {
    expect(error.message).not.toContain('raw transcript');
  });
});

test('abort cancels XHR and rejects an incomplete request content-free', async () => {
  const { xhr, start } = createHarness();
  const subscription = await start({
    requestId,
    audioUri: 'file:///private/original.m4a',
    durationSeconds: 12,
  }, jest.fn());

  subscription.abort();

  expect(xhr.aborted).toBe(true);
  await expect(subscription.completed).rejects.toBeInstanceOf(TranscriptionClientError);
});
