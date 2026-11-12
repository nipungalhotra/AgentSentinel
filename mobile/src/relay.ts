// Talks to the loggdin phone relay. The wire protocol is the one in Sources/PhoneRelay.swift and
// bin/loggdin.py: the computer publishes a request to a secret topic, each button carries a
// pre-signed one-time reply, and the phone posts that reply to "<topic>-reply". The phone never
// holds the signing secret, so it cannot forge an answer for another request. Requests and their
// buttons arrive sealed ("lg1e …") and open only with the pairing key from the QR code.

import { openSealed } from './hmac';

/** `key` is the pairing key from the QR code (or a typed pairing code); without it the phone can't
 * open requests or register for notifications. */
export type Pairing = { server: string; topic: string; key?: string };

export type ReplyAction = { label: string; url: string; method: string; body: string };

export type PhoneRequest = {
  /** sequence_id: stable per request, used by the computer to clear it. */
  seq: string;
  title: string;
  message: string;
  /** When the computer sent it, in ms. */
  at: number;
  high: boolean;
  actions: ReplyAction[];
};

const DEFAULT_SERVER = 'https://ntfy.sh';
const TOPIC = /^loggdin-[a-z0-9]{8,64}$/;
const KEY = /^[a-f0-9]{16}$/;

/** "loggdin-…" or "loggdin-….<pairing key>" (the pairing code). */
function splitCode(code: string): { topic: string; key?: string } | null {
  const [topic, key, ...extra] = code.split('.');
  if (extra.length || !TOPIC.test(topic)) return null;
  if (key === undefined) return { topic };
  return KEY.test(key) ? { topic, key } : null;
}

/** Accepts a topic, a pairing code ("loggdin-….<key>"), or the QR code's link (pairing after "#"). */
export function parsePairing(input: string): Pairing | null {
  let text = input.trim();
  // The computer's QR code is a link to the web app with the pairing after "#": use that part.
  const hash = /^https?:\/\/[^/\s#]+\/?#(.+)$/.exec(text);
  if (hash) text = decodeURIComponent(hash[1]);
  const direct = splitCode(text);
  if (direct) return { server: DEFAULT_SERVER, ...direct };
  const m = /^(https?:\/\/[^/\s]+)\/([^/?#\s]+)\/?$/.exec(text);
  const onServer = m ? splitCode(m[2]) : null;
  if (m && onServer) return { server: m[1], ...onServer };
  return null;
}

/** A reply may only go to this pairing's own reply topic, whatever the message claims. */
export function isSafeReply(p: Pairing, action: ReplyAction): boolean {
  return action.url === `${p.server}/${p.topic}-reply` && action.method === 'POST' && action.body.startsWith('lg1 ');
}

export async function sendReply(action: ReplyAction): Promise<boolean> {
  try {
    const res = await fetch(action.url, { method: 'POST', body: action.body });
    return res.ok;
  } catch {
    return false;
  }
}

type Sealed = { t?: unknown; m?: unknown; h?: unknown; a?: unknown };

/** Requests arrive sealed; only the pairing key from the QR code or pairing code opens them. */
function toRequest(msg: any, p: Pairing): PhoneRequest | null | 'locked' {
  if (!msg || typeof msg.message !== 'string') return null;
  if (msg.message.startsWith('lg1e ')) {
    if (!p.key) return 'locked';
    const s = openSealed(p.key, msg.message) as Sealed | null;
    if (!s || typeof s.m !== 'string' || !Array.isArray(s.a)) return null;
    const actions: ReplyAction[] = s.a
      .filter((x): x is [string, string] => Array.isArray(x) && typeof x[0] === 'string' && typeof x[1] === 'string')
      .map(([label, body]) => ({ label, body, method: 'POST', url: `${p.server}/${p.topic}-reply` }));
    if (!actions.length) return null;
    return {
      seq: String(msg.sequence_id ?? msg.id),
      title: typeof s.t === 'string' ? s.t : 'Permission request',
      message: s.m,
      at: typeof msg.time === 'number' ? msg.time * 1000 : Date.now(),
      high: s.h === true,
      actions,
    };
  }
  if (!Array.isArray(msg.actions)) return null;
  const actions: ReplyAction[] = msg.actions
    .filter((a: any) => a && a.action === 'http' && typeof a.url === 'string' && typeof a.body === 'string')
    .map((a: any) => ({ label: String(a.label ?? ''), url: a.url, method: String(a.method ?? 'POST'), body: a.body }));
  if (!actions.length) return null;
  return {
    seq: String(msg.sequence_id ?? msg.id),
    title: String(msg.title ?? 'Permission request'),
    message: msg.message,
    at: typeof msg.time === 'number' ? msg.time * 1000 : Date.now(),
    high: msg.priority === 5,
    actions,
  };
}

type Handlers = {
  onStatus: (online: boolean) => void;
  onRequest: (r: PhoneRequest) => void;
  onClear: (seq: string) => void;
  /** A request arrived that this pairing can't open (paired by topic only, without the key). */
  onLocked?: () => void;
};

/** Opens a live connection that reconnects by itself. Returns a function that closes it. */
export function connect(p: Pairing, h: Handlers): () => void {
  let closed = false;
  let socket: WebSocket | null = null;
  let retry: ReturnType<typeof setTimeout> | null = null;
  let backoff = 1000;

  const open = () => {
    if (closed) return;
    // since=2m replays requests that may still be waiting; cleared ones are replayed as cleared.
    const url = `${p.server.replace(/^http/, 'ws')}/${p.topic}/ws?since=2m`;
    const ws = new WebSocket(url);
    socket = ws;
    ws.onopen = () => {
      backoff = 1000;
      h.onStatus(true);
    };
    ws.onmessage = (event) => {
      let msg: any;
      try {
        msg = JSON.parse(String(event.data));
      } catch {
        return;
      }
      if (msg.event === 'message') {
        const r = toRequest(msg, p);
        if (r === 'locked') h.onLocked?.();
        else if (r) h.onRequest(r);
      } else if (msg.event === 'message_clear' || msg.event === 'message_delete') {
        if (msg.sequence_id) h.onClear(String(msg.sequence_id));
      }
    };
    ws.onerror = () => ws.close();
    ws.onclose = () => {
      if (socket !== ws || closed) return;
      h.onStatus(false);
      retry = setTimeout(open, backoff);
      backoff = Math.min(backoff * 2, 30_000);
    };
  };

  open();
  return () => {
    closed = true;
    if (retry) clearTimeout(retry);
    socket?.close();
  };
}
