import { ActionSheetIOS, Alert, Platform } from 'react-native';

import { playInteractionHaptic } from './interactionHaptics';

export type DestructiveInputIntent =
  | 'cancel-recording'
  | 'switch-to-keyboard'
  | 'delete-voice-draft'
  | 'discard-voice-submission';

export interface DestructiveInputConfirmationOptions {
  title: string;
  message: string;
  options: [string, string];
  cancelButtonIndex: 0;
  destructiveButtonIndex: 1;
}

export type DestructiveInputPresenter = (
  options: DestructiveInputConfirmationOptions,
  callback: (buttonIndex: number) => void,
) => void;

export function getDestructiveInputConfirmationOptions(
  intent: DestructiveInputIntent,
): DestructiveInputConfirmationOptions {
  switch (intent) {
    case 'switch-to-keyboard':
      return {
        title: 'Switch to keyboard?',
        message: 'Your current recording will be discarded.',
        options: ['Go back', 'Switch and discard'],
        cancelButtonIndex: 0,
        destructiveButtonIndex: 1,
      };
    case 'delete-voice-draft':
      return {
        title: 'Delete voice draft?',
        message: 'This recording will be permanently removed.',
        options: ['Go back', 'Delete recording'],
        cancelButtonIndex: 0,
        destructiveButtonIndex: 1,
      };
    case 'discard-voice-submission':
      return {
        title: 'Discard submission?',
        message: 'The recording and its unfinished submission will be removed.',
        options: ['Go back', 'Discard submission'],
        cancelButtonIndex: 0,
        destructiveButtonIndex: 1,
      };
    case 'cancel-recording':
    default:
      return {
        title: 'Discard recording?',
        message: 'This recording will not be saved.',
        options: ['Go back', 'Discard recording'],
        cancelButtonIndex: 0,
        destructiveButtonIndex: 1,
      };
  }
}

export function confirmDestructiveInput(
  intent: DestructiveInputIntent,
  presenter?: DestructiveInputPresenter,
): Promise<boolean> {
  const confirmation = getDestructiveInputConfirmationOptions(intent);

  return new Promise((resolve) => {
    const handleSelection = (buttonIndex: number) => {
      playInteractionHaptic(
        buttonIndex === confirmation.destructiveButtonIndex ? 'destructive-confirm' : 'go-back',
      );
      resolve(buttonIndex === confirmation.destructiveButtonIndex);
    };

    if (presenter !== undefined) {
      presenter(confirmation, handleSelection);
      return;
    }

    if (Platform.OS === 'ios') {
      ActionSheetIOS.showActionSheetWithOptions(confirmation, handleSelection);
      return;
    }

    Alert.alert(confirmation.title, confirmation.message, [
      { text: confirmation.options[0], style: 'cancel', onPress: () => handleSelection(0) },
      { text: confirmation.options[1], style: 'destructive', onPress: () => handleSelection(1) },
    ]);
  });
}
