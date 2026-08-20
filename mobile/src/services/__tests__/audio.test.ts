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
});
