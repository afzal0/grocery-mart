import { useState } from 'react';
import { confirmMerge, listMergeQueue, type MergeCandidate } from '../../lib/api';
import { useAsync } from '../../lib/useAsync';
import { Loading, ErrorState, EmptyState, Badge } from '../ui';

function label(brand: string | null, name: string | null, size: string | null): string {
  return [brand, name, size].filter(Boolean).join(' · ') || '—';
}

function simTone(sim: number): 'ok' | 'warn' | 'danger' {
  if (sim >= 0.85) return 'ok';
  if (sim >= 0.65) return 'warn';
  return 'danger';
}

export function MergeQueueTab() {
  const { data, loading, error, reload } = useAsync<MergeCandidate[]>(listMergeQueue);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [flash, setFlash] = useState<{ kind: 'ok' | 'bad'; text: string } | null>(null);

  async function confirm(c: MergeCandidate) {
    setBusyId(c.candidate_id);
    setFlash(null);
    try {
      await confirmMerge(c.candidate_id);
      setFlash({ kind: 'ok', text: `Merged "${label(c.raw_brand, c.raw_name, c.raw_size)}" into the master catalog.` });
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
          <h2>Merge queue</h2>
          <p>Confirm a submitted store product maps to its candidate master product.</p>
        </div>
        <button type="button" className="gm-btn gm-btn-ghost gm-btn-sm" onClick={reload} disabled={loading}>
          Refresh
        </button>
      </div>

      {flash && <div className={`gm-flash ${flash.kind}`}>{flash.text}</div>}

      {loading && <Loading label="Loading merge candidates…" />}
      {error && !loading && <ErrorState message={error} onRetry={reload} />}
      {!loading && !error && data && data.length === 0 && (
        <EmptyState title="Queue is clear" hint="No store products are awaiting a catalog merge decision." />
      )}

      {!loading && !error && data && data.length > 0 && (
        <div className="gm-table-wrap">
          <table className="gm-table">
            <thead>
              <tr>
                <th>Submitted item</th>
                <th>Shop</th>
                <th>Candidate master</th>
                <th style={{ textAlign: 'right' }}>Similarity</th>
                <th style={{ textAlign: 'right' }}>Action</th>
              </tr>
            </thead>
            <tbody>
              {data.map((c) => (
                <tr key={c.candidate_id}>
                  <td>{label(c.raw_brand, c.raw_name, c.raw_size)}</td>
                  <td className="muted">{c.shop_name ?? '—'}</td>
                  <td>{label(c.canonical_brand, c.canonical_name, c.canonical_size)}</td>
                  <td className="num">
                    <Badge tone={simTone(c.similarity)}>{Math.round(c.similarity * 100)}%</Badge>
                  </td>
                  <td>
                    <div className="gm-row-actions">
                      <button
                        type="button"
                        className="gm-btn gm-btn-sm"
                        onClick={() => confirm(c)}
                        disabled={busyId === c.candidate_id}
                      >
                        {busyId === c.candidate_id ? 'Merging…' : 'Confirm merge'}
                      </button>
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
