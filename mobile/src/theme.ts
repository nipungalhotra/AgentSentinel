// loggdin design tokens for the phone app, taken from DESIGN.md ("The Braun Control Panel"):
// an anodised plate with raised faceplates and machined recesses, engraved hairline rules,
// status lamps, and exactly one signal-orange key per view. Dark mode is a token swap only.
import { Platform, useColorScheme } from 'react-native';

const shared = {
  signal: '#ee6a3d',
  signalPress: '#f4855e',
  onSignal: '#1d1a17',
  lampGreen: '#3f9a62',
  lampAmber: '#e08a1e',
  lampRed: '#d2452f',
};

const light = {
  ...shared,
  dark: false,
  plate: '#e8e5de',
  plateHi: '#f3f1ec',
  plateLo: '#dcd8cf',
  plateDeep: '#d0cbc1',
  ink: '#23221f',
  ink2: '#57544e',
  ink3: '#6e6a63',
  rule: '#c3bdb1',
  ruleHi: 'rgba(255,255,255,0.7)',
  lampOff: '#b8b2a6',
  keyRest: '0 1px 0 rgba(0,0,0,0.16), 0 4px 8px -4px rgba(0,0,0,0.35), inset 0 1px 0 rgba(255,255,255,0.7)',
  keyDown: '0 1px 2px -1px rgba(0,0,0,0.3), inset 0 1px 2px rgba(0,0,0,0.12)',
  recess: 'inset 0 1px 3px rgba(0,0,0,0.13), inset 0 0 0 1px #c3bdb1, 0 1px 0 rgba(255,255,255,0.7)',
  faceplate: 'inset 0 0 0 1px #c3bdb1, inset 0 2px 0 rgba(255,255,255,0.7), 0 1px 0 rgba(255,255,255,0.7)',
};

const dark: typeof light = {
  ...shared,
  dark: true,
  plate: '#1c1c1b',
  plateHi: '#252524',
  plateLo: '#161615',
  plateDeep: '#111110',
  ink: '#ecebe6',
  ink2: '#b3b0a8',
  ink3: '#9c988f',
  rule: '#34332f',
  ruleHi: 'rgba(255,255,255,0.06)',
  lampOff: '#4a4843',
  keyRest: '0 1px 0 rgba(0,0,0,0.5), 0 4px 8px -4px rgba(0,0,0,0.7), inset 0 1px 0 rgba(255,255,255,0.06)',
  keyDown: '0 1px 2px -1px rgba(0,0,0,0.6), inset 0 1px 2px rgba(0,0,0,0.35)',
  recess: 'inset 0 1px 3px rgba(0,0,0,0.4), inset 0 0 0 1px #34332f, 0 1px 0 rgba(255,255,255,0.06)',
  faceplate: 'inset 0 0 0 1px #34332f, inset 0 2px 0 rgba(255,255,255,0.06), 0 1px 0 rgba(255,255,255,0.06)',
};

export type Theme = typeof light;

export function useTheme(): Theme {
  return useColorScheme() === 'dark' ? dark : light;
}

/** Archivo, loaded in App.tsx. Legends are heavy and tight; reading text is regular. */
export const font = {
  body: 'Archivo_400Regular',
  medium: 'Archivo_500Medium',
  legend: 'Archivo_600SemiBold',
  heavy: 'Archivo_700Bold',
  // Monospace is for commands only.
  mono: Platform.select({ ios: 'Menlo', android: 'monospace', default: 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace' }) as string,
};

/** 8px panel grid. */
export const u = 8;
