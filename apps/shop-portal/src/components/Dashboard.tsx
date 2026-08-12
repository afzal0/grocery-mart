import { useState } from 'react';
import { clearTokens, getRefresh } from '../auth';
import { logout as apiLogout, type Me } from '../lib/api';
import { ProfileTab } from './ProfileTab';
import { CatalogTab } from './CatalogTab';
import { DispatchTab } from './DispatchTab';
import { DonationsTab } from './DonationsTab';
import { SettlementTab } from './SettlementTab';
import { Icon } from './Icon';
import type { IconName } from '../../../../packages/design-tokens/icon-paths';

type TabKey = 'profile' | 'catalog' | 'dispatch' | 'donations' | 'settlement';

const TABS: { key: TabKey; label: string; icon: IconName }[] = [
  { key: 'profile', label: 'Profile', icon: 'store' },
  { key: 'catalog', label: 'Catalog', icon: 'box' },
  { key: 'dispatch', label: 'Dispatch', icon: 'truck' },
  { key: 'donations', label: 'Donations', icon: 'heart' },
  { key: 'settlement', label: 'Settlement', icon: 'wallet' },
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
    <div className="gm-app">
      <header className="gm-topbar">
        <div className="gm-topbar-inner">
          <h1 className="gm-brand">
            <span className="gm-brand-mark"><Icon name="store" size={16} /></span>
            Grocery-Mart <span className="gm-brand-sub">Shop</span>
          </h1>
          <div className="gm-whoami">
            <span className="gm-pill">
              <span className="gm-dot online" /> {user.roles.join(', ') || 'Signed in'}
            </span>
            <button className="gm-btn-ghost gm-btn-sm" type="button" onClick={doLogout}>
              <Icon name="logout" size={16} /> Sign out
            </button>
          </div>
        </div>
      </header>

      <main className="gm-main">
        <nav className="gm-tabs" role="tablist" aria-label="Sections">
          {TABS.map(({ key, label, icon }) => (
            <button
              key={key}
              type="button"
              role="tab"
              aria-selected={tab === key}
              className={`gm-tab${tab === key ? ' active' : ''}`}
              onClick={() => setTab(key)}
            >
              <Icon name={icon} size={16} /> {label}
            </button>
          ))}
        </nav>

        <div role="tabpanel" style={{ marginTop: 'var(--gm-s4)' }}>
          {tab === 'profile' && <ProfileTab />}
          {tab === 'catalog' && <CatalogTab />}
          {tab === 'dispatch' && <DispatchTab />}
          {tab === 'donations' && <DonationsTab />}
          {tab === 'settlement' && <SettlementTab />}
        </div>
      </main>
    </div>
  );
}
