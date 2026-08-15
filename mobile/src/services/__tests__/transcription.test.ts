import { createTranscriptionClient, TranscriptionClientError } from '../transcription';

test('transcription client binds the persisted request ID and returns transcript plus usage', async () => {
  const post = jest.fn(async (_path: string, _body: unknown, _config?: unknown) => ({
    data: {
      success: true,
      data: {
        transcript: 'Editable transcript',
        durationSeconds: 12,
        usage: {
          provider: 'openai',
          model: 'fixture-transcription',
          audioSeconds: 12,
          estimatedCostUsd: 0.0012,
        },
      },
    },
  }));
  const transcribe = createTranscriptionClient({ post });

  const result = await transcribe({
    requestId: '00000000-0000-4000-8000-000000000001',
    audioUri: 'file:///private/original.m4a',
    durationSeconds: 12,
  });

  expect(result.transcript).toBe('Editable transcript');
  expect(result.usage.audioSeconds).toBe(12);
  expect(post).toHaveBeenCalledTimes(1);
  expect(post.mock.calls[0][0]).toBe('/transcribe');
  expect(post.mock.calls[0][2]).toEqual({
    headers: {
      'Content-Type': 'multipart/form-data',
      'x-request-id': '00000000-0000-4000-8000-000000000001',
    },
    timeout: 60_000,
  });
});

test('transcription client converts transport failures into content-free errors', async () => {
  const post = jest.fn(async (_path: string, _body: unknown, _config?: unknown) => {
    throw new Error('raw transcript and provider payload');
  });
  const transcribe = createTranscriptionClient({ post });

  let failure: TranscriptionClientError | null = null;
  try {
    await transcribe({
      requestId: '00000000-0000-4000-8000-000000000001',
      audioUri: 'file:///private/original.m4a',
      durationSeconds: 12,
    });
  } catch (error) {
    failure = error as TranscriptionClientError;
  }

  expect(failure).toBeInstanceOf(TranscriptionClientError);
  expect(failure?.message).not.toContain('raw transcript');
  expect(post).toHaveBeenCalledTimes(1);
});

test('transcription client does not infer speech activity from the returned words', async () => {
  const transcript = 'Thanks for watching!';
  const post = jest.fn(async () => ({
    data: {
      success: true,
      data: {
        transcript,
        durationSeconds: 4,
        usage: {
          provider: 'openai',
          model: 'fixture-transcription',
          audioSeconds: 4,
          estimatedCostUsd: 0.0004,
        },
      },
    },
  }));
  const transcribe = createTranscriptionClient({ post });

  await expect(transcribe({
    requestId: '00000000-0000-4000-8000-000000000001',
    audioUri: 'file:///private/noise-only.m4a',
    durationSeconds: 4,
  })).resolves.toMatchObject({ transcript });
});

test('transcription client accepts speech that mentions background noise', async () => {
  const transcript = 'The background noise made it difficult to focus at work.';
  const post = jest.fn(async () => ({
    data: {
      success: true,
      data: {
        transcript,
        durationSeconds: 8,
        usage: {
          provider: 'openai',
          model: 'fixture-transcription',
          audioSeconds: 8,
          estimatedCostUsd: 0.0008,
        },
      },
    },
  }));
  const transcribe = createTranscriptionClient({ post });

  await expect(transcribe({
    requestId: '00000000-0000-4000-8000-000000000001',
    audioUri: 'file:///private/spoken-content.m4a',
    durationSeconds: 8,
  })).resolves.toMatchObject({ transcript });
});
