import * as Notifications from 'expo-notifications';
import api from './api';

Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowAlert: true,
    shouldShowBanner: true,
    shouldShowList: true,
    shouldPlaySound: false,
    shouldSetBadge: false,
  }),
});

export async function requestNotificationPermissions(): Promise<boolean> {
  const { status } = await Notifications.requestPermissionsAsync();
  return status === 'granted';
}

export async function scheduleDailyReminders(times: string[] = ['15:00', '19:00']): Promise<void> {
  // Cancel existing reminders first
  await Notifications.cancelAllScheduledNotificationsAsync();

  for (const time of times) {
    const [hour, minute] = time.split(':').map(Number);

    // Fetch a personalized message from the backend
    let message = "Time to reflect on your day. What happened?";
    try {
      const res = await api.post('/notifications/checkin-message');
      message = res.data.data.message;
    } catch {
      // Fall back to generic message
    }

    await Notifications.scheduleNotificationAsync({
      content: {
        title: 'Taisa',
        body: message,
        data: { screen: 'journal' },
      },
      trigger: {
        type: Notifications.SchedulableTriggerInputTypes.DAILY,
        hour,
        minute,
      },
    });
  }
}

export async function cancelAllReminders(): Promise<void> {
  await Notifications.cancelAllScheduledNotificationsAsync();
}

// Set up deep link handler — routes to journal on notification tap
export function setupNotificationListener() {
  return Notifications.addNotificationResponseReceivedListener(response => {
    const data = response.notification.request.content.data;
    if (data?.screen === 'journal') {
      // Navigation is handled in _layout.tsx via router
    }
  });
}
