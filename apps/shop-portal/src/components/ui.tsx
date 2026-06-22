// Small presentational helpers shared by every dashboard tab so loading / error /
// empty states stay consistent across the portal. Pure formatters live in
// ../lib/format so this module only exports components (Fast Refresh friendly).
import type { ReactNode } from 'react';
import { statusTone, type Tone } from '../lib/format';

export function Loading({ label = 'Loading…' }: { label?: string }) {
  return (
    <div className="gm-state">
      <div className="gm-spinner" aria-hidden />
      {label}
    </div>
  );
}

export function ErrorState({ message, onRetry }: { message: string; onRetry?: () => void }) {
  return (
    <div className="gm-state error">
      <div>{message}</div>
      {onRetry && (
        <button className="gm-btn gm-btn-ghost gm-btn-sm" type="button" onClick={onRetry} style={{ marginTop: '0.9rem' }}>
          Retry
        </button>
      )}
    </div>
  );
}

export function EmptyState({ children }: { children: ReactNode }) {
  return <div className="gm-state">{children}</div>;
}

export function Badge({ children, tone }: { children: ReactNode; tone?: Tone }) {
  return <span className={`gm-badge${tone ? ` ${tone}` : ''}`}>{children}</span>;
}

export function StatusBadge({ status }: { status: string }) {
  return <Badge tone={statusTone(status)}>{status.replace(/_/g, ' ')}</Badge>;
}
