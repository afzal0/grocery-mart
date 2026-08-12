import { useState } from 'react';
import { portalLogin, type Me } from '../lib/api';
import { setTokens } from '../auth';
import { Icon } from './Icon';

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
    <main className="gm-auth">
      <form className="gm-auth-card" onSubmit={submit}>
        <span className="gm-brand-mark" style={{ marginBottom: 'var(--gm-s4)' }}>
          <Icon name="store" size={16} />
        </span>
        <h1>Shop Portal</h1>
        <p>Sign in to manage your store, catalog and orders.</p>

        {/* Visible labels, not placeholder-only: a placeholder disappears the moment you type,
            leaving no way to check which field is which. */}
        <div className="gm-field">
          <label htmlFor="email">Email</label>
          <input
            id="email" className="gm-input" type="email" autoComplete="username"
            value={email} onChange={(e) => setEmail(e.target.value)} required
          />
        </div>
        <div className="gm-field">
          <label htmlFor="password">Password</label>
          <input
            id="password" className="gm-input" type="password" autoComplete="current-password"
            value={password} onChange={(e) => setPassword(e.target.value)} required
          />
        </div>

        {error && <div className="gm-flash danger" role="alert">{error}</div>}

        <button className="gm-btn" type="submit" disabled={busy} style={{ width: '100%' }}>
          {busy ? 'Signing in…' : 'Sign in'}
        </button>
        <div className="gm-auth-foot">Grocery-Mart · Vendor tools</div>
      </form>
    </main>
  );
}
