import {
  CURRENT_HISTORY_LABEL,
  CURRENT_INITIAL_TAB,
  CURRENT_INITIAL_TAB_PATH,
  CURRENT_INITIAL_STACK,
} from '../currentExperience';
import { chatThreadRoute } from '../chatConversationRoute';

describe('current experience navigation', () => {
  test('initialized launches enter Home in the middle of Chats and Me', () => {
    expect(CURRENT_INITIAL_TAB).toBe('index');
    expect(CURRENT_INITIAL_STACK).toBe('(tabs)');
    expect(CURRENT_INITIAL_TAB_PATH).toBe('/');
    expect(CURRENT_HISTORY_LABEL).toBe('Chats');
    expect(CURRENT_HISTORY_LABEL).not.toBe('Logs');
  });

  test('opening a chat preserves its durable conversation id', () => {
    expect(chatThreadRoute('conversation-42')).toEqual({
      pathname: '/thread/[id]',
      params: { id: 'conversation-42' },
    });
  });
});
