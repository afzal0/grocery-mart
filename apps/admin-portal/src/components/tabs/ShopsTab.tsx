import { useState } from 'react';
import { approveShop, listAdminShops, rejectShop, type AdminShop } from '../../lib/api';
import { useAsync } from '../../lib/useAsync';
import { Loading, ErrorState, EmptyState, StatusBadge, Badge } from '../ui';

function isPending(status: string): boolean {
  return status.toLowerCase() === 'pending' || status.toLowerCase() === 'pending_approval';
}

export function ShopsTab() {
  const { data, loading, error, reload } = useAsync<AdminShop[]>(listAdminShops);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [flash, setFlash] = useState<{ kind: 'ok' | 'bad'; text: string } | null>(null);

  async function act(shop: AdminShop, kind: 'approve' | 'reject') {
    setBusyId(shop.id);
    setFlash(null);
    try {
      const res = kind === 'approve' ? await approveShop(shop.id) : await rejectShop(shop.id);
      setFlash({ kind: 'ok', text: `${shop.name} → ${res.status}` });
      reload();
    } catch (e) {
      setFlash({ kind: 'bad', text: e instanceof Error ? e.message : String(e) });
    } finally {
      setBusyId(null);
    }
  }

  return (
    <section className="gm-glass gm-panel">
      <div className="gm-panel-head">
        <div>
          <h2>Shops</h2>
          <p>Approve or reject shops awaiting onboarding review.</p>
        </div>
        <button type="button" className="gm-btn gm-btn-ghost gm-btn-sm" onClick={reload} disabled={loading}>
          Refresh
        </button>
      </div>

      {flash && <div className={`gm-flash ${flash.kind}`}>{flash.text}</div>}

      {loading && <Loading label="Loading shops…" />}
      {error && !loading && <ErrorState message={error} onRetry={reload} />}
      {!loading && !error && data && data.length === 0 && (
        <EmptyState title="No shops yet" hint="Shops appear here once owners register their stores." />
      )}

      {!loading && !error && data && data.length > 0 && (
        <div className="gm-table-wrap">
          <table className="gm-table">
            <thead>
              <tr>
                <th>Name</th>
                <th>Owner</th>
                <th>Status</th>
                <th>Open</th>
                <th>Address</th>
                <th style={{ textAlign: 'right' }}>Actions</th>
              </tr>
            </thead>
            <tbody>
              {data.map((shop) => (
                <tr key={shop.id}>
                  <td>{shop.name}</td>
                  <td className="muted">{shop.owner_email ?? '—'}</td>
                  <td><StatusBadge status={shop.status} /></td>
                  <td>
                    {shop.is_open ? <Badge tone="ok">open</Badge> : <Badge tone="neutral">closed</Badge>}
                  </td>
                  <td className="muted">{shop.address ?? '—'}</td>
                  <td>
                    <div className="gm-row-actions">
                      {isPending(shop.status) ? (
                        <>
                          <button
                            type="button"
                            className="gm-btn gm-btn-sm"
                            onClick={() => act(shop, 'approve')}
                            disabled={busyId === shop.id}
                          >
                            {busyId === shop.id ? '…' : 'Approve'}
                          </button>
                          <button
                            type="button"
                            className="gm-btn gm-btn-ghost gm-btn-sm"
                            onClick={() => act(shop, 'reject')}
                            disabled={busyId === shop.id}
                          >
                            Reject
                          </button>
                        </>
                      ) : (
                        <span className="muted">—</span>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}
