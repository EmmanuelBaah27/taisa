import { startFreshCapture } from '../../navigation/chatConversationRoute';
import { useUIStore } from '../uiStore';

describe('voice capture entry intent', () => {
  beforeEach(() => {
    useUIStore.setState({
      chatMorphing: false,
      voiceAutoStartPending: false,
      chatListReturnOffset: null,
    });
  });

  test('a Chats return offset is consumed exactly once after route dismissal', () => {
    useUIStore.getState().captureChatListReturn(248.5);

    expect(useUIStore.getState().consumeChatListReturn()).toBe(248.5);
    expect(useUIStore.getState().consumeChatListReturn()).toBeNull();
  });

  test('the central voice entry opens voice mode and offers exactly one automatic start', () => {
    const clearActiveConversation = jest.fn();

    startFreshCapture({
      clearActiveConversation,
      openCapture: useUIStore.getState().openVoiceCapture,
    });

    expect(clearActiveConversation).toHaveBeenCalledTimes(1);
    expect(useUIStore.getState()).toMatchObject({
      chatMorphing: true,
      voiceAutoStartPending: true,
    });
    expect(useUIStore.getState().consumeVoiceAutoStart()).toBe(true);
    expect(useUIStore.getState().consumeVoiceAutoStart()).toBe(false);
  });

  test('ordinary voice-ready responses do not enqueue another automatic start', () => {
    useUIStore.getState().setChatMorphing(true);

    expect(useUIStore.getState().consumeVoiceAutoStart()).toBe(false);
  });
});
