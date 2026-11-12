// The control-panel parts: detented keys, status lamps, engraved rules, machined recesses.
import type { ReactNode } from 'react';
import { Pressable, StyleSheet, Text, View, type StyleProp, type ViewStyle } from 'react-native';

import { font, u, useTheme } from './theme';

type KeyKind = 'signal' | 'plate' | 'ink';

/** A key travels 2px when pressed. `signal` is the one orange key of a view; `ink` is the inverse keycap. */
export function Key({
  label,
  kind = 'plate',
  onPress,
  disabled,
  style,
}: {
  label: string;
  kind?: KeyKind;
  onPress: () => void;
  disabled?: boolean;
  style?: StyleProp<ViewStyle>;
}) {
  const t = useTheme();
  const face = kind === 'signal' ? t.signal : kind === 'ink' ? t.ink : t.plateHi;
  const pressedFace = kind === 'signal' ? t.signalPress : face;
  const legend = kind === 'signal' ? t.onSignal : kind === 'ink' ? t.plate : t.ink;
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={label}
      accessibilityState={{ disabled: !!disabled }}
      disabled={disabled}
      onPress={onPress}
      style={({ pressed, focused }: { pressed: boolean; focused?: boolean }) => [
        styles.key,
        { backgroundColor: pressed ? pressedFace : face, boxShadow: pressed ? t.keyDown : t.keyRest },
        pressed && styles.keyDown,
        focused && { outlineColor: t.signal, outlineWidth: 2, outlineOffset: 3, outlineStyle: 'solid' },
        disabled && styles.keyDisabled,
        style,
      ]}>
      <Text style={[styles.keyLegend, { color: legend }]} numberOfLines={1}>
        {label}
      </Text>
    </Pressable>
  );
}

/** An 8px status lamp. Colour is status only, never decoration. */
export function Lamp({ state }: { state: 'on' | 'warn' | 'alert' | 'off' }) {
  const t = useTheme();
  const color = state === 'on' ? t.lampGreen : state === 'warn' ? t.lampAmber : state === 'alert' ? t.lampRed : t.lampOff;
  return (
    <View
      accessibilityElementsHidden
      importantForAccessibility="no"
      style={[
        styles.lamp,
        { backgroundColor: color },
        state !== 'off' && { boxShadow: `0 0 0 2px ${color}38, inset 0 -1px 1px rgba(0,0,0,0.25)` },
        state === 'off' && { boxShadow: 'inset 0 1px 1px rgba(0,0,0,0.25)' },
      ]}
    />
  );
}

/** Engraved divider: a dark hairline with a light lower lip. */
export function Rule() {
  const t = useTheme();
  return (
    <View>
      <View style={{ height: 1, backgroundColor: t.rule }} />
      <View style={{ height: 1, backgroundColor: t.ruleHi }} />
    </View>
  );
}

/** A panel machined into the plate. */
export function Recess({ children, style }: { children: ReactNode; style?: StyleProp<ViewStyle> }) {
  const t = useTheme();
  return <View style={[styles.recess, { backgroundColor: t.plateLo, boxShadow: t.recess }, style]}>{children}</View>;
}

/** A plate raised a millimetre from the ground: holds the thing that needs an answer. */
export function Faceplate({ children, style }: { children: ReactNode; style?: StyleProp<ViewStyle> }) {
  const t = useTheme();
  return <View style={[styles.faceplate, { backgroundColor: t.plateHi, boxShadow: t.faceplate }, style]}>{children}</View>;
}

/** One line of a spec plate: a lamp, a term, and its value. */
export function StatusRow({ lamp, term, value }: { lamp: 'on' | 'warn' | 'alert' | 'off'; term: string; value: string }) {
  const t = useTheme();
  return (
    <View style={styles.statusRow} accessible accessibilityLabel={`${term}: ${value}`}>
      <Lamp state={lamp} />
      <Text style={[styles.term, { color: t.ink }]}>{term}</Text>
      <Text style={[styles.value, { color: t.ink2 }]}>{value}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  key: { minHeight: 48, borderRadius: 6, paddingHorizontal: 18, alignItems: 'center', justifyContent: 'center' },
  keyDown: { transform: [{ translateY: 2 }] },
  keyDisabled: { opacity: 0.55 },
  keyLegend: { fontFamily: font.legend, fontSize: 16, letterSpacing: -0.1 },
  lamp: { width: u, height: u, borderRadius: u / 2 },
  recess: { borderRadius: 12 },
  faceplate: { borderRadius: 16 },
  statusRow: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 14, paddingHorizontal: 2 * u },
  term: { fontFamily: font.legend, fontSize: 15, width: 112 },
  value: { fontFamily: font.body, fontSize: 15, lineHeight: 21, flex: 1 },
});
