import { useEffect, useState } from 'react';
import {
  getMyShop,
  createShop,
  updateMyShop,
  type Shop,
} from '../lib/api';
import { Loading, ErrorState, StatusBadge } from './ui';

export function ProfileTab() {
  const [shop, setShop] = useState<Shop | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadErr, setLoadErr] = useState('');

  async function load() {
    setLoading(true);
    setLoadErr('');
    try {
      setShop(await getMyShop());
    } catch (err) {
      setLoadErr((err as Error).message);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void load();
  }, []);

  if (loading) {
    return (
      <section className="gm-glass gm-panel">
        <Loading label="Loading your shop…" />
      </section>
    );
  }
  if (loadErr) {
    return (
      <section className="gm-glass gm-panel">
        <ErrorState message={loadErr} onRetry={() => void load()} />
      </section>
    );
  }

  return shop ? (
    <EditShopForm shop={shop} onSaved={() => void load()} />
  ) : (
    <CreateShopForm onCreated={() => void load()} />
  );
}

function CreateShopForm({ onCreated }: { onCreated: () => void }) {
  const [name, setName] = useState('');
  const [tags, setTags] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError('');
    try {
      await createShop(
        name.trim(),
        tags
          .split(',')
          .map((t) => t.trim())
          .filter(Boolean),
      );
      onCreated();
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
          <h2>Create your shop</h2>
          <p>You don't have a shop yet. Set one up to start listing products.</p>
        </div>
      </div>
      <form onSubmit={submit} style={{ maxWidth: 480 }}>
        <div className="gm-field">
          <label htmlFor="cs-name">Shop name</label>
          <input
            id="cs-name"
            className="gm-input"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Patel Cash & Carry"
            required
          />
        </div>
        <div className="gm-field">
          <label htmlFor="cs-tags">Cuisine tags</label>
          <input
            id="cs-tags"
            className="gm-input"
            value={tags}
            onChange={(e) => setTags(e.target.value)}
            placeholder="indian, grocery, halal"
          />
          <span className="gm-hint">Comma-separated.</span>
        </div>
        {error && <div className="gm-error">{error}</div>}
        <button className="gm-btn" type="submit" disabled={busy || !name.trim()}>
          {busy ? 'Creating…' : 'Create shop'}
        </button>
      </form>
    </section>
  );
}

function EditShopForm({ shop, onSaved }: { shop: Shop; onSaved: () => void }) {
  const [name, setName] = useState(shop.name ?? '');
  const [tags, setTags] = useState((shop.cuisine_tags ?? []).join(', '));
  const [description, setDescription] = useState(shop.description ?? '');
  const [address, setAddress] = useState('');
  const [lat, setLat] = useState('-33.8688');
  const [lng, setLng] = useState('151.2093');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [saved, setSaved] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError('');
    setSaved(false);
    try {
      await updateMyShop({
        name: name.trim(),
        cuisineTags: tags
          .split(',')
          .map((t) => t.trim())
          .filter(Boolean),
        description: description.trim(),
        address: address.trim(),
        lat: Number(lat),
        lng: Number(lng),
      });
      setSaved(true);
      onSaved();
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
          <h2>Shop profile</h2>
          <p>
            <span className="gm-code">{shop.id}</span>
          </p>
        </div>
        <StatusBadge status={shop.status} />
      </div>
      <form onSubmit={submit} style={{ maxWidth: 560 }}>
        <div className="gm-field">
          <label htmlFor="es-name">Shop name</label>
          <input
            id="es-name"
            className="gm-input"
            value={name}
            onChange={(e) => setName(e.target.value)}
            required
          />
        </div>
        <div className="gm-field">
          <label htmlFor="es-tags">Cuisine tags</label>
          <input
            id="es-tags"
            className="gm-input"
            value={tags}
            onChange={(e) => setTags(e.target.value)}
            placeholder="indian, grocery"
          />
          <span className="gm-hint">Comma-separated.</span>
        </div>
        <div className="gm-field">
          <label htmlFor="es-desc">Description</label>
          <textarea
            id="es-desc"
            className="gm-input"
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="Family-run South-Asian grocery."
          />
        </div>
        <div className="gm-field">
          <label htmlFor="es-addr">Address</label>
          <input
            id="es-addr"
            className="gm-input"
            value={address}
            onChange={(e) => setAddress(e.target.value)}
            placeholder="123 George St, Sydney NSW"
          />
        </div>
        <div className="gm-field-row">
          <div className="gm-field">
            <label htmlFor="es-lat">Latitude</label>
            <input
              id="es-lat"
              className="gm-input"
              type="number"
              step="any"
              value={lat}
              onChange={(e) => setLat(e.target.value)}
            />
          </div>
          <div className="gm-field">
            <label htmlFor="es-lng">Longitude</label>
            <input
              id="es-lng"
              className="gm-input"
              type="number"
              step="any"
              value={lng}
              onChange={(e) => setLng(e.target.value)}
            />
          </div>
        </div>
        {error && <div className="gm-error">{error}</div>}
        {saved && <div className="gm-ok">Saved.</div>}
        <button className="gm-btn" type="submit" disabled={busy || !name.trim()}>
          {busy ? 'Saving…' : 'Save changes'}
        </button>
      </form>
    </section>
  );
}
