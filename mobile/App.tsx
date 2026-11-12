import { useCallback, useEffect, useRef, useState } from 'react';
import {
  AccessibilityInfo,
  Animated,
  AppState,
  Easing,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { StatusBar } from 'expo-status-bar';
import { CameraView, useCameraPermissions } from 'expo-camera';
import { Archivo_400Regular, Archivo_500Medium, Archivo_600SemiBold, Archivo_700Bold, useFonts } from '@expo-google-fonts/archivo';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';

import { connect, isSafeReply, parsePairing, sendReply, type Pairing, type PhoneRequest } from './src/relay';
import { loadItem, removeItem, saveItem, takePairingFromLink } from './src/storage';
import { registerForPush, type PushState } from './src/push';
import { font, u, useTheme } from './src/theme';
import { Faceplate, Key, Lamp, Recess, Rule, StatusRow } from './src/ui';

const STORE_KEY = 'loggdin.pairing';
/** The computer waits 110 s while phone approvals are on; after that a request is dead. */
const REQUEST_LIFETIME_MS = 110_000;

type HistoryItem = { key: string; allowed: boolean; label: string; command: string; at: number };

export default function App() {
  const t = useTheme();
  const [fontsReady] = useFonts({ Archivo_400Regular, Archivo_500Medium, Archivo_600SemiBold, Archivo_700Bold });
  const [pairing, setPairing] = useState<Pairing | null | undefined>(undefined);

  useEffect(() => {
    // Development only: EXPO_PUBLIC_DEV_TOPIC pairs the app without typing, for simulator testing.
    const devPairing = __DEV__ ? parsePairing(process.env.EXPO_PUBLIC_DEV_TOPIC ?? '') : null;
    // Web: a pairing link (…/#loggdin-…) from the computer's QR code pairs straight away.
    const linked = parsePairing(takePairingFromLink() ?? '');
    const stored = linked
      ? saveItem(STORE_KEY, JSON.stringify(linked)).then(() => JSON.stringify(linked))
      : loadItem(STORE_KEY);
    stored
      .then((raw) => setPairing(raw ? (JSON.parse(raw) as Pairing) : devPairing))
      .catch(() => setPairing(linked ?? devPairing));
  }, []);

  const pair = useCallback(async (p: Pairing) => {
    await saveItem(STORE_KEY, JSON.stringify(p));
    setPairing(p);
  }, []);

  const unpair = useCallback(async () => {
    await removeItem(STORE_KEY);
    setPairing(null);
  }, []);

  return (
    <SafeAreaProvider>
      <SafeAreaView style={[styles.screen, { backgroundColor: t.plate }]}>
        <StatusBar style={t.dark ? 'light' : 'dark'} />
        {!fontsReady || pairing === undefined ? null : pairing === null ? (
          <PairScreen onPair={pair} />
        ) : (
          <RequestsScreen pairing={pairing} onUnpair={unpair} />
        )}
      </SafeAreaView>
    </SafeAreaProvider>
  );
}

function Wordmark() {
  const t = useTheme();
  return (
    <Text accessibilityRole="header" accessibilityLabel="loggdin Pocket" style={[styles.wordmark, { color: t.ink }]}>
      loggdin<Text style={[styles.wordmarkSub, { color: t.ink3 }]}> Pocket</Text>
    </Text>
  );
}

function Notice({ text }: { text: string }) {
  const t = useTheme();
  return (
    <View style={styles.notice} accessibilityRole="alert">
      <Lamp state="alert" />
      <Text style={[styles.noticeText, { color: t.ink }]}>{text}</Text>
    </View>
  );
}

function PairScreen({ onPair }: { onPair: (p: Pairing) => void }) {
  const t = useTheme();
  const [text, setText] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [scanning, setScanning] = useState(false);
  const [focused, setFocused] = useState(false);
  const [permission, requestPermission] = useCameraPermissions();

  const submit = (value: string) => {
    const p = parsePairing(value);
    if (!p) {
      setError(
        value.trim()
          ? 'That isn’t a loggdin pairing code. It starts with “loggdin-”.'
          : 'Type the pairing code shown on your computer.',
      );
      return false;
    }
    setError(null);
    onPair(p);
    return true;
  };

  const startScan = async () => {
    const granted = permission?.granted || (await requestPermission()).granted;
    if (granted) setScanning(true);
    else setError('Camera access is off. Type the pairing code instead.');
  };

  if (scanning) {
    return (
      <View style={styles.fill}>
        <CameraView
          style={styles.fill}
          barcodeScannerSettings={{ barcodeTypes: ['qr'] }}
          onBarcodeScanned={({ data }) => {
            if (submit(data)) setScanning(false);
          }}
        />
        <View style={[styles.scanBar, { backgroundColor: t.plate }]}>
          <Text style={[styles.body, { color: t.ink2 }]}>Point the camera at the code on your computer.</Text>
          <Key label="Cancel" onPress={() => setScanning(false)} />
        </View>
      </View>
    );
  }

  return (
    <KeyboardAvoidingView style={styles.fill} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <ScrollView contentContainerStyle={styles.column} keyboardShouldPersistTaps="handled">
        <Wordmark />
        <View style={styles.intro}>
          <Text accessibilityRole="header" style={[styles.headline, { color: t.ink }]}>
            Pair with your computer
          </Text>
          <Text style={[styles.body, { color: t.ink2 }]}>
            Once paired, this phone can answer when an AI agent on your computer asks for permission.
          </Text>
        </View>

        <Recess>
          <View style={styles.source}>
            <Text style={[styles.term, { color: t.ink }]}>Mac</Text>
            <Text style={[styles.sourceText, { color: t.ink2 }]}>
              Open loggdin, then Rules & Grants, then Approve from your phone. A pairing code appears.
            </Text>
          </View>
          <Rule />
          <View style={styles.source}>
            <Text style={[styles.term, { color: t.ink }]}>Windows, Linux</Text>
            <Text style={[styles.sourceText, { color: t.ink2 }]}>
              Run <Text style={[styles.code, { color: t.ink }]}>loggdin phone setup</Text>. It prints a pairing code to type
              below.
            </Text>
          </View>
        </Recess>

        <Key kind="signal" label="Scan pairing code" onPress={startScan} />

        <View style={styles.manual}>
          <Text nativeID="topic-label" style={[styles.fieldLabel, { color: t.ink }]}>
            Or type the pairing code
          </Text>
          <Recess
            style={[styles.well, focused && { outlineColor: t.signal, outlineWidth: 2, outlineStyle: 'solid' }]}>
            <TextInput
              style={[styles.input, { color: t.ink }]}
              value={text}
              onChangeText={(v) => {
                setText(v);
                if (error) setError(null);
              }}
              onFocus={() => setFocused(true)}
              onBlur={() => setFocused(false)}
              placeholder="loggdin-k7m2x9pq4rtw8hnc.3f9a…"
              placeholderTextColor={t.ink3}
              selectionColor={t.signal}
              cursorColor={t.signal}
              autoCapitalize="none"
              autoCorrect={false}
              spellCheck={false}
              accessibilityLabel="Pairing code"
              accessibilityLabelledBy="topic-label"
              returnKeyType="done"
              onSubmitEditing={() => submit(text)}
            />
            <Key label="Pair" onPress={() => submit(text)} style={styles.wellKey} />
          </Recess>
          {error ? <Notice text={error} /> : null}
        </View>

        <Text style={[styles.fine, { color: t.ink3 }]}>
          No account, no password. The code is the pairing, so keep it private.
        </Text>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const pushLine: Record<PushState, { lamp: 'on' | 'warn' | 'off'; value: string }> = {
  on: { lamp: 'on', value: 'On, even when this app is closed' },
  denied: { lamp: 'warn', value: 'Off. Turn them on in Settings' },
  'needs-build': { lamp: 'off', value: 'Not in this test version' },
  'needs-code': { lamp: 'warn', value: 'Pair with the QR code or pairing code to turn on' },
  unsupported: { lamp: 'off', value: 'Not available here' },
  error: { lamp: 'warn', value: 'Couldn’t switch on. Reopen the app' },
};

const isDeny = (label: string) => label.toLowerCase().startsWith('deny');

function RequestsScreen({ pairing, onUnpair }: { pairing: Pairing; onUnpair: () => void }) {
  const t = useTheme();
  const [requests, setRequests] = useState<PhoneRequest[]>([]);
  const [history, setHistory] = useState<HistoryItem[]>([]);
  const [online, setOnline] = useState(false);
  const [sending, setSending] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [push, setPush] = useState<PushState>('unsupported');
  const [now, setNow] = useState(() => Date.now());
  const answered = useRef(new Set<string>());

  useEffect(() => {
    let live = true;
    registerForPush(pairing).then((state) => live && setPush(state));
    return () => {
      live = false;
    };
  }, [pairing]);

  useEffect(() => {
    const handlers = {
      onStatus: setOnline,
      onRequest: (r: PhoneRequest) =>
        setRequests((list) => (answered.current.has(r.seq) ? list : [r, ...list.filter((x) => x.seq !== r.seq)])),
      onClear: (seq: string) => setRequests((list) => list.filter((x) => x.seq !== seq)),
      onLocked: () =>
        setError('A request arrived that this phone can\u2019t open. Pair again with the QR code or the pairing code.'),
    };
    let stop = connect(pairing, handlers);
    // iOS and Android close sockets in the background: reconnect when the app comes back.
    const sub = AppState.addEventListener('change', (state) => {
      if (state !== 'active') return;
      stop();
      stop = connect(pairing, handlers);
    });
    return () => {
      sub.remove();
      stop();
    };
  }, [pairing]);

  // Drop requests the computer has already given up on, and keep the countdown moving.
  useEffect(() => {
    const timer = setInterval(() => {
      setRequests((list) => {
        const live = list.filter((r) => Date.now() - r.at < REQUEST_LIFETIME_MS);
        return live.length === list.length ? list : live;
      });
      setNow(Date.now());
    }, 1000);
    return () => clearInterval(timer);
  }, []);

  const answer = async (request: PhoneRequest, index: number) => {
    const action = request.actions[index];
    if (!isSafeReply(pairing, action)) {
      setError('This request has an unexpected reply address, so it wasn’t answered.');
      return;
    }
    setSending(request.seq);
    setError(null);
    const ok = await sendReply(action);
    setSending(null);
    if (!ok) {
      setError('Your answer didn’t send. Check the connection and try again.');
      return;
    }
    answered.current.add(request.seq);
    setRequests((list) => list.filter((x) => x.seq !== request.seq));
    const deny = isDeny(action.label);
    setHistory((list) =>
      [
        {
          key: request.seq,
          allowed: !deny,
          label: deny ? 'Denied' : action.label.replace(/^Allow/, 'Allowed'),
          command: request.message.split('\n')[0],
          at: Date.now(),
        },
        ...list,
      ].slice(0, 20),
    );
  };

  return (
    <ScrollView contentContainerStyle={styles.column}>
      <View style={styles.topStrip}>
        <Wordmark />
        <View style={styles.link} accessible accessibilityLabel={online ? 'Connected' : 'Connecting'}>
          <Lamp state={online ? 'on' : 'warn'} />
          <Text style={[styles.linkText, { color: t.ink2 }]}>{online ? 'Connected' : 'Connecting'}</Text>
        </View>
      </View>

      {error ? <Notice text={error} /> : null}

      {requests.length === 0 ? (
        <View style={styles.intro}>
          <Text accessibilityRole="header" style={[styles.headline, { color: t.ink }]}>
            Nothing waiting
          </Text>
          <Text style={[styles.body, { color: t.ink2 }]}>
            When an agent on your computer needs permission, the request appears here with the exact command.
          </Text>
        </View>
      ) : (
        requests.map((r) => (
          <RequestPlate key={r.seq} request={r} now={now} busy={sending === r.seq} onAnswer={(i) => answer(r, i)} />
        ))
      )}

      <Recess>
        <StatusRow lamp={online ? 'on' : 'warn'} term="Computer" value={online ? 'Linked and listening' : 'Reconnecting'} />
        <Rule />
        <StatusRow lamp={pushLine[push].lamp} term="Notifications" value={pushLine[push].value} />
      </Recess>

      {history.length ? (
        <View style={styles.log}>
          <Text style={[styles.fieldLabel, { color: t.ink }]}>Answered from this phone</Text>
          <View>
            {history.map((h) => (
              <View key={h.key}>
                <Rule />
                <View style={styles.logRow} accessible accessibilityLabel={`${h.label}: ${h.command}`}>
                  <Lamp state={h.allowed ? 'on' : 'alert'} />
                  <Text style={[styles.logLabel, { color: t.ink }]}>{h.label}</Text>
                  <Text style={[styles.logCommand, { color: t.ink2 }]} numberOfLines={1}>
                    {h.command}
                  </Text>
                </View>
              </View>
            ))}
            <Rule />
          </View>
        </View>
      ) : null}

      <Pressable
        accessibilityRole="button"
        onPress={onUnpair}
        style={({ pressed }) => [styles.unpair, pressed && { opacity: 0.6 }]}>
        <Text style={[styles.unpairText, { color: t.ink2 }]}>Unpair this computer</Text>
      </Pressable>
    </ScrollView>
  );
}

/** The request itself: who is asking, the exact command, how long is left, and the keys to answer. */
function RequestPlate({
  request,
  now,
  busy,
  onAnswer,
}: {
  request: PhoneRequest;
  now: number;
  busy: boolean;
  onAnswer: (index: number) => void;
}) {
  const t = useTheme();
  const [drop] = useState(() => new Animated.Value(0));
  const [lift] = useState(() => drop.interpolate({ inputRange: [0, 1], outputRange: [-16, 0] }));

  // The one authored motion: the plate drops into place, as the card does from the Mac's notch.
  useEffect(() => {
    let cancelled = false;
    AccessibilityInfo.isReduceMotionEnabled()
      .catch(() => false)
      .then((reduce) => {
        if (cancelled) return;
        if (reduce) drop.setValue(1);
        else
          Animated.timing(drop, {
            toValue: 1,
            duration: 420,
            easing: Easing.bezier(0.16, 1, 0.3, 1),
            useNativeDriver: Platform.OS !== 'web',
          }).start();
      });
    return () => {
      cancelled = true;
    };
  }, [drop]);

  const left = Math.max(0, REQUEST_LIFETIME_MS - (now - request.at));
  const seconds = Math.ceil(left / 1000);
  const urgent = seconds <= 15;
  const [command, ...rest] = request.message.split('\n');
  const agent = request.title.replace(/\s+needs permission.*$/i, '') || 'An agent';
  const rawFolder = rest.join(' ').replace(/^Folder:\s*/i, '').trim();
  const folder = rawFolder === '~' ? 'your home folder' : rawFolder;

  return (
    <Animated.View
      style={{
        opacity: drop,
        transform: [{ translateY: lift }],
      }}>
      <Faceplate style={styles.plate}>
        <View style={styles.plateHead}>
          <Text accessibilityRole="header" style={[styles.title, { color: t.ink }]}>
            {agent} asks to run
          </Text>
          {request.high ? (
            <View style={[styles.risk, { backgroundColor: t.lampRed }]}>
              <Text style={styles.riskText}>High risk</Text>
            </View>
          ) : null}
        </View>

        <Recess style={styles.commandWell}>
          <Text style={[styles.command, { color: t.ink }]} selectable>
            {command}
          </Text>
        </Recess>

        <View style={styles.meta}>
          <Text style={[styles.metaText, { color: t.ink2 }]} numberOfLines={1}>
            {folder ? `In ${folder}` : ' '}
          </Text>
          <Text style={[styles.metaText, styles.tabular, { color: urgent ? t.ink : t.ink2 }]}>{seconds} s left</Text>
        </View>
        <View
          style={[styles.track, { backgroundColor: t.plateDeep }]}
          accessibilityRole="progressbar"
          accessibilityLabel="Time left to answer"
          accessibilityValue={{ min: 0, max: 110, now: seconds }}>
          <View
            style={[
              styles.trackFill,
              { width: `${(left / REQUEST_LIFETIME_MS) * 100}%`, backgroundColor: urgent ? t.lampAmber : t.ink3 },
            ]}
          />
        </View>

        <View style={styles.keys}>
          {request.actions.map((a, i) => (
            <Key
              key={a.label}
              label={a.label}
              kind={isDeny(a.label) ? 'ink' : i === 0 ? 'signal' : 'plate'}
              disabled={busy}
              onPress={() => onAnswer(i)}
            />
          ))}
        </View>
      </Faceplate>
    </Animated.View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1 },
  fill: { flex: 1 },
  column: {
    width: '100%',
    maxWidth: 520,
    alignSelf: 'center',
    paddingHorizontal: 3 * u,
    paddingTop: 2 * u,
    paddingBottom: 6 * u,
    gap: 3 * u,
  },
  topStrip: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', minHeight: 44 },
  wordmark: { fontFamily: font.heavy, fontSize: 21, letterSpacing: -0.6, lineHeight: 44 },
  wordmarkSub: { fontFamily: font.medium, letterSpacing: -0.3 },
  link: { flexDirection: 'row', alignItems: 'center', gap: u },
  linkText: { fontFamily: font.medium, fontSize: 15 },
  intro: { gap: 12, paddingTop: 2 * u },
  headline: { fontFamily: font.legend, fontSize: 34, lineHeight: 37, letterSpacing: -1.2 },
  title: { fontFamily: font.legend, fontSize: 21, lineHeight: 25, letterSpacing: -0.4, flexShrink: 1 },
  body: { fontFamily: font.body, fontSize: 17, lineHeight: 26 },
  source: { padding: 2 * u, gap: 4 },
  term: { fontFamily: font.legend, fontSize: 15 },
  sourceText: { fontFamily: font.body, fontSize: 15, lineHeight: 22 },
  code: { fontFamily: font.mono, fontSize: 13.5 },
  manual: { gap: u },
  fieldLabel: { fontFamily: font.legend, fontSize: 15 },
  well: { flexDirection: 'row', alignItems: 'center', gap: 6, padding: 6, borderRadius: 10 },
  input: { flex: 1, minWidth: 0, minHeight: 44, paddingHorizontal: 10, fontFamily: font.mono, fontSize: 15, outlineWidth: 0 },
  wellKey: { minHeight: 44 },
  notice: { flexDirection: 'row', alignItems: 'center', gap: 10 },
  noticeText: { fontFamily: font.medium, fontSize: 15, lineHeight: 21, flex: 1 },
  fine: { fontFamily: font.body, fontSize: 14, lineHeight: 20 },
  scanBar: { padding: 3 * u, gap: 2 * u },
  plate: { padding: 20, gap: 2 * u },
  plateHead: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 12 },
  risk: { borderRadius: 999, paddingHorizontal: 10, paddingVertical: 4 },
  riskText: { fontFamily: font.legend, fontSize: 13, color: '#ffffff' },
  commandWell: { padding: 14 },
  command: { fontFamily: font.mono, fontSize: 15, lineHeight: 22 },
  meta: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'baseline', gap: 12 },
  metaText: { fontFamily: font.body, fontSize: 15, flexShrink: 1 },
  tabular: { fontVariant: ['tabular-nums'] },
  track: { height: 4, borderRadius: 2, overflow: 'hidden', marginTop: -u },
  trackFill: { height: '100%', borderRadius: 2 },
  keys: { gap: 10, marginTop: 4 },
  log: { gap: 10 },
  logRow: { flexDirection: 'row', alignItems: 'center', gap: 12, minHeight: 48 },
  logLabel: { fontFamily: font.legend, fontSize: 15 },
  logCommand: { fontFamily: font.mono, fontSize: 13.5, flex: 1 },
  unpair: { minHeight: 44, alignItems: 'center', justifyContent: 'center' },
  unpairText: { fontFamily: font.medium, fontSize: 15, textDecorationLine: 'underline' },
});
