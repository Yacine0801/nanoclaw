export function calculateBackoff(
  consecutiveErrors: number,
  baseMs: number,
  maxMs: number,
): number {
  return consecutiveErrors > 0
    ? Math.min(baseMs * Math.pow(2, consecutiveErrors), maxMs)
    : baseMs;
}
