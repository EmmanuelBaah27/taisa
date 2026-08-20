const mockStopAndUnloadAsync = jest.fn();
const mockGetURI = jest.fn(() => 'file:///recording.m4a');
const mockSetAudioModeAsync = jest.fn(async () => undefined);
const mockCreateAsync = jest.fn();

jest.mock('expo-av', () => ({
  Audio: {
    requestPermissionsAsync: jest.fn(async () => ({ granted: true })),
    setAudioModeAsync: mockSetAudioModeAsync,
    RecordingOptionsPresets: { HIGH_QUALITY: {} },
    Recording: { createAsync: mockCreateAsync },
  },
}));

jest.mock('expo-file-system', () => ({}));

describe('native audio recorder ownership', () => {
  beforeEach(() => {
    jest.resetModules();
    jest.clearAllMocks();
  });

  test('a failed native stop releases the owned recorder and permits a later start', async () => {
    const firstRecorder = {
      stopAndUnloadAsync: mockStopAndUnloadAsync,
      getURI: mockGetURI,
      setOnRecordingStatusUpdate: jest.fn(),
      setProgressUpdateInterval: jest.fn(),
      pauseAsync: jest.fn(),
      startAsync: jest.fn(),
    };
    const secondRecorder = { ...firstRecorder, stopAndUnloadAsync: jest.fn() };
    mockCreateAsync
      .mockResolvedValueOnce({ recording: firstRecorder })
      .mockResolvedValueOnce({ recording: secondRecorder });
    mockStopAndUnloadAsync.mockRejectedValueOnce(new Error('native stop failed'));
    const audio = require('../audio') as typeof import('../audio');

    await audio.startRecording();
    await expect(audio.stopRecording()).rejects.toThrow('native stop failed');
    expect(audio.isRecording()).toBe(false);
    expect(mockSetAudioModeAsync).toHaveBeenLastCalledWith({ allowsRecordingIOS: false });

    await expect(audio.startRecording()).resolves.toBeUndefined();
    expect(mockCreateAsync).toHaveBeenCalledTimes(2);
  });

  test('retries once after iOS releases a higher-priority system audio session', async () => {
    const recorder = {
      stopAndUnloadAsync: mockStopAndUnloadAsync,
      getURI: mockGetURI,
      setOnRecordingStatusUpdate: jest.fn(),
      setProgressUpdateInterval: jest.fn(),
      pauseAsync: jest.fn(),
      startAsync: jest.fn(),
    };
    mockCreateAsync
      .mockRejectedValueOnce(Object.assign(new Error('Session activation failed'), { code: 561017449 }))
      .mockResolvedValueOnce({ recording: recorder });
    const audio = require('../audio') as typeof import('../audio');

    await expect(audio.startRecording()).resolves.toBeUndefined();

    expect(mockCreateAsync).toHaveBeenCalledTimes(2);
    expect(mockSetAudioModeAsync).toHaveBeenNthCalledWith(2, { allowsRecordingIOS: false });
    expect(mockSetAudioModeAsync).toHaveBeenNthCalledWith(3, {
      allowsRecordingIOS: true,
      playsInSilentModeIOS: true,
    });
  });

  test('does not retry unrelated recorder preparation failures', async () => {
    mockCreateAsync.mockRejectedValueOnce(new Error('Recorder unavailable'));
    const audio = require('../audio') as typeof import('../audio');

    await expect(audio.startRecording()).rejects.toThrow('Recorder unavailable');

    expect(mockCreateAsync).toHaveBeenCalledTimes(1);
    expect(mockSetAudioModeAsync).toHaveBeenLastCalledWith({ allowsRecordingIOS: false });
  });
});
