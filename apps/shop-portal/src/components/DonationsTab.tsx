import { useEffect, useState } from 'react';
import {
  getMyDonations,
  createDonation,
  updateDonation,
  type Donation,
} from '../lib/api';
import { Loading, ErrorState, EmptyState, StatusBadge } from './ui';

export function DonationsTab() {
  const [donations, setDonations] = useState<Donation[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadErr, setLoadErr] = useState('');

  async function load() {
    setLoading(true);
    setLoadErr('');
    try {
      setDonations(await getMyDonations());
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
    <div className="gm-section-grid">
      <CreateDonationPanel onCreated={() => void load()} />
      <section className="gm-glass gm-panel">
        <div className="gm-panel-head">
          <div>
            <h2>Donations</h2>
            <p>Surplus stock offered to partner NGOs. Edit quantity/description until claimed.</p>
          </div>
          <button className="gm-btn gm-btn-ghost gm-btn-sm" type="button" onClick={() => void load()}>
            Refresh
          </button>
        </div>
        {loading ? (
          <Loading label="Loading donations…" />
        ) : loadErr ? (
          <ErrorState message={loadErr} onRetry={() => void load()} />
        ) : donations.length === 0 ? (
          <EmptyState>No donations yet. Offer surplus stock above.</EmptyState>
        ) : (
          <ul className="gm-list">
            {donations.map((d) => (
              <DonationItem key={d.donationId} donation={d} onSaved={() => void load()} />
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}

function CreateDonationPanel({ onCreated }: { onCreated: () => void }) {
  const [productRef, setProductRef] = useState('');
  const [description, setDescription] = useState('');
  const [quantity, setQuantity] = useState('');
  const [unit, setUnit] = useState('kg');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [ok, setOk] = useState('');

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError('');
    setOk('');
    try {
      await createDonation({
        productRef: productRef.trim(),
        description: description.trim(),
        quantity: Number(quantity),
        unit: unit.trim() || 'unit',
      });
      setOk('Donation created.');
      setProductRef('');
      setDescription('');
      setQuantity('');
      onCreated();
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setBusy(false);
    }
  }

  const valid = productRef.trim() && quantity !== '' && Number(quantity) > 0;

  return (
    <section className="gm-glass gm-panel">
      <div className="gm-panel-head">
        <div>
          <h2>Offer a donation</h2>
          <p>List surplus stock for NGO collection.</p>
        </div>
      </div>
      <form onSubmit={submit}>
        <div className="gm-field">
          <label htmlFor="cd-ref">Product reference</label>
          <input
            id="cd-ref"
            className="gm-input"
            value={productRef}
            onChange={(e) => setProductRef(e.target.value)}
            placeholder="Paneer 200g (near best-before)"
            required
          />
        </div>
        <div className="gm-field">
          <label htmlFor="cd-desc">Description</label>
          <input
            id="cd-desc"
            className="gm-input"
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="Sealed, chilled, best before tomorrow"
          />
        </div>
        <div className="gm-field-row">
          <div className="gm-field">
            <label htmlFor="cd-qty">Quantity</label>
            <input
              id="cd-qty"
              className="gm-input"
              type="number"
              min="0"
              step="any"
              value={quantity}
              onChange={(e) => setQuantity(e.target.value)}
              placeholder="12"
              required
            />
          </div>
          <div className="gm-field">
            <label htmlFor="cd-unit">Unit</label>
            <input
              id="cd-unit"
              className="gm-input"
              value={unit}
              onChange={(e) => setUnit(e.target.value)}
              placeholder="kg / packs / units"
            />
          </div>
        </div>
        {error && <div className="gm-error">{error}</div>}
        {ok && <div className="gm-ok">{ok}</div>}
        <button className="gm-btn" type="submit" disabled={busy || !valid}>
          {busy ? 'Creating…' : 'Create donation'}
        </button>
      </form>
    </section>
  );
}

function DonationItem({ donation, onSaved }: { donation: Donation; onSaved: () => void }) {
  const [editing, setEditing] = useState(false);
  const [quantity, setQuantity] = useState(String(donation.quantity));
  const [description, setDescription] = useState(donation.description ?? '');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  async function save() {
    setBusy(true);
    setError('');
    try {
      await updateDonation(donation.donationId, Number(quantity), description.trim());
      setEditing(false);
      onSaved();
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <li className="gm-list-item">
      <div className="gm-li-main">
        <span className="title">{donation.productRef}</span>
        {editing ? (
          <div className="gm-field-row" style={{ marginTop: '0.5rem' }}>
            <input
              className="gm-inline-input"
              type="number"
              min="0"
              step="any"
              value={quantity}
              onChange={(e) => setQuantity(e.target.value)}
              aria-label="quantity"
            />
            <input
              className="gm-input"
              style={{ flex: '1 1 200px', width: 'auto' }}
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Description"
              aria-label="description"
            />
          </div>
        ) : (
          <span className="sub">
            {donation.quantity} {donation.unit}
            {donation.description ? ` · ${donation.description}` : ''}
          </span>
        )}
        {error && <div className="gm-error">{error}</div>}
      </div>
      <div className="gm-li-side">
        <StatusBadge status={donation.status} />
        {editing ? (
          <>
            <button className="gm-btn gm-btn-sm" type="button" onClick={() => void save()} disabled={busy}>
              {busy ? 'Saving…' : 'Save'}
            </button>
            <button
              className="gm-btn gm-btn-ghost gm-btn-sm"
              type="button"
              onClick={() => {
                setEditing(false);
                setQuantity(String(donation.quantity));
                setDescription(donation.description ?? '');
                setError('');
              }}
              disabled={busy}
            >
              Cancel
            </button>
          </>
        ) : (
          <button className="gm-btn gm-btn-ghost gm-btn-sm" type="button" onClick={() => setEditing(true)}>
            Edit
          </button>
        )}
      </div>
    </li>
  );
}
