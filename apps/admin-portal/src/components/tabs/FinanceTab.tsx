import { useState } from 'react';
import {
  listDisputes,
  recordPayout,
  reconciliation,
  type Dispute,
  type PerShopReconciliation,
  type Reconciliation,
} from '../../lib/api';
import { useAsync } from '../../lib/useAsync';
import { Loading, ErrorState, EmptyState, StatusBadge, Badge, money, dateTime } from '../ui';

function PayoutForm({
  shop,
  onDone,
  onCancel,
}: {
  shop: PerShopReconciliation;
  onDone: (msg: string) => void;
  onCancel: () => void;
}) {
  const [amount, setAmount] = useState(shop.netOwed > 0 ? shop.netOwed.toFixed(2) : '');
  const [currency, setCurrency] = useState('AUD');
  const [reference, setReference] = useState('');
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setErr(null);
    try {
      const res = await recordPayout(shop.shopId, {
        amount: Number(amount),
        currency: currency.trim(),
        reference: reference.trim(),
        note: note.trim(),
      });
      onDone(`Payout ${money(Number(amount), currency)} recorded for ${shop.shopName} (${res.status}). Remaining owed: ${money(res.netOwed, currency)}.`);
    } catch (e2) {
      setErr(e2 instanceof Error ? e2.message : String(e2));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="gm-glass gm-subcard">
      <h3>Record manual payout — {shop.shopName}</h3>
      {err && <div className="gm-flash bad">{err}</div>}
      <form className="gm-inline-form" onSubmit={submit}>
        <div className="gm-field">
          <label htmlFor="po-amount">Amount</label>
          <input id="po-amount" className="gm-input" style={{ width: '8rem' }} type="number" step="0.01" min="0" value={amount} onChange={(e) => setAmount(e.target.value)} required />
        </div>
        <div className="gm-field">
          <label htmlFor="po-currency">Currency</label>
          <input id="po-currency" className="gm-input" style={{ width: '6rem' }} value={currency} onChange={(e) => setCurrency(e.target.value)} required />
        </div>
        <div className="gm-field grow">
          <label htmlFor="po-ref">Reference</label>
          <input id="po-ref" className="gm-input" value={reference} onChange={(e) => setReference(e.target.value)} required />
        </div>
        <div className="gm-field grow">
          <label htmlFor="po-note">Note</label>
          <input id="po-note" className="gm-input" value={note} onChange={(e) => setNote(e.target.value)} />
        </div>
        <button type="submit" className="gm-btn gm-btn-sm" disabled={busy}>
          {busy ? 'Recording…' : 'Record payout'}
        </button>
        <button type="button" className="gm-btn gm-btn-ghost gm-btn-sm" onClick={onCancel}>
          Cancel
        </button>
      </form>
    </div>
  );
}

