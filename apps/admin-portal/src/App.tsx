import { useEffect, useState } from 'react';

const API = (import.meta.env.VITE_API_BASE_URL as string) ?? 'http://localhost:8080';
type Health = 'pending' | 'online' | 'offline';

export default function App() {
  const [health, setHealth] = useState<Health>('pending');
  const [service, setService] = useState('');

  useEffect(() => {
    fetch(`${API}/api/v1/ping`)
      .then((r) => (r.ok ? r.json() : Promise.reject()))
      .then((d: { service: string }) => { setHealth('online'); setService(d.service); })
      .catch(() => setHealth('offline'));
  }, []);

  return (
    <main className="gm-landing">
      <section className="gm-glass gm-card">
        <span className="gm-pill">
          <span className={`gm-dot ${health}`} />
          backend {health}{service && ` · ${service}`}
        </span>
        <h1>
          Grocery-Mart <span className="gm-gradient-text">Admin</span>
        </h1>
        <p>Approve stores &amp; NGOs, govern the catalog merge queue, and oversee the platform.</p>
        <button className="gm-btn" type="button">Open console</button>
        <div className="gm-foot">Liquid Glass · React + Vite · Epic 1 walking skeleton</div>
      </section>
    </main>
  );
}
