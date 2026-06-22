import { clearTokens, getRefresh } from '../auth';
import { logout as apiLogout, type Me } from '../lib/api';

export function Dashboard({ user, onLogout }: { user: Me; onLogout: () => void }) {
  async function doLogout() {
    const refresh = getRefresh();
    if (refresh) await apiLogout(refresh).catch(() => {});
    clearTokens();
    onLogout();
  }

  return (
    <main className="gm-landing">
      <section className="gm-glass gm-card">
        <span className="gm-pill"><span className="gm-dot online" /> signed in</span>
        <h1>
          Welcome to the <span className="gm-gradient-text">Shop Portal</span>
        </h1>
        <p>
          Roles: <strong>{user.roles.join(', ') || '(none)'}</strong>
          <br />
          <small style={{ color: 'var(--gm-text-dim)' }}>{user.userId}</small>
        </p>
        <button className="gm-btn" type="button" onClick={doLogout}>Sign out</button>
        <div className="gm-foot">Catalog, pricing, orders &amp; drivers land in Epic 3+.</div>
      </section>
    </main>
  );
}