export function FinanceTab() {
  const [asOf, setAsOf] = useState('');
  const [appliedAsOf, setAppliedAsOf] = useState('');
  const recon = useAsync<Reconciliation>(() => reconciliation(appliedAsOf || undefined), [appliedAsOf]);
  const disputes = useAsync<Dispute[]>(listDisputes);

  const [payoutShop, setPayoutShop] = useState<PerShopReconciliation | null>(null);
  const [flash, setFlash] = useState<{ kind: 'ok' | 'bad'; text: string } | null>(null);

  function applyDate(e: React.FormEvent) {
    e.preventDefault();
    setAppliedAsOf(asOf);
  }

  const totals = recon.data;

  return (
    <>
      <section className="gm-glass gm-panel">
        <div className="gm-panel-head">
          <div>
            <h2>Finance — settlement reconciliation</h2>
            <p>Platform gross, commission, refunds and outstanding payouts, per shop.</p>
          </div>
          <form className="gm-toolbar" onSubmit={applyDate}>
            <div className="gm-field">
              <label htmlFor="asof">As of</label>
              <input id="asof" className="gm-input" type="date" value={asOf} onChange={(e) => setAsOf(e.target.value)} />
            </div>
            <button type="submit" className="gm-btn gm-btn-sm" disabled={recon.loading}>Apply</button>
            <button
              type="button"
              className="gm-btn gm-btn-ghost gm-btn-sm"
              onClick={() => { setAsOf(''); setAppliedAsOf(''); }}
              disabled={recon.loading}
            >
              Clear
            </button>
          </form>
        </div>

        {flash && <div className={`gm-flash ${flash.kind}`}>{flash.text}</div>}

        {recon.loading && <Loading label="Loading reconciliation…" />}
        {recon.error && !recon.loading && <ErrorState message={recon.error} onRetry={recon.reload} />}

        {!recon.loading && !recon.error && totals && (
          <>
            <div className="gm-metrics">
              <div className="gm-glass gm-metric">
                <div className="label">Gross</div>
                <div className="value">{money(totals.totalGross, 'AUD')}</div>
              </div>
              <div className="gm-glass gm-metric">
                <div className="label">Commission</div>
                <div className="value">{money(totals.totalCommission, 'AUD')}</div>
              </div>
              <div className="gm-glass gm-metric">
                <div className="label">Refunds</div>
                <div className="value">{money(totals.totalRefunds, 'AUD')}</div>
              </div>
              <div className="gm-glass gm-metric">
                <div className="label">Paid out</div>
                <div className="value">{money(totals.totalPaidOut, 'AUD')}</div>
              </div>
              <div className="gm-glass gm-metric">
                <div className="label">Net owed</div>
                <div className="value accent">{money(totals.totalNetOwed, 'AUD')}</div>
              </div>
            </div>

            {totals.perShop.length === 0 ? (
              <EmptyState title="No settlement activity" hint="No shops have settlement entries for this period." />
            ) : (
              <div className="gm-table-wrap">
                <table className="gm-table">
                  <thead>
                    <tr>
                      <th>Shop</th>
                      <th style={{ textAlign: 'right' }}>Gross</th>
                      <th style={{ textAlign: 'right' }}>Commission</th>
                      <th style={{ textAlign: 'right' }}>Refunds</th>
                      <th style={{ textAlign: 'right' }}>Net</th>
                      <th style={{ textAlign: 'right' }}>Paid out</th>
                      <th style={{ textAlign: 'right' }}>Net owed</th>
                      <th style={{ textAlign: 'right' }}>Variance</th>
                      <th style={{ textAlign: 'right' }}>Action</th>
                    </tr>
                  </thead>
                  <tbody>
                    {totals.perShop.map((s) => (
                      <tr key={s.shopId}>
                        <td>
                          {s.shopName}{' '}
                          {s.flagged && <Badge tone="danger">flagged</Badge>}
                        </td>
                        <td className="num">{money(s.gross, 'AUD')}</td>
                        <td className="num">{money(s.commission, 'AUD')}</td>
                        <td className="num">{money(s.refunds, 'AUD')}</td>
                        <td className="num">{money(s.net, 'AUD')}</td>
                        <td className="num">{money(s.paidOut, 'AUD')}</td>
                        <td className="num">{money(s.netOwed, 'AUD')}</td>
                        <td className="num">
                          {s.variance !== 0 ? (
                            <Badge tone={s.flagged ? 'danger' : 'warn'}>{money(s.variance, 'AUD')}</Badge>
                          ) : (
                            <span className="muted">0.00</span>
                          )}
                        </td>
                        <td>
                          <div className="gm-row-actions">
                            <button
                              type="button"
                              className="gm-btn gm-btn-sm"
                              onClick={() => setPayoutShop(payoutShop?.shopId === s.shopId ? null : s)}
                            >
                              {payoutShop?.shopId === s.shopId ? 'Close' : 'Pay out'}
                            </button>
                          </div>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}

            {payoutShop && (
              <PayoutForm
                shop={payoutShop}
                onCancel={() => setPayoutShop(null)}
                onDone={(msg) => {
                  setFlash({ kind: 'ok', text: msg });
                  setPayoutShop(null);
                  recon.reload();
                }}
              />
            )}
          </>
        )}
      </section>

      <section className="gm-glass gm-panel">
        <div className="gm-panel-head">
          <div>
            <h2>Disputes</h2>
            <p>Open chargebacks and order disputes requiring evidence.</p>
          </div>
          <button type="button" className="gm-btn gm-btn-ghost gm-btn-sm" onClick={disputes.reload} disabled={disputes.loading}>
            Refresh
          </button>
        </div>

        {disputes.loading && <Loading label="Loading disputes…" />}
        {disputes.error && !disputes.loading && <ErrorState message={disputes.error} onRetry={disputes.reload} />}
        {!disputes.loading && !disputes.error && disputes.data && disputes.data.length === 0 && (
          <EmptyState title="No open disputes" hint="Order disputes will surface here when raised." />
        )}
        {!disputes.loading && !disputes.error && disputes.data && disputes.data.length > 0 && (
          <div className="gm-table-wrap">
            <table className="gm-table">
              <thead>
                <tr>
                  <th>Dispute</th>
                  <th>Order</th>
                  <th>Shop</th>
                  <th style={{ textAlign: 'right' }}>Amount</th>
                  <th>Status</th>
                  <th>Evidence due</th>
                </tr>
              </thead>
              <tbody>
                {disputes.data.map((d) => (
                  <tr key={d.disputeId}>
                    <td className="gm-mono">{d.disputeId}</td>
                    <td className="gm-mono">{d.orderId}</td>
                    <td>{d.shop ?? '—'}</td>
                    <td className="num">{money(d.amount, d.currency)}</td>
                    <td><StatusBadge status={d.status} /></td>
                    <td className="muted">{dateTime(d.evidenceDue)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </>
  );
}
