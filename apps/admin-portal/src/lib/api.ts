// Minimal typed client for the auth API (see packages/api-contract for the generated client).
import { getAccess, getRefresh, setTokens, clearTokens } from '../auth';

const API = (import.meta.env.VITE_API_BASE_URL as string) ?? 'http://localhost:8080';

// Silent token refresh: the access token is short-lived (15 min). On a 401/403 we rotate it once
// using the stored refresh token and retry, so the session survives expiry without re-login.
// Concurrent callers share a single in-flight refresh.
let refreshing: Promise<string | null> | null = null;
function refreshAccess(): Promise<string | null> {
  if (refreshing) return refreshing;
  const rt = getRefresh();
  if (!rt) return Promise.resolve(null);
  refreshing = (async () => {
    try {
      const res = await fetch(`${API}/api/v1/auth/refresh`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ refreshToken: rt }),
      });
      if (!res.ok) {
        clearTokens();
        return null;
      }
      const auth = (await res.json()) as AuthResponse;
      setTokens(auth.accessToken, auth.refreshToken);
      return auth.accessToken;
    } catch {
      return null;
    } finally {
      refreshing = null;
    }
  })();
  return refreshing;
}

export type AuthResponse = {
  accessToken: string;
  refreshToken: string;
  userId: string;
  roles: string[];
};

export type Me = { userId: string; roles: string[] };

async function problem(res: Response): Promise<string> {
  const p = await res.json().catch(() => ({}));
  return (p as { detail?: string }).detail ?? `Request failed (${res.status})`;
}

