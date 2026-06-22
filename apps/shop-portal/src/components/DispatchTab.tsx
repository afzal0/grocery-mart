import { useEffect, useState } from 'react';
import {
  getDispatch,
  createDriver,
  createSlot,
  assignDriver,
  type DispatchOrder,
} from '../lib/api';
import { Loading, ErrorState, EmptyState, StatusBadge } from './ui';
import { money, fmtDate } from '../lib/format';

export function DispatchTab() {
  const [orders, setOrders] = useState<DispatchOrder[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadErr, setLoadErr] = useState('');
  // Driver IDs created this session, surfaced so the owner can copy them into assign.
  const [knownDrivers, setKnownDrivers] = useState<string[]>([]);

  async function load() {
    setLoading(true);
    setLoadErr('');
    try {
      setOrders(await getDispatch());
    } catch (err) {
      setLoadErr((err as Error).message);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void load();
  }, []);

  // Seed the assign dropdown from drivers already on dispatch rows plus any created here.
  const driverOptions = Array.from(
    new Set([
      ...knownDrivers,
      ...orders.map((o) => o.driverId).filter((d): d is string => Boolean(d)),
    ]),
  );

  return (
    <div className="gm-section-grid">
      <DispatchQueuePanel
        orders={orders}
        loading={loading}
        loadErr={loadErr}
        driverOptions={driverOptions}
        onReload={() => void load()}
      />
      <div className="gm-section-grid cols-2">
        <AddDriverPanel onCreated={(id) => setKnownDrivers((d) => [...d, id])} />
        <CreateSlotPanel />
      </div>
    </div>
  );
}

