import {
  donationMetrics,
  listAdminDonations,
  type AdminDonation,
  type DonationMetrics,
} from '../../lib/api';
import { useAsync } from '../../lib/useAsync';
import { Loading, ErrorState, EmptyState, StatusBadge } from '../ui';

export function DonationsTab() {
  const donations = useAsync<AdminDonation[]>(listAdminDonations);
  const metrics = useAsync<DonationMetrics>(donationMetrics);

  function reloadAll() {
    donations.reload();
    metrics.reload();
  }

  return (
    <section className="gm-glass gm-panel">
      <div className="gm-panel-head">
        <div>
          <h2>Donations</h2>
          <p>Oversight of surplus-food donations across the platform.</p>
        </div>
        <button type="button" className="gm-btn gm-btn-ghost gm-btn-sm" onClick={reloadAll}>
          Refresh
        </button>
      </div>

      <div className="gm-metrics">
        <div className="gm-glass gm-metric">
          <div className="label">Collected donations</div>
          <div className="value accent">
            {metrics.loading ? '…' : metrics.error ? '—' : (metrics.data?.collectedCount ?? 0)}
          </div>
        </div>
        <div className="gm-glass gm-metric">
          <div className="label">Total quantity rescued</div>
          <div className="value accent">
            {metrics.loading ? '…' : metrics.error ? '—' : (metrics.data?.totalQuantityRescued ?? 0)}
          </div>
        </div>
      </div>
      {metrics.error && <div className="gm-flash bad">Metrics: {metrics.error}</div>}

      {donations.loading && <Loading label="Loading donations…" />}
      {donations.error && !donations.loading && (
        <ErrorState message={donations.error} onRetry={donations.reload} />
      )}
      {!donations.loading && !donations.error && donations.data && donations.data.length === 0 && (
        <EmptyState title="No donations yet" hint="Donations logged by shops will appear here for oversight." />
      )}

      {!donations.loading && !donations.error && donations.data && donations.data.length > 0 && (
        <div className="gm-table-wrap">
          <table className="gm-table">
            <thead>
              <tr>
                <th>Store</th>
                <th>Product</th>
                <th style={{ textAlign: 'right' }}>Quantity</th>
                <th>Status</th>
                <th>Claimed by</th>
                <th>Collected by</th>
              </tr>
            </thead>
            <tbody>
              {donations.data.map((d) => (
                <tr key={d.donationId}>
                  <td>{d.store ?? '—'}</td>
                  <td>{d.productRef ?? '—'}</td>
                  <td className="num">{d.quantity} {d.unit ?? ''}</td>
                  <td><StatusBadge status={d.status} /></td>
                  <td className="muted">{d.claimedBy ?? '—'}</td>
                  <td className="muted">{d.collectedBy ?? '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}
