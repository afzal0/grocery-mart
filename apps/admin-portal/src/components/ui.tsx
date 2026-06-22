// Shared presentational helpers for the admin console (loading / error / empty / badges).
import type { ReactNode } from 'react';

export function Loading({ label = 'Loading…' }: { label?: string }) {
  return (
    <div className="gm-state" role="status" aria-live="polite">
      <div className="gm-spinner" />
      {label}
    </div>
  );
}

export function ErrorState({ message, onRetry }: { message: string; onRetry?: () => void }) {
  return (
    <div className="gm-state gm-error-state" role="alert">
      <div className="gm-state-title">Something went wrong</div>
      <div>{message}</div>
      {onRetry && (
        <div style={{ marginTop: '1rem' }}>
          <button type="button" className="gm-btn gm-btn-ghost gm-btn-sm" onClick={onRetry}>
            Try again
          </button>
        </div>
      )}
    </div>
  );
}

export function EmptyState({ title, hint }: { title: string; hint?: string }) {
  return (
    <div className="gm-state">
      <div className="gm-state-title">{title}</div>
      {hint && <div>{hint}</div>}
    </div>
  );
}

type Tone = 'ok' | 'warn' | 'danger' | 'info' | 'neutral';

const STATUS_TONE: Record<string, Tone> = {
  // shops / ngos / generic lifecycle
  approved: 'ok',
  active: 'ok',
  open: 'ok',
  confirmed: 'ok',
  collected: 'ok',
  paid: 'ok',
  paid_out: 'ok',
  pending: 'warn',
  pending_approval: 'warn',
  submitted: 'warn',
  claimed: 'info',
  available: 'info',
  scheduled: 'info',
  rejected: 'danger',
  suspended: 'danger',
  closed: 'danger',
  flagged: 'danger',
  failed: 'danger',
  failure: 'danger',
  denied: 'danger',
  disputed: 'danger',
  // audit outcomes
  success: 'ok',
  ok: 'ok',
  allowed: 'ok',
  error: 'danger',
};

export function toneFor(status: string | null | undefined): Tone {
  if (!status) return 'neutral';
  return STATUS_TONE[status.toLowerCase()] ?? 'neutral';
}

export function StatusBadge({ status }: { status: string | null | undefined }) {
  const label = status ?? '—';
  return <span className={`gm-badge ${toneFor(status)}`}>{label.replace(/_/g, ' ')}</span>;
}

export function Badge({ tone = 'neutral', children }: { tone?: Tone; children: ReactNode }) {
  return <span className={`gm-badge ${tone}`}>{children}</span>;
}

/** Formats a currency amount; backend amounts are already in major units. */
export function money(amount: number | null | undefined, currency: string | null | undefined): string {
  if (amount === null || amount === undefined) return '—';
  const cur = currency ?? '';
  try {
    return new Intl.NumberFormat(undefined, {
      style: cur ? 'currency' : 'decimal',
      currency: cur || undefined,
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    }).format(amount);
  } catch {
    return `${amount.toFixed(2)} ${cur}`.trim();
  }
}

export function dateTime(iso: string | null | undefined): string {
  if (!iso) return '—';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleString(undefined, {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
}