function DispatchQueuePanel({
  orders,
  loading,
  loadErr,
  driverOptions,
  onReload,
}: {
  orders: DispatchOrder[];
  loading: boolean;
  loadErr: string;
  driverOptions: string[];
  onReload: () => void;
}) {
  return (
    <section className="gm-glass gm-panel">
      <div className="gm-panel-head">
        <div>
          <h2>Dispatch queue</h2>
          <p>Assign a driver to ready orders. Timing shows immediate vs scheduled slots.</p>
        </div>
        <button className="gm-btn gm-btn-ghost gm-btn-sm" type="button" onClick={onReload}>
          Refresh
        </button>
      </div>
      {loading ? (
        <Loading label="Loading dispatch…" />
      ) : loadErr ? (
        <ErrorState message={loadErr} onRetry={onReload} />
      ) : orders.length === 0 ? (
        <EmptyState>No orders awaiting dispatch.</EmptyState>
      ) : (
        <div className="gm-table-wrap">
          <table className="gm-table">
            <thead>
              <tr>
                <th>Order</th>
                <th>State</th>
                <th>Timing</th>
                <th>Destination</th>
                <th className="num">Total</th>
                <th>Slot start</th>
                <th>Driver</th>
                <th>Assign</th>
              </tr>
            </thead>
            <tbody>
              {orders.map((o) => (
                <DispatchRow
                  key={o.orderId}
                  order={o}
                  driverOptions={driverOptions}
                  onAssigned={onReload}
                />
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}

function DispatchRow({
  order,
  driverOptions,
  onAssigned,
}: {
  order: DispatchOrder;
  driverOptions: string[];
  onAssigned: () => void;
}) {
  const [driverId, setDriverId] = useState(order.driverId ?? '');
  const [manual, setManual] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  async function assign() {
    const id = (driverId === '__manual__' ? manual : driverId).trim();
    if (!id) {
      setError('Pick or paste a driver id.');
      return;
    }
    setBusy(true);
    setError('');
    try {
      await assignDriver(order.orderId, id);
      onAssigned();
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <tr>
      <td>
        <span className="gm-code">{order.orderId.slice(0, 8)}</span>
        {error && <div className="gm-error">{error}</div>}
      </td>
      <td>
        <StatusBadge status={order.state} />
      </td>
      <td>{order.timing}</td>
      <td>{order.destination}</td>
      <td className="num">{money(order.grandTotal, order.currency)}</td>
      <td>{fmtDate(order.slotStart)}</td>
      <td>{order.driverId ? <span className="gm-code">{order.driverId.slice(0, 8)}</span> : '—'}</td>
      <td>
        <div style={{ display: 'flex', gap: '0.4rem', flexWrap: 'wrap', alignItems: 'center' }}>
          <select
            className="gm-inline-input"
            style={{ width: 140 }}
            value={driverId}
            onChange={(e) => setDriverId(e.target.value)}
            aria-label="driver"
          >
            <option value="">Select driver…</option>
            {driverOptions.map((d) => (
              <option key={d} value={d}>
                {d.slice(0, 8)}
              </option>
            ))}
            <option value="__manual__">Paste id…</option>
          </select>
          {driverId === '__manual__' && (
            <input
              className="gm-inline-input"
              style={{ width: 160 }}
              value={manual}
              onChange={(e) => setManual(e.target.value)}
              placeholder="driver id"
              aria-label="driver id"
            />
          )}
          <button className="gm-btn gm-btn-sm" type="button" onClick={() => void assign()} disabled={busy}>
            {busy ? 'Assigning…' : 'Assign'}
          </button>
        </div>
      </td>
    </tr>
  );
}

function AddDriverPanel({ onCreated }: { onCreated: (driverId: string) => void }) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [displayName, setDisplayName] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [newId, setNewId] = useState('');

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError('');
    setNewId('');
    try {
      const r = await createDriver(email.trim(), password, displayName.trim());
      setNewId(r.driverId);
      onCreated(r.driverId);
      setEmail('');
      setPassword('');
      setDisplayName('');
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="gm-glass gm-panel">
      <div className="gm-panel-head">
        <div>
          <h2>Add driver</h2>
          <p>Creates a driver account they can log into via the driver app.</p>
        </div>
      </div>
      <form onSubmit={submit}>
        <div className="gm-field">
          <label htmlFor="ad-name">Display name</label>
          <input
            id="ad-name"
            className="gm-input"
            value={displayName}
            onChange={(e) => setDisplayName(e.target.value)}
            placeholder="Ravi Kumar"
            required
          />
        </div>
        <div className="gm-field">
          <label htmlFor="ad-email">Email</label>
          <input
            id="ad-email"
            className="gm-input"
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="ravi@grocery-mart.dev"
            required
          />
        </div>
        <div className="gm-field">
          <label htmlFor="ad-pass">Password</label>
          <input
            id="ad-pass"
            className="gm-input"
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            placeholder="At least 8 characters"
            required
          />
        </div>
        {error && <div className="gm-error">{error}</div>}
        {newId && (
          <div className="gm-toast">
            Driver created · <span className="gm-code">{newId}</span> (now selectable in Assign)
          </div>
        )}
        <button className="gm-btn" type="submit" disabled={busy || !email.trim() || !password}>
          {busy ? 'Creating…' : 'Add driver'}
        </button>
      </form>
    </section>
  );
}

function CreateSlotPanel() {
  const [windowStart, setWindowStart] = useState('');
  const [windowEnd, setWindowEnd] = useState('');
  const [capacity, setCapacity] = useState('10');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [newSlot, setNewSlot] = useState('');

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError('');
    setNewSlot('');
    try {
      // datetime-local yields "YYYY-MM-DDTHH:mm"; promote to a full ISO instant.
      const startIso = new Date(windowStart).toISOString();
      const endIso = new Date(windowEnd).toISOString();
      const r = await createSlot(startIso, endIso, Number(capacity));
      setNewSlot(r.slotId);
      setWindowStart('');
      setWindowEnd('');
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setBusy(false);
    }
  }

  const valid = windowStart && windowEnd && Number(capacity) > 0;

  return (
    <section className="gm-glass gm-panel">
      <div className="gm-panel-head">
        <div>
          <h2>Create delivery slot</h2>
          <p>Opens a scheduled delivery window customers can book.</p>
        </div>
      </div>
      <form onSubmit={submit}>
        <div className="gm-field">
          <label htmlFor="cs-start">Window start</label>
          <input
            id="cs-start"
            className="gm-input"
            type="datetime-local"
            value={windowStart}
            onChange={(e) => setWindowStart(e.target.value)}
            required
          />
        </div>
        <div className="gm-field">
          <label htmlFor="cs-end">Window end</label>
          <input
            id="cs-end"
            className="gm-input"
            type="datetime-local"
            value={windowEnd}
            onChange={(e) => setWindowEnd(e.target.value)}
            required
          />
        </div>
        <div className="gm-field">
          <label htmlFor="cs-cap">Capacity</label>
          <input
            id="cs-cap"
            className="gm-input"
            type="number"
            min="1"
            step="1"
            value={capacity}
            onChange={(e) => setCapacity(e.target.value)}
            required
          />
        </div>
        {error && <div className="gm-error">{error}</div>}
        {newSlot && (
          <div className="gm-toast">
            Slot created · <span className="gm-code">{newSlot}</span>
          </div>
        )}
        <button className="gm-btn" type="submit" disabled={busy || !valid}>
          {busy ? 'Creating…' : 'Create slot'}
        </button>
      </form>
    </section>
  );
}
