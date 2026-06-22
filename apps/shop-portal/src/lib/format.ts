// Pure formatting / status helpers shared across the dashboard tabs.
// Kept free of JSX so React Fast Refresh only ever sees component modules.

export type Tone = 'ok' | 'warn' | 'bad' | 'info';

/** Maps a status-ish string onto one of the gm-badge tone classes. */
export function statusTone(status: string): Tone {
  const s = status.toLowerCase();
  if (['active', 'approved', 'paid', 'delivered', 'matched', 'collected', 'auto', 'confirmed', 'available'].some((k) => s.includes(k)))
    return 'ok';
  if (['pending', 'review', 'processing', 'assigned', 'claimed', 'unmatched', 'scheduled', 'manual'].some((k) => s.includes(k)))
    return 'warn';
  if (['reject', 'cancel', 'fail', 'suspend', 'refund', 'unavailable', 'flagged'].some((k) => s.includes(k)))
    return 'bad';
  return 'info';
}

/** Format a numeric amount with its currency; falls back gracefully when null. */
export function money(amount: number | null | undefined, currency?: string | null): string {
  if (amount === null || amount === undefined) return '—';
  const cur = currency ?? '';
  return `${cur ? `${cur} ` : ''}${amount.toFixed(2)}`;
}

/** Short, locale-aware date/time for table cells; tolerant of nulls. */
export function fmtDate(iso: string | null | undefined): string {
  if (!iso) return '—';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
}
