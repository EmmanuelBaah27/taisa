import {
  confirmDestructiveInput,
  getDestructiveInputConfirmationOptions,
} from '../destructiveInputConfirmation';

describe('destructive input confirmation', () => {
  test.each([
    ['cancel-recording', 'Discard draft'],
    ['switch-to-keyboard', 'Switch and discard'],
    ['delete-voice-draft', 'Delete recording'],
    ['discard-voice-submission', 'Discard draft'],
  ] as const)('marks %s as the native destructive action', (intent, destructiveLabel) => {
    expect(getDestructiveInputConfirmationOptions(intent)).toMatchObject({
      options: ['Cancel', destructiveLabel],
      cancelButtonIndex: 0,
      destructiveButtonIndex: 1,
    });
  });

  test.each(['cancel-recording', 'discard-voice-submission'] as const)(
    'uses format-neutral draft copy for %s',
    (intent) => {
      expect(getDestructiveInputConfirmationOptions(intent)).toMatchObject({
        title: 'Discard draft?',
        message: 'Your unfinished draft will be removed.',
      });
    },
  );

  test('resolves only the destructive native action as confirmation', async () => {
    const presenter = jest.fn((
      _options: ReturnType<typeof getDestructiveInputConfirmationOptions>,
      callback: (index: number) => void,
    ) => callback(1));

    await expect(confirmDestructiveInput('cancel-recording', presenter)).resolves.toBe(true);
    expect(presenter).toHaveBeenCalledTimes(1);
  });

  test('resolves the native cancel action without discarding', async () => {
    const presenter = jest.fn((
      _options: ReturnType<typeof getDestructiveInputConfirmationOptions>,
      callback: (index: number) => void,
    ) => callback(0));

    await expect(confirmDestructiveInput('delete-voice-draft', presenter)).resolves.toBe(false);
  });
});
