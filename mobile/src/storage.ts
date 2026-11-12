// Where the pairing is kept: the device keychain in the phone app, localStorage in a browser
// (expo-secure-store has no web implementation).
import { Platform } from 'react-native';
import * as SecureStore from 'expo-secure-store';

const web = Platform.OS === 'web';

export async function loadItem(key: string): Promise<string | null> {
  if (!web) return SecureStore.getItemAsync(key);
  try {
    return window.localStorage.getItem(key);
  } catch {
    return null; // private browsing or blocked storage: stay unpaired
  }
}

export async function saveItem(key: string, value: string): Promise<void> {
  if (!web) return SecureStore.setItemAsync(key, value);
  try {
    window.localStorage.setItem(key, value);
  } catch {
    // The pairing still works for this visit; it just is not remembered.
  }
}

export async function removeItem(key: string): Promise<void> {
  if (!web) return SecureStore.deleteItemAsync(key);
  try {
    window.localStorage.removeItem(key);
  } catch {}
}

/**
 * On the web a pairing link looks like https://app.loggdin.com/#loggdin-…: the topic sits after
 * the "#", which browsers never send to the server. It is read once and removed from the address bar.
 */
export function takePairingFromLink(): string | null {
  if (!web || typeof window === 'undefined') return null;
  const hash = decodeURIComponent(window.location.hash.replace(/^#/, ''));
  if (!hash) return null;
  window.history.replaceState(null, '', window.location.pathname + window.location.search);
  return hash;
}
