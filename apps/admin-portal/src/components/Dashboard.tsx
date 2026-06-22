import { useState } from 'react';
import { clearTokens, getRefresh } from '../auth';
import { logout as apiLogout, type Me } from '../lib/api';
import { ShopsTab } from './tabs/ShopsTab';
import { MergeQueueTab } from './tabs/MergeQueueTab';
import { NgosTab } from './tabs/NgosTab';
import { DonationsTab } from './tabs/DonationsTab';
import { FinanceTab } from './tabs/FinanceTab';
import { AuditTab } from './tabs/AuditTab';

type TabKey = 'shops' | 'merge' | 'ngos' | 'donations' | 'finance' | 'audit';

const TABS: { key: TabKey; label: string }[] = [
  { key: 'shops', label: 'Shops' },
  { key: 'merge', label: 'Merge queue' },
  { key: 'ngos', label: 'NGOs' },
  { key: 'donations', label: 'Donations' },
  { key: 'finance', label: 'Finance' },
  { key: 'audit', label: 'Audit' },
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
        <div className="gm-brand">
          <span className="gm-dot online" />
          Grocery-Mart <span className="gm-gradient-text">Admin</span>
        </div>
        <div className="gm-topbar-right">
          <div className="gm-whoami">
            <div>{user.roles.join(', ') || '(no roles)'}</div>
            <div className="gm-mono">{user.userId}</div>
          </div>
          <button type="button" className="gm-btn gm-btn-ghost gm-btn-sm" onClick={doLogout} disabled={signingOut}>
            {signingOut ? 'Signing out…' : 'Sign out'}
          </button>
        </div>
      </header>

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
            {t.label}
          </button>
        ))}
      </nav>

      <main className="gm-main" id={`panel-${tab}`} role="tabpanel" aria-labelledby={`tab-${tab}`}>
        {tab === 'shops' && <ShopsTab />}
        {tab === 'merge' && <MergeQueueTab />}
        {tab === 'ngos' && <NgosTab />}
        {tab === 'donations' && <DonationsTab />}
        {tab === 'finance' && <FinanceTab />}
        {tab === 'audit' && <AuditTab />}
      </main>
    </div>
  );
}
