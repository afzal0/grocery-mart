import { useState } from 'react';
import {
  addNgoManager,
  approveNgo,
  createNgo,
  listNgos,
  suspendNgo,
  type Ngo,
} from '../../lib/api';
import { useAsync } from '../../lib/useAsync';
import { Loading, ErrorState, EmptyState, StatusBadge, dateTime } from '../ui';

function statusLower(s: string): string {
  return s.toLowerCase();
}

export function NgosTab() {
  const { data, loading, error, reload } = useAsync<Ngo[]>(listNgos);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [flash, setFlash] = useState<{ kind: 'ok' | 'bad'; text: string } | null>(null);

  // create form
  const [name, setName] = useState('');
  const [contactEmail, setContactEmail] = useState('');
  const [lat, setLat] = useState('-33.8688');
  const [lng, setLng] = useState('151.2093');
  const [creating, setCreating] = useState(false);

  // add-manager form (per selected ngo)
  const [mgrFor, setMgrFor] = useState<string | null>(null);
  const [mgrEmail, setMgrEmail] = useState('');
  const [mgrPassword, setMgrPassword] = useState('');
  const [mgrName, setMgrName] = useState('');
  const [mgrBusy, setMgrBusy] = useState(false);

  async function submitCreate(e: React.FormEvent) {
    e.preventDefault();
    setCreating(true);
    setFlash(null);
    try {
      const res = await createNgo({
        name: name.trim(),
        contactEmail: contactEmail.trim(),
        lat: Number(lat),
        lng: Number(lng),
      });
      setFlash({ kind: 'ok', text: `Created NGO "${name}" (${res.status}).` });
      setName('');
      setContactEmail('');
      reload();
    } catch (err) {
      setFlash({ kind: 'bad', text: err instanceof Error ? err.message : String(err) });
    } finally {
      setCreating(false);
    }
  }

  async function lifecycle(ngo: Ngo, kind: 'approve' | 'suspend') {
    setBusyId(ngo.ngoId);
    setFlash(null);
    try {
      if (kind === 'approve') await approveNgo(ngo.ngoId);
      else await suspendNgo(ngo.ngoId);
      setFlash({ kind: 'ok', text: `${ngo.name} ${kind === 'approve' ? 'approved' : 'suspended'}.` });
      reload();
    } catch (err) {
      setFlash({ kind: 'bad', text: err instanceof Error ? err.message : String(err) });
    } finally {
      setBusyId(null);
    }
  }

  async function submitManager(e: React.FormEvent, ngo: Ngo) {
    e.preventDefault();
    setMgrBusy(true);
    setFlash(null);
    try {
      await addNgoManager(ngo.ngoId, {
        email: mgrEmail.trim(),
        password: mgrPassword,
        displayName: mgrName.trim(),
      });
      setFlash({ kind: 'ok', text: `Manager ${mgrEmail} added to ${ngo.name}.` });
      setMgrEmail('');
      setMgrPassword('');
      setMgrName('');
      setMgrFor(null);
    } catch (err) {
      setFlash({ kind: 'bad', text: err instanceof Error ? err.message : String(err) });
    } finally {
      setMgrBusy(false);
    }
  }

  return (
    <section className="gm-glass gm-panel">
      <div className="gm-panel-head">
        <div>
          <h2>NGOs</h2>
          <p>Onboard food-rescue partners, govern their status, and grant manager access.</p>
        </div>
        <button type="button" className="gm-btn gm-btn-ghost gm-btn-sm" onClick={reload} disabled={loading}>
          Refresh
        </button>
      </div>

      {flash && <div className={`gm-flash ${flash.kind}`}>{flash.text}</div>}

      <form className="gm-inline-form" onSubmit={submitCreate} style={{ marginBottom: '1.2rem' }}>
        <div className="gm-field grow">
          <label htmlFor="ngo-name">Name</label>
          <input id="ngo-name" className="gm-input" value={name} onChange={(e) => setName(e.target.value)} required />
        </div>
        <div className="gm-field grow">
          <label htmlFor="ngo-email">Contact email</label>
          <input id="ngo-email" type="email" className="gm-input" value={contactEmail} onChange={(e) => setContactEmail(e.target.value)} required />
        </div>
        <div className="gm-field">
          <label htmlFor="ngo-lat">Lat</label>
          <input id="ngo-lat" className="gm-input" style={{ width: '7rem' }} value={lat} onChange={(e) => setLat(e.target.value)} required />
        </div>
        <div className="gm-field">
          <label htmlFor="ngo-lng">Lng</label>
          <input id="ngo-lng" className="gm-input" style={{ width: '7rem' }} value={lng} onChange={(e) => setLng(e.target.value)} required />
        </div>
        <button type="submit" className="gm-btn gm-btn-sm" disabled={creating}>
          {creating ? 'Creating…' : 'Add NGO'}
        </button>
      </form>

      {loading && <Loading label="Loading NGOs…" />}
      {error && !loading && <ErrorState message={error} onRetry={reload} />}
      {!loading && !error && data && data.length === 0 && (
        <EmptyState title="No NGOs yet" hint="Create your first food-rescue partner above." />
      )}

      {!loading && !error && data && data.length > 0 && (
        <div className="gm-table-wrap">
          <table className="gm-table">
            <thead>
              <tr>
                <th>Name</th>
                <th>Contact</th>
                <th>Status</th>
                <th>Approved</th>
                <th style={{ textAlign: 'right' }}>Actions</th>
              </tr>
            </thead>
            <tbody>
              {data.map((ngo) => {
                const s = statusLower(ngo.status);
                return (
                  <tr key={ngo.ngoId}>
                    <td>{ngo.name}</td>
                    <td className="muted">{ngo.contactEmail}</td>
                    <td><StatusBadge status={ngo.status} /></td>
                    <td className="muted">{dateTime(ngo.approvedAt)}</td>
                    <td>
                      <div className="gm-row-actions">
                        {s !== 'approved' && s !== 'active' && (
                          <button
                            type="button"
                            className="gm-btn gm-btn-sm"
                            onClick={() => lifecycle(ngo, 'approve')}
                            disabled={busyId === ngo.ngoId}
                          >
                            Approve
                          </button>
                        )}
                        {s !== 'suspended' && (
                          <button
                            type="button"
                            className="gm-btn gm-btn-ghost gm-btn-sm"
                            onClick={() => lifecycle(ngo, 'suspend')}
                            disabled={busyId === ngo.ngoId}
                          >
                            Suspend
                          </button>
                        )}
                        <button
                          type="button"
                          className="gm-btn gm-btn-ghost gm-btn-sm"
                          onClick={() => setMgrFor(mgrFor === ngo.ngoId ? null : ngo.ngoId)}
                        >
                          {mgrFor === ngo.ngoId ? 'Close' : 'Add manager'}
                        </button>
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      {mgrFor && data && (() => {
        const ngo = data.find((n) => n.ngoId === mgrFor);
        if (!ngo) return null;
        return (
          <div className="gm-glass gm-subcard">
            <h3>Add manager — {ngo.name}</h3>
            <form className="gm-inline-form" onSubmit={(e) => submitManager(e, ngo)}>
              <div className="gm-field grow">
                <label htmlFor="mgr-email">Email</label>
                <input id="mgr-email" type="email" className="gm-input" value={mgrEmail} onChange={(e) => setMgrEmail(e.target.value)} required />
              </div>
              <div className="gm-field grow">
                <label htmlFor="mgr-name">Display name</label>
                <input id="mgr-name" className="gm-input" value={mgrName} onChange={(e) => setMgrName(e.target.value)} required />
              </div>
              <div className="gm-field grow">
                <label htmlFor="mgr-pass">Password</label>
                <input id="mgr-pass" type="password" className="gm-input" value={mgrPassword} onChange={(e) => setMgrPassword(e.target.value)} required minLength={8} />
              </div>
              <button type="submit" className="gm-btn gm-btn-sm" disabled={mgrBusy}>
                {mgrBusy ? 'Adding…' : 'Create manager'}
              </button>
            </form>
          </div>
        );
      })()}
    </section>
  );
}
