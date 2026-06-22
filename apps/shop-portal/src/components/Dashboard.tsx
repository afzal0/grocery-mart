import { useState } from 'react';
import { clearTokens, getRefresh } from '../auth';
import { logout as apiLogout, type Me } from '../lib/api';
import { ProfileTab } from './ProfileTab';
import { CatalogTab } from './CatalogTab';
import { DispatchTab } from './DispatchTab';
import { DonationsTab } from './DonationsTab';
import { SettlementTab } from './SettlementTab';

type TabKey = 'profile' | 'catalog' | 'dispatch' | 'donations' | 'settlement';

const TABS: { key: TabKey; label: string }[] = [
  { key: 'profile', label: 'Profile' },
  { key: 'catalog', label: 'Catalog' },
  { key: 'dispatch', label: 'Dispatch' },
  { key: 'donations', label: 'Donations' },
  { key: 'settlement', label: 'Settlement' },
];

export function Dashboard({ user, onLogout }: { user: Me; onLogout: () => void }) {
  const [tab, setTab] = useState<TabKey>('profile');

  async function doLogout() {
    const refresh = getRefresh();
    if (refresh) await apiLogout(refresh).catch(() => {});
    clearTokens();
    onLogout();
  }

  return (
    <div className="gm-shell">
      <header className="gm-glass gm-topbar">
        <div className="gm-who">
          <h1>
            Grocery-Mart <span className="gm-gradient-text">Shop Portal</span>
          </h1>
          <small>
            <span className="gm-pill" style={{ marginRight: '0.5rem' }}>
              <span className="gm-dot online" /> {user.roles.join(', ') || 'signed in'}
            </span>
            {user.userId}
          </small>
        </div>
        <div className="gm-topbar-actions">
          <button className="gm-btn gm-btn-ghost gm-btn-sm" type="button" onClick={doLogout}>
            Sign out
          </button>
        </div>
      </header>

      <nav className="gm-glass gm-tabs" aria-label="Sections">
        {TABS.map((t) => (
          <button
            key={t.key}
            type="button"
            className={`gm-tab${tab === t.key ? ' active' : ''}`}
            aria-current={tab === t.key ? 'page' : undefined}
            onClick={() => setTab(t.key)}
          >
            {t.label}
          </button>
        ))}
      </nav>

      <div>
        {tab === 'profile' && <ProfileTab />}
        {tab === 'catalog' && <CatalogTab />}
        {tab === 'dispatch' && <DispatchTab />}
        {tab === 'donations' && <DonationsTab />}
        {tab === 'settlement' && <SettlementTab />}
      </div>
    </div>
  );
}
