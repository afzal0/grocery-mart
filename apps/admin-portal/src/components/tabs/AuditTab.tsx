import { useState } from 'react';
import { listAudit, type AuditEntry } from '../../lib/api';
import { useAsync } from '../../lib/useAsync';
import { Loading, ErrorState, EmptyState, StatusBadge, dateTime } from '../ui';

export function AuditTab() {
  // draft filter (form) vs applied filter (drives the request)
  const [actor, setActor] = useState('');
  const [action, setAction] = useState('');
  const [limit, setLimit] = useState('50');
  const [applied, setApplied] = useState<{ actor: string; action: string; limit: number }>({
    actor: '',
    action: '',
    limit: 50,
  });

  const { data, loading, error, reload } = useAsync<AuditEntry[]>(
    () =>
      listAudit({
        actor: applied.actor || undefined,
        action: applied.action || undefined,
        limit: applied.limit,
      }),
    [applied.actor, applied.action, applied.limit],
  );

  function apply(e: React.FormEvent) {
    e.preventDefault();
    const parsed = Number(limit);
    setApplied({
      actor: actor.trim(),
      action: action.trim(),
      limit: Number.isFinite(parsed) && parsed > 0 ? parsed : 50,
    });
  }

  function clearAll() {
    setActor('');
    setAction('');
    setLimit('50');
    setApplied({ actor: '', action: '', limit: 50 });
  }

  return (
    <section className="gm-glass gm-panel">
      <div className="gm-panel-head">
        <div>
          <h2>Audit log</h2>
          <p>Filterable trail of privileged actions across the platform.</p>
        </div>
        <button type="button" className="gm-btn gm-btn-ghost gm-btn-sm" onClick={reload} disabled={loading}>
          Refresh
        </button>
      </div>

      <form className="gm-inline-form" onSubmit={apply} style={{ marginBottom: '1.2rem' }}>
        <div className="gm-field grow">
          <label htmlFor="aud-actor">Actor</label>
          <input id="aud-actor" className="gm-input" placeholder="actor id" value={actor} onChange={(e) => setActor(e.target.value)} />
        </div>
        <div className="gm-field grow">
          <label htmlFor="aud-action">Action</label>
          <input id="aud-action" className="gm-input" placeholder="e.g. shop.approve" value={action} onChange={(e) => setAction(e.target.value)} />
        </div>
        <div className="gm-field">
          <label htmlFor="aud-limit">Limit</label>
          <input id="aud-limit" className="gm-input" style={{ width: '6rem' }} type="number" min="1" max="500" value={limit} onChange={(e) => setLimit(e.target.value)} />
        </div>
        <button type="submit" className="gm-btn gm-btn-sm" disabled={loading}>Filter</button>
        <button type="button" className="gm-btn gm-btn-ghost gm-btn-sm" onClick={clearAll} disabled={loading}>Clear</button>
      </form>

      {loading && <Loading label="Loading audit entries…" />}
      {error && !loading && <ErrorState message={error} onRetry={reload} />}
      {!loading && !error && data && data.length === 0 && (
        <EmptyState title="No audit entries" hint="Try widening the filters or raising the limit." />
      )}

      {!loading && !error && data && data.length > 0 && (
        <div className="gm-table-wrap">
          <table className="gm-table">
            <thead>
              <tr>
                <th>When</th>
                <th>Actor</th>
                <th>Action</th>
                <th>Target</th>
                <th>Outcome</th>
                <th>Source IP</th>
              </tr>
            </thead>
            <tbody>
              {data.map((e) => (
                <tr key={e.id}>
                  <td className="muted">{dateTime(e.createdAt)}</td>
                  <td className="gm-mono">{e.actorId ?? '—'}</td>
                  <td>{e.action}</td>
                  <td className="muted">
                    {e.targetType ? `${e.targetType}${e.targetId ? ` · ${e.targetId}` : ''}` : '—'}
                  </td>
                  <td><StatusBadge status={e.outcome} /></td>
                  <td className="gm-mono muted">{e.sourceIp ?? '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}
