import { useEffect, useState } from 'react';
import {
  getSettlement,
  getPayouts,
  type Settlement,
  type Payout,
} from '../lib/api';
import { Loading, ErrorState, EmptyState, StatusBadge } from './ui';
import { money, fmtDate } from '../lib/format';

export function SettlementTab() {
  return (
    <div className="gm-section-grid">
      <SettlementPanel />
      <PayoutsPanel />
    </div>
  );
}

function SettlementPanel() {
  const [data, setData] = useState<Settlement | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadErr, setLoadErr] = useState('');

  async function load() {
    setLoading(true);
    setLoadErr('');
    try {
      setData(await getSettlement(50));
    } catch (err) {
      setLoadErr((err as Error).message);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void load();
  }, []);

  // Currency for the summary cards — take it from the first entry, default AUD.
  const currency = data?.entries[0]?.currency ?? 'AUD';

  return (
    <section className="gm-glass gm-panel">
      <div className="gm-panel-head">
        <div>
          <h2>Settlement</h2>
          <p>Gross sales, platform commission, GST and what you're owed.</p>
        </div>
        <button className="gm-btn gm-btn-ghost gm-btn-sm" type="button" onClick={() => void load()}>
          Refresh
        </button>
      </div>
      {loading ? (
        <Loading label="Loading settlement…" />
      ) : loadErr ? (
        <ErrorState message={loadErr} onRetry={() => void load()} />
      ) : !data ? (
        <EmptyState>No settlement data.</EmptyState>
      ) : (
        <>
          <div className="gm-kv">
            <div className="gm-kv-item">
              <div className="label">Gross</div>
              <div className="value">{money(data.gross, currency)}</div>
            </div>
            <div className="gm-kv-item">
              <div className="label">Commission</div>
              <div className="value">{money(data.commission, currency)}</div>
            </div>
            <div className="gm-kv-item">
              <div className="label">Refunds</div>
              <div className="value">{money(data.refunds, currency)}</div>
            </div>
            <div className="gm-kv-item">
              <div className="label">Net</div>
              <div className="value">{money(data.net, currency)}</div>
            </div>
            <div className="gm-kv-item">
              <div className="label">Paid out</div>
              <div className="value">{money(data.paidOut, currency)}</div>
            </div>
            <div className="gm-kv-item">
              <div className="label">Net owed</div>
              <div className="value accent">{money(data.netOwed, currency)}</div>
            </div>
          </div>
          {data.entries.length === 0 ? (
            <EmptyState>No settlement entries yet.</EmptyState>
          ) : (
            <div className="gm-table-wrap">
              <table className="gm-table">
                <thead>
                  <tr>
                    <th>Order</th>
                    <th>Type</th>
                    <th className="num">Amount</th>
                    <th className="num">GST</th>
                    <th className="num">Commission</th>
                    <th>When</th>
                  </tr>
                </thead>
                <tbody>
                  {data.entries.map((e, i) => (
                    <tr key={`${e.orderId}-${i}`}>
                      <td>
                        <span className="gm-code">{e.orderId.slice(0, 8)}</span>
                      </td>
                      <td>
                        <StatusBadge status={e.entryType} />
                      </td>
                      <td className="num">{money(e.amount, e.currency)}</td>
                      <td className="num">{money(e.gst, e.currency)}</td>
                      <td className="num">{money(e.commission, e.currency)}</td>
                      <td>{fmtDate(e.createdAt)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </>
      )}
    </section>
  );
}

function PayoutsPanel() {
  const [payouts, setPayouts] = useState<Payout[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadErr, setLoadErr] = useState('');

  async function load() {
    setLoading(true);
    setLoadErr('');
    try {
      setPayouts(await getPayouts());
    } catch (err) {
      setLoadErr((err as Error).message);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void load();
  }, []);

  return (
    <section className="gm-glass gm-panel">
      <div className="gm-panel-head">
        <div>
          <h2>Payouts</h2>
          <p>Transfers from the platform to your account.</p>
        </div>
        <button className="gm-btn gm-btn-ghost gm-btn-sm" type="button" onClick={() => void load()}>
          Refresh
        </button>
      </div>
      {loading ? (
        <Loading label="Loading payouts…" />
      ) : loadErr ? (
        <ErrorState message={loadErr} onRetry={() => void load()} />
      ) : payouts.length === 0 ? (
        <EmptyState>No payouts recorded yet.</EmptyState>
      ) : (
        <div className="gm-table-wrap">
          <table className="gm-table">
            <thead>
              <tr>
                <th className="num">Amount</th>
                <th>Period</th>
                <th>Status</th>
                <th>Reason</th>
                <th>Paid at</th>
              </tr>
            </thead>
            <tbody>
              {payouts.map((p, i) => (
                <tr key={i}>
                  <td className="num">{money(p.amount, p.currency)}</td>
                  <td>
                    {p.periodStart || p.periodEnd
                      ? `${fmtDate(p.periodStart)} → ${fmtDate(p.periodEnd)}`
                      : '—'}
                  </td>
                  <td>
                    <StatusBadge status={p.status} />
                  </td>
                  <td>{p.reason ?? '—'}</td>
                  <td>{fmtDate(p.paidAt)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}
