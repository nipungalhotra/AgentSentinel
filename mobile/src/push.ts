// Notifications while the app is closed. The app gets a push token from Expo's push service and
// hands it to the paired computer over the reply topic ("lg1-push <token> <signature>", signed with the pairing key). The computer then
// sends "a request is waiting" through Expo, which passes it to Apple or Google. The command text
// is never put in that notification: the app loads the request itself when it opens.
import { Platform } from 'react-native';
import Constants from 'expo-constants';
import * as Device from 'expo-device';
import * as Notifications from 'expo-notifications';
import { AndroidImportance } from 'expo-notifications';

import { signPushRegistration } from './hmac';
import type { Pairing } from './relay';

export type PushState = 'on' | 'denied' | 'needs-build' | 'needs-code' | 'unsupported' | 'error';

// While the app is open the request card is already on screen, so stay quiet.
Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowBanner: false,
    shouldShowList: false,
    shouldPlaySound: false,
    shouldSetBadge: false,
  }),
});

export async function registerForPush(p: Pairing): Promise<PushState> {
  // Browsers and simulators cannot receive these notifications.
  if (Platform.OS === 'web' || !Device.isDevice) return 'unsupported';
  // Only a phone holding the pairing key (from the QR code) may register; a typed topic can't.
  if (!p.key) return 'needs-code';
  try {
    if (Platform.OS === 'android') {
      await Notifications.setNotificationChannelAsync('requests', {
        name: 'Permission requests',
        importance: AndroidImportance.MAX,
      });
    }
    let { status } = await Notifications.getPermissionsAsync();
    if (status !== 'granted') status = (await Notifications.requestPermissionsAsync()).status;
    if (status !== 'granted') return 'denied';

    // The project id exists only in a real build made with an Expo account (not in Expo Go).
    const projectId = Constants.expoConfig?.extra?.eas?.projectId ?? Constants.easConfig?.projectId;
    if (!projectId) return 'needs-build';
    const token = (await Notifications.getExpoPushTokenAsync({ projectId })).data;

    const res = await fetch(`${p.server}/${p.topic}-reply`, { method: 'POST', body: `lg1-push ${token} ${signPushRegistration(p.key, token)}` });
    return res.ok ? 'on' : 'error';
  } catch {
    // Expo Go refuses remote notifications; a store or development build is needed.
    return Constants.appOwnership === 'expo' ? 'needs-build' : 'error';
  }
}
