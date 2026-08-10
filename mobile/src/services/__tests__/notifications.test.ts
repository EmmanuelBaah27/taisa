const mockApiPost = jest.fn(async () => ({
  data: { data: { message: 'Private Acme goal excerpt' } },
}));

jest.mock('expo-notifications', () => ({
  SchedulableTriggerInputTypes: { DAILY: 'daily' },
  setNotificationHandler: jest.fn(),
  requestPermissionsAsync: jest.fn(async () => ({ status: 'granted' })),
  cancelAllScheduledNotificationsAsync: jest.fn(async () => undefined),
  scheduleNotificationAsync: jest.fn(async () => 'notification-id'),
  addNotificationResponseReceivedListener: jest.fn(),
}));

jest.mock('../api', () => ({
  __esModule: true,
  default: { post: mockApiPost },
}));

import { scheduleDailyReminders } from '../notifications';
import * as Notifications from 'expo-notifications';

const mockNotifications = jest.mocked(Notifications);

describe('notification privacy', () => {
  beforeEach(() => {
    mockNotifications.scheduleNotificationAsync.mockClear();
    mockNotifications.cancelAllScheduledNotificationsAsync.mockClear();
    mockApiPost.mockClear();
  });

  test('uses content-free copy and metadata for every scheduled reminder', async () => {
    await scheduleDailyReminders(['09:30', '17:45']);

    expect(mockNotifications.scheduleNotificationAsync).toHaveBeenCalledTimes(2);
    expect(mockApiPost).not.toHaveBeenCalled();
    for (const [input] of mockNotifications.scheduleNotificationAsync.mock.calls) {
      expect(input.content).toEqual({
        title: 'Taisa',
        body: 'You have an open Taisa action',
        data: { screen: 'today' },
      });
      expect(JSON.stringify(input.content)).not.toMatch(/goal|journal|reflect|company|excerpt/i);
    }
  });
});
