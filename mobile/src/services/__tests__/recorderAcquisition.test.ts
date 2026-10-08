import { isRecorderAcquiring } from '../recorderAcquisition';

describe('recorder acquisition state', () => {
  test('a paused native recording is settled rather than acquiring', () => {
    expect(isRecorderAcquiring('paused', false, false)).toBe(false);
  });

  test('a recording draft waits for native acquisition before actions activate', () => {
    expect(isRecorderAcquiring('recording', false, false)).toBe(true);
    expect(isRecorderAcquiring('recording', false, true)).toBe(false);
  });
});
