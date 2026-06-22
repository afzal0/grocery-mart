import { useEffect, useState } from 'react';
import {
  getMyProducts,
  createStoreProduct,
  updateStoreProduct,
  bulkUploadProducts,
  getCatalogOutcomes,
  type StoreProduct,
  type CatalogOutcome,
  type BulkUploadResult,
} from '../lib/api';
import { Loading, ErrorState, EmptyState, StatusBadge } from './ui';

export function CatalogTab() {
  const [products, setProducts] = useState<StoreProduct[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadErr, setLoadErr] = useState('');

  async function load() {
    setLoading(true);
    setLoadErr('');
    try {
      setProducts(await getMyProducts());
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
      <ProductsPanel
        products={products}
        loading={loading}
        loadErr={loadErr}
        onReload={() => void load()}
      />
      <div className="gm-section-grid cols-2">
        <AddProductPanel onAdded={() => void load()} />
        <BulkUploadPanel onUploaded={() => void load()} />
      </div>
      <CatalogOutcomesPanel />
    </div>
  );
}

function ProductsPanel({
  products,
  loading,
  loadErr,
  onReload,
}: {
  products: StoreProduct[];
  loading: boolean;
  loadErr: string;
  onReload: () => void;
}) {
  return (
    <section className="gm-glass gm-panel">
      <div className="gm-panel-head">
        <div>
          <h2>Products</h2>
          <p>Edit price &amp; stock inline. Match status reflects canonical standardization.</p>
        </div>
        <button className="gm-btn gm-btn-ghost gm-btn-sm" type="button" onClick={onReload}>
          Refresh
        </button>
      </div>
      {loading ? (
        <Loading label="Loading products…" />
      ) : loadErr ? (
        <ErrorState message={loadErr} onRetry={onReload} />
      ) : products.length === 0 ? (
        <EmptyState>No products yet. Add one below or bulk-upload a CSV.</EmptyState>
      ) : (
        <div className="gm-table-wrap">
          <table className="gm-table">
            <thead>
              <tr>
                <th>Product</th>
                <th>Brand</th>
                <th>Size</th>
                <th className="num">Price</th>
                <th className="num">Stock</th>
                <th>Match</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {products.map((p) => (
                <ProductRow key={p.id} product={p} onSaved={onReload} />
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}

function ProductRow({ product, onSaved }: { product: StoreProduct; onSaved: () => void }) {
  const [price, setPrice] = useState(String(product.price_amount));
  const [stock, setStock] = useState(String(product.stock));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const dirty = Number(price) !== product.price_amount || Number(stock) !== product.stock;

  async function save() {
    setBusy(true);
    setError('');
    try {
      await updateStoreProduct(product.id, Number(price), Number(stock));
      onSaved();
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <tr>
      <td>
        {product.raw_name}
        {error && <div className="gm-error">{error}</div>}
      </td>
      <td>{product.raw_brand ?? '—'}</td>
      <td>{product.raw_size ?? '—'}</td>
      <td className="num">
        <input
          className="gm-inline-input"
          type="number"
          step="0.01"
          min="0"
          value={price}
          onChange={(e) => setPrice(e.target.value)}
          aria-label="price"
        />
      </td>
      <td className="num">
        <input
          className="gm-inline-input"
          type="number"
          step="1"
          min="0"
          value={stock}
          onChange={(e) => setStock(e.target.value)}
          aria-label="stock"
        />
      </td>
      <td>
        <StatusBadge status={product.match_status} />
      </td>
      <td className="num">
        <button
          className="gm-btn gm-btn-sm"
          type="button"
          onClick={() => void save()}
          disabled={busy || !dirty}
        >
          {busy ? 'Saving…' : 'Save'}
        </button>
      </td>
    </tr>
  );
}

function AddProductPanel({ onAdded }: { onAdded: () => void }) {
  const [name, setName] = useState('');
  const [brand, setBrand] = useState('');
  const [size, setSize] = useState('');
  const [price, setPrice] = useState('');
  const [currency, setCurrency] = useState('AUD');
  const [stock, setStock] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [ok, setOk] = useState('');

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError('');
    setOk('');
    try {
      await createStoreProduct({
        name: name.trim(),
        brand: brand.trim(),
        size: size.trim(),
        price: Number(price),
        currency: currency.trim() || 'AUD',
        stock: Number(stock),
      });
      setOk(`Added "${name.trim()}".`);
      setName('');
      setBrand('');
      setSize('');
      setPrice('');
      setStock('');
      onAdded();
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setBusy(false);
    }
  }

  const valid = name.trim() && price !== '' && stock !== '';

  return (
    <section className="gm-glass gm-panel">
      <div className="gm-panel-head">
        <div>
          <h2>Add product</h2>
          <p>Goes to the canonical matcher automatically.</p>
        </div>
      </div>
      <form onSubmit={submit}>
        <div className="gm-field">
          <label htmlFor="ap-name">Name</label>
          <input
            id="ap-name"
            className="gm-input"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Aashirvaad Atta"
            required
          />
        </div>
        <div className="gm-field-row">
          <div className="gm-field">
            <label htmlFor="ap-brand">Brand</label>
            <input
              id="ap-brand"
              className="gm-input"
              value={brand}
              onChange={(e) => setBrand(e.target.value)}
              placeholder="Aashirvaad"
            />
          </div>
          <div className="gm-field">
            <label htmlFor="ap-size">Size</label>
            <input
              id="ap-size"
              className="gm-input"
              value={size}
              onChange={(e) => setSize(e.target.value)}
              placeholder="5kg"
            />
          </div>
        </div>
        <div className="gm-field-row">
          <div className="gm-field">
            <label htmlFor="ap-price">Price</label>
            <input
              id="ap-price"
              className="gm-input"
              type="number"
              step="0.01"
              min="0"
              value={price}
              onChange={(e) => setPrice(e.target.value)}
              placeholder="14.99"
              required
            />
          </div>
          <div className="gm-field">
            <label htmlFor="ap-currency">Currency</label>
            <input
              id="ap-currency"
              className="gm-input"
              value={currency}
              onChange={(e) => setCurrency(e.target.value)}
            />
          </div>
          <div className="gm-field">
            <label htmlFor="ap-stock">Stock</label>
            <input
              id="ap-stock"
              className="gm-input"
              type="number"
              step="1"
              min="0"
              value={stock}
              onChange={(e) => setStock(e.target.value)}
              placeholder="40"
              required
            />
          </div>
        </div>
        {error && <div className="gm-error">{error}</div>}
        {ok && <div className="gm-ok">{ok}</div>}
        <button className="gm-btn" type="submit" disabled={busy || !valid}>
          {busy ? 'Adding…' : 'Add product'}
        </button>
      </form>
    </section>
  );
}

const SAMPLE_CSV = 'Toor Dal,Tata,1kg,4.50,80\nPaneer,Gopi,200g,5.20,30';

function BulkUploadPanel({ onUploaded }: { onUploaded: () => void }) {
  const [csv, setCsv] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [result, setResult] = useState<BulkUploadResult | null>(null);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError('');
    setResult(null);
    try {
      const r = await bulkUploadProducts(csv.trim());
      setResult(r);
      if (r.created > 0) {
        setCsv('');
        onUploaded();
      }
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
          <h2>Bulk CSV upload</h2>
          <p>One product per line: name,brand,size,price,stock</p>
        </div>
      </div>
      <form onSubmit={submit}>
        <div className="gm-field">
          <textarea
            className="gm-input"
            value={csv}
            onChange={(e) => setCsv(e.target.value)}
            placeholder={SAMPLE_CSV}
            spellCheck={false}
          />
          <span className="gm-hint">No header row. Each line is name,brand,size,price,stock.</span>
        </div>
        {error && <div className="gm-error">{error}</div>}
        {result && (
          <div className="gm-toast">
            Created {result.created}, failed {result.failed}.
          </div>
        )}
        <button className="gm-btn" type="submit" disabled={busy || !csv.trim()}>
          {busy ? 'Uploading…' : 'Upload CSV'}
        </button>
      </form>
    </section>
  );
}

function CatalogOutcomesPanel() {
  const [outcomes, setOutcomes] = useState<CatalogOutcome[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadErr, setLoadErr] = useState('');

  async function load() {
    setLoading(true);
    setLoadErr('');
    try {
      setOutcomes(await getCatalogOutcomes());
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
          <h2>Catalog match outcomes</h2>
          <p>How each submitted product was standardized against the master catalog.</p>
        </div>
        <button className="gm-btn gm-btn-ghost gm-btn-sm" type="button" onClick={() => void load()}>
          Refresh
        </button>
      </div>
      {loading ? (
        <Loading label="Loading outcomes…" />
      ) : loadErr ? (
        <ErrorState message={loadErr} onRetry={() => void load()} />
      ) : outcomes.length === 0 ? (
        <EmptyState>No match outcomes yet.</EmptyState>
      ) : (
        <div className="gm-table-wrap">
          <table className="gm-table">
            <thead>
              <tr>
                <th>Submitted</th>
                <th>Master product</th>
                <th>Match type</th>
                <th>Standardized</th>
              </tr>
            </thead>
            <tbody>
              {outcomes.map((o) => (
                <tr key={o.storeProductId}>
                  <td>{o.submittedName}</td>
                  <td>{o.masterProduct ?? '—'}</td>
                  <td>
                    <StatusBadge status={o.matchType} />
                  </td>
                  <td>{new Date(o.standardizedAt).toLocaleString()}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}
