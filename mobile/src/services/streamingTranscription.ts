import {
  isTranscriptionStreamEvent,
  type TranscriptionStreamEvent,
} from '@taisa/shared';

export interface StreamingTranscriptionRequest {
  requestId: string;
  audioUri: string;
  durationSeconds: number;
}

type SuccessfulTerminalEvent = Extract<
  TranscriptionStreamEvent,
  { type: 'transcript.completed' | 'transcript.no_speech' }
>;

export interface StreamingTranscriptionSubscription {
  completed: Promise<SuccessfulTerminalEvent>;
  abort(): void;
}

export class TranscriptionClientError extends Error {
  readonly code = 'TRANSCRIPTION_REQUEST_FAILED';

  constructor() {
    super('Taisa could not transcribe this recording. The recording remains on this device.');
    this.name = 'TranscriptionClientError';
  }
}

interface StreamingTranscriptionDependencies {
  createRequest(): XMLHttpRequest;
  getInstallationId(): Promise<string>;
  getDeviceCredential(): Promise<string | null>;
  baseUrl: string;
}

export function createStreamingTranscriptionClient(
  dependencies: StreamingTranscriptionDependencies,
) {
  return async function startStreamingTranscription(
    request: StreamingTranscriptionRequest,
    onEvent: (event: TranscriptionStreamEvent) => void,
  ): Promise<StreamingTranscriptionSubscription> {
    const [installationId, credential] = await Promise.all([
      dependencies.getInstallationId(),
      dependencies.getDeviceCredential(),
    ]);
    const xhr = dependencies.createRequest();
    let consumedResponseLength = 0;
    let bufferedLine = '';
    let nextSequence = 0;
    let terminalReceived = false;
    let terminalEvent: Exclude<TranscriptionStreamEvent, { type: 'transcript.delta' }> | null = null;
    let settled = false;
    let resolveCompleted!: (event: SuccessfulTerminalEvent) => void;
    let rejectCompleted!: (error: TranscriptionClientError) => void;
    const completed = new Promise<SuccessfulTerminalEvent>((resolve, reject) => {
      resolveCompleted = resolve;
      rejectCompleted = reject;
    });

    const fail = () => {
      if (settled) return;
      settled = true;
      rejectCompleted(new TranscriptionClientError());
    };

    const acceptLine = (line: string) => {
      if (!line.trim() || settled) return;
      let value: unknown;
      try {
        value = JSON.parse(line);
      } catch {
        fail();
        return;
      }
      if (
        !isTranscriptionStreamEvent(value)
        || value.requestId !== request.requestId
        || value.sequence !== nextSequence
        || terminalReceived
      ) {
        fail();
        return;
      }

      nextSequence += 1;
      onEvent(value);
      if (value.type === 'transcript.delta') return;
      terminalReceived = true;
      terminalEvent = value;
    };

    const consumeProgress = () => {
      if (settled) return;
      const newText = xhr.responseText.slice(consumedResponseLength);
      consumedResponseLength = xhr.responseText.length;
      bufferedLine += newText;
      const lines = bufferedLine.split('\n');
      bufferedLine = lines.pop() ?? '';
      for (const line of lines) acceptLine(line);
    };

    xhr.open('POST', `${dependencies.baseUrl.replace(/\/$/, '')}/transcribe`);
    xhr.timeout = 60_000;
    xhr.setRequestHeader('x-user-id', installationId);
    xhr.setRequestHeader('x-request-id', request.requestId);
    if (credential) xhr.setRequestHeader('Authorization', `Bearer ${credential}`);
    xhr.onprogress = consumeProgress;
    xhr.onload = () => {
      consumeProgress();
      if (!settled && bufferedLine.trim()) {
        const finalLine = bufferedLine;
        bufferedLine = '';
        acceptLine(finalLine);
      }
      if (xhr.status < 200 || xhr.status >= 300 || terminalEvent === null) {
        fail();
        return;
      }
      if (terminalEvent.type === 'transcript.failed') {
        fail();
        return;
      }
      settled = true;
      resolveCompleted(terminalEvent);
    };
    xhr.onerror = fail;
    xhr.ontimeout = fail;
    xhr.onabort = fail;

    const formData = new FormData();
    formData.append('audio', {
      uri: request.audioUri,
      name: 'recording.m4a',
      type: 'audio/m4a',
    } as never);
    formData.append('durationSeconds', String(request.durationSeconds));
    xhr.send(formData);

    return {
      completed,
      abort() {
        if (!settled) xhr.abort();
      },
    };
  };
}
