import { useState } from 'react';
import { portalLogin, type Me } from '../lib/api';
import { setTokens } from '../auth';

export function LoginScreen({ onLoggedIn }: { onLoggedIn: (user: Me) => void }) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError('');
    try {
      const auth = await portalLogin(email, password);
      setTokens(auth.accessToken, auth.refreshToken);
      onLoggedIn({ userId: auth.userId, roles: auth.roles });
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="gm-landing">
      <form className="gm-glass gm-card gm-form" onSubmit={submit}>
        <h1>
          Grocery-Mart <span className="gm-gradient-text">Shop Portal</span>
        </h1>
        <p>Sign in to manage your store, catalog, and orders.</p>
        <input className="gm-input" type="email" placeholder="Email" autoComplete="username"
          value={email} onChange={(e) => setEmail(e.target.value)} required />
        <input className="gm-input" type="password" placeholder="Password" autoComplete="current-password"
          value={password} onChange={(e) => setPassword(e.target.value)} required />
        {error && <div className="gm-error">{error}</div>}
        <button className="gm-btn" type="submit" disabled={busy}>{busy ? 'Signing in…' : 'Sign in'}</button>
        <div className="gm-foot">Liquid Glass · React + Vite · Epic 2 auth</div>
      </form>
    </main>
  );
}
