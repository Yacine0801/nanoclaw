/**
 * Anti-spam: rate-limit error detection and per-JID notification cooldown.
 */

// Cooldown: 4h between error notifications per JID
const ERROR_COOLDOWN_MS = 4 * 60 * 60 * 1000;
const lastErrorNotifiedAt: Record<string, number> = {};

const RATE_LIMIT_PATTERNS = [
  'hit your limit',
  'rate limit',
  'rate_limit',
  'overloaded',
  '429',
];

export function isRateLimitError(text: string): boolean {
  const lower = text.toLowerCase();
  return RATE_LIMIT_PATTERNS.some((p) => lower.includes(p));
}

export function shouldNotifyError(chatJid: string): boolean {
  const last = lastErrorNotifiedAt[chatJid];
  if (!last) return true;
  return Date.now() - last >= ERROR_COOLDOWN_MS;
}

export function markErrorNotified(chatJid: string): void {
  lastErrorNotifiedAt[chatJid] = Date.now();
}

export function resetErrorCooldown(chatJid: string): void {
  delete lastErrorNotifiedAt[chatJid];
}
