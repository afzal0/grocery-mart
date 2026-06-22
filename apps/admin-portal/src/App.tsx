import { useEffect, useState } from 'react';
import { LoginScreen } from './components/LoginScreen';
import { Dashboard } from './components/Dashboard';
import { getAccess, clearTokens } from './auth';
import { fetchMe, type Me } from './lib/api';

export default function App() {
  const [user, setUser] = useState<Me | null>(null);
  const [checking, setChecking] = useState(true);

  useEffect(() => {
    const token = getAccess();
    if (!token) {
      setChecking(false);
      return;
    }
    fetchMe(token)
      .then(setUser)
      .catch(() => clearTokens())
      .finally(() => setChecking(false));
  }, []);

  if (checking) {
    return (
      <main className="gm-landing">
        <div className="gm-glass gm-card">Loading…</div>
      </main>
    );
  }

  return user
    ? <Dashboard user={user} onLogout={() => setUser(null)} />
    : <LoginScreen onLoggedIn={setUser} />;
}