export async function portalLogin(email: string, password: string): Promise<AuthResponse> {
  const res = await fetch(`${API}/api/v1/auth/portal/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  if (!res.ok) throw new Error(await problem(res));
  return res.json();
}

export async function fetchMe(accessToken: string): Promise<Me> {
  let res = await fetch(`${API}/api/v1/me`, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (res.status === 401 || res.status === 403) {
    const fresh = await refreshAccess();
    if (fresh) {
      res = await fetch(`${API}/api/v1/me`, { headers: { Authorization: `Bearer ${fresh}` } });
    }
  }
  if (!res.ok) throw new Error('unauthorized');
  return res.json();
}

export async function logout(refreshToken: string): Promise<void> {
  await fetch(`${API}/api/v1/auth/logout`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ refreshToken }),
  });
}

// ---------------------------------------------------------------------------
// Admin API client
// ---------------------------------------------------------------------------

/** Shared request helper: attaches the bearer token and surfaces problem+json detail. */
async function request<T>(
  path: string,
  init: RequestInit = {},
): Promise<T> {
  const token = getAccess();
  const headers = new Headers(init.headers);
  if (token) headers.set('Authorization', `Bearer ${token}`);
  if (init.body !== undefined && !headers.has('Content-Type')) {
    headers.set('Content-Type', 'application/json');
  }
  let res = await fetch(`${API}/api/v1${path}`, { ...init, headers });
  if ((res.status === 401 || res.status === 403) && getRefresh()) {
    const fresh = await refreshAccess();
    if (fresh) {
      headers.set('Authorization', `Bearer ${fresh}`);
      res = await fetch(`${API}/api/v1${path}`, { ...init, headers });
    }
  }
  if (!res.ok) throw new Error(await problem(res));
  if (res.status === 204) return undefined as T;
  const text = await res.text();
  if (!text) return undefined as T;
  return JSON.parse(text) as T;
}

function get<T>(path: string): Promise<T> {
  return request<T>(path, { method: 'GET' });
}
function post<T>(path: string, body?: unknown): Promise<T> {
  return request<T>(path, {
    method: 'POST',
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

function qs(params: Record<string, string | number | undefined>): string {
  const sp = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) {
    if (v !== undefined && v !== '') sp.set(k, String(v));
  }
  const s = sp.toString();
  return s ? `?${s}` : '';
}

// ---- Shops -----------------------------------------------------------------

export type AdminShop = {
  id: string;
  name: string;
  status: string;
  is_open: boolean;
  address: string | null;
  owner_email: string | null;
  created_at: string;
};

export type ShopStatusResult = { shopId: string; status: string };

export function listAdminShops(): Promise<AdminShop[]> {
  return get<AdminShop[]>('/admin/shops');
}
export function approveShop(id: string): Promise<ShopStatusResult> {
  return post<ShopStatusResult>(`/admin/shops/${encodeURIComponent(id)}/approve`);
}
export function rejectShop(id: string): Promise<ShopStatusResult> {
  return post<ShopStatusResult>(`/admin/shops/${encodeURIComponent(id)}/reject`);
}

// ---- Merge queue -----------------------------------------------------------

export type MergeCandidate = {
  candidate_id: string;
  similarity: number;
  store_product_id: string;
  raw_brand: string | null;
  raw_name: string | null;
  raw_size: string | null;
  shop_name: string | null;
  canonical_id: string;
  canonical_brand: string | null;
  canonical_name: string | null;
  canonical_size: string | null;
};

export function listMergeQueue(): Promise<MergeCandidate[]> {
  return get<MergeCandidate[]>('/admin/merge-queue');
}
export function confirmMerge(candidateId: string): Promise<void> {
  return post<void>(`/admin/merge-queue/${encodeURIComponent(candidateId)}/confirm`);
}

// ---- NGOs ------------------------------------------------------------------

export type Ngo = {
  ngoId: string;
  name: string;
  contactEmail: string;
  status: string;
  approvedAt: string | null;
};

export type CreateNgoInput = { name: string; contactEmail: string; lat: number; lng: number };
export type CreateNgoResult = { ngoId: string; status: string };
export type AddManagerInput = { email: string; password: string; displayName: string };
export type AddManagerResult = { userId: string; ngoId: string };

export function listNgos(): Promise<Ngo[]> {
  return get<Ngo[]>('/admin/ngos');
}
export function createNgo(input: CreateNgoInput): Promise<CreateNgoResult> {
  return post<CreateNgoResult>('/admin/ngos', input);
}
export function approveNgo(id: string): Promise<void> {
  return post<void>(`/admin/ngos/${encodeURIComponent(id)}/approve`);
}
export function suspendNgo(id: string): Promise<void> {
  return post<void>(`/admin/ngos/${encodeURIComponent(id)}/suspend`);
}
export function addNgoManager(id: string, input: AddManagerInput): Promise<AddManagerResult> {
  return post<AddManagerResult>(`/admin/ngos/${encodeURIComponent(id)}/managers`, input);
}

// ---- Donations -------------------------------------------------------------

export type AdminDonation = {
  donationId: string;
  store: string | null;
  productRef: string | null;
  quantity: number;
  unit: string | null;
  status: string;
  claimedBy: string | null;
  collectedBy: string | null;
};

export type DonationMetrics = { collectedCount: number; totalQuantityRescued: number };

export function listAdminDonations(): Promise<AdminDonation[]> {
  return get<AdminDonation[]>('/admin/donations');
}
export function donationMetrics(): Promise<DonationMetrics> {
  return get<DonationMetrics>('/admin/donations/metrics');
}

// ---- Finance: settlement reconciliation / payouts / disputes ---------------

export type PerShopReconciliation = {
  shopId: string;
  shopName: string;
  gross: number;
  commission: number;
  refunds: number;
  net: number;
  paidOut: number;
  netOwed: number;
  variance: number;
  flagged: boolean;
};

export type Reconciliation = {
  totalGross: number;
  totalCommission: number;
  totalRefunds: number;
  totalNetOwed: number;
  totalPaidOut: number;
  perShop: PerShopReconciliation[];
};

export type RecordPayoutInput = {
  amount: number;
  currency: string;
  reference: string;
  note: string;
};
export type RecordPayoutResult = { payoutId: string; status: string; netOwed: number };

export type Dispute = {
  disputeId: string;
  orderId: string;
  shop: string | null;
  amount: number;
  currency: string;
  status: string;
  evidenceDue: string | null;
};

export function reconciliation(asOf?: string): Promise<Reconciliation> {
  return get<Reconciliation>(`/admin/settlement/reconciliation${qs({ asOf })}`);
}
export function recordPayout(shopId: string, input: RecordPayoutInput): Promise<RecordPayoutResult> {
  return post<RecordPayoutResult>(`/admin/shops/${encodeURIComponent(shopId)}/payouts`, input);
}
export function listDisputes(): Promise<Dispute[]> {
  return get<Dispute[]>('/admin/disputes');
}

// ---- Audit -----------------------------------------------------------------

export type AuditEntry = {
  id: string;
  actorId: string | null;
  action: string;
  targetType: string | null;
  targetId: string | null;
  outcome: string;
  sourceIp: string | null;
  createdAt: string;
};

export type AuditFilter = { actor?: string; action?: string; limit?: number };

export function listAudit(filter: AuditFilter = {}): Promise<AuditEntry[]> {
  return get<AuditEntry[]>(`/admin/audit${qs({ actor: filter.actor, action: filter.action, limit: filter.limit })}`);
}
