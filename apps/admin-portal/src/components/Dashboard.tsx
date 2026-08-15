import { useState } from 'react';
import { clearTokens, getRefresh } from '../auth';
import { logout as apiLogout, type Me } from '../lib/api';
import { ShopsTab } from './tabs/ShopsTab';
import { MergeQueueTab } from './tabs/MergeQueueTab';
import { NgosTab } from './tabs/NgosTab';
import { DonationsTab } from './tabs/DonationsTab';
import { FinanceTab } from './tabs/FinanceTab';
import { AuditTab } from './tabs/AuditTab';
import { Icon } from './Icon';
import type { IconName } from '../../../../packages/design-tokens/icon-paths';

type TabKey = 'shops' | 'merge' | 'ngos' | 'donations' | 'finance' | 'audit';

const TABS: { key: TabKey; label: string; icon: IconName }[] = [
  { key: 'shops', label: 'Shops', icon: 'store' },
  { key: 'merge', label: 'Merge queue', icon: 'merge' },
  { key: 'ngos', label: 'NGOs', icon: 'users' },
  { key: 'donations', label: 'Donations', icon: 'heart' },
  { key: 'finance', label: 'Finance', icon: 'chart' },
  { key: 'audit', label: 'Audit', icon: 'shield' },
];

export function Dashboard({ user, onLogout }: { user: Me; onLogout: () => void }) {
  const [tab, setTab] = useState<TabKey>('shops');
  const [signingOut, setSigningOut] = useState(false);

  async function doLogout() {
    setSigningOut(true);
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
            <span className="gm-brand-mark"><Icon name="shield" size={16} /></span>
            Grocery-Mart <span className="gm-brand-sub">Admin</span>
          </h1>
          <div className="gm-whoami">
            <span className="gm-pill">
              <span className="gm-dot online" /> {user.roles.join(', ') || '(no roles)'}
            </span>
            <button type="button" className="gm-btn-ghost gm-btn-sm" onClick={doLogout} disabled={signingOut}>
              <Icon name="logout" size={16} /> {signingOut ? 'Signing out…' : 'Sign out'}
            </button>
          </div>
        </div>
      </header>

      <div className="gm-main">
        <nav className="gm-tabs" role="tablist" aria-label="Admin sections">
          {TABS.map((t) => (
            <button
              key={t.key}
              type="button"
              role="tab"
              id={`tab-${t.key}`}
              aria-selected={tab === t.key}
              aria-controls={`panel-${t.key}`}
              className="gm-tab"
              onClick={() => setTab(t.key)}
            >
              <Icon name={t.icon} size={16} /> {t.label}
            </button>
          ))}
        </nav>

        <main
          id={`panel-${tab}`}
          role="tabpanel"
          aria-labelledby={`tab-${tab}`}
          style={{ marginTop: 'var(--gm-s4)' }}
        >
          {tab === 'shops' && <ShopsTab />}
          {tab === 'merge' && <MergeQueueTab />}
          {tab === 'ngos' && <NgosTab />}
          {tab === 'donations' && <DonationsTab />}
          {tab === 'finance' && <FinanceTab />}
          {tab === 'audit' && <AuditTab />}
        </main>
      </div>
    </div>
  );
}
