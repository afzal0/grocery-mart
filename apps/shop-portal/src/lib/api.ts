// Minimal typed client for the auth API. (Swap for the generated @grocery-mart/api-contract
// client when the OpenAPI spec covers the auth paths — see packages/api-contract.)
import { getAccess, getRefresh, setTokens, clearTokens } from '../auth';

const API = (import.meta.env.VITE_API_BASE_URL as string) ?? 'http://localhost:8080';
const BASE = `${API}/api/v1`;

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

// ── Shared authed request helpers ────────────────────────────────────────────
// Every shop endpoint is behind the Bearer token issued at portal login; pull it
// from getAccess() so screens never have to thread the token through props.

type Json = Record<string, unknown> | unknown[];

// Silent token refresh: the access token is short-lived (15 min). On a 401/403 we rotate it once
// via the stored refresh token and retry, so the session survives expiry without a re-login.
// Concurrent callers share a single in-flight refresh.
let refreshing: Promise<string | null> | null = null;
function refreshAccess(): Promise<string | null> {
  if (refreshing) return refreshing;
  const rt = getRefresh();
  if (!rt) return Promise.resolve(null);
  refreshing = (async () => {
    try {
      const res = await fetch(`${BASE}/auth/refresh`, {
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

/** fetch with the Bearer token; on 401/403 refresh once and retry. Returns the raw Response. */
async function authedFetch(path: string, init: RequestInit = {}, extraHeaders?: Record<string, string>): Promise<Response> {
  const build = (token: string | null): RequestInit => ({
    ...init,
    headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), ...extraHeaders },
  });
  let res = await fetch(`${BASE}${path}`, build(getAccess()));
  if ((res.status === 401 || res.status === 403) && getRefresh()) {
    const fresh = await refreshAccess();
    if (fresh) res = await fetch(`${BASE}${path}`, build(fresh));
  }
  return res;
}

/** GET that parses JSON, surfacing the problem+json "detail" on failure. */
async function apiGet<T>(path: string): Promise<T> {
  const res = await authedFetch(path);
  if (!res.ok) throw new Error(await problem(res));
  return res.json() as Promise<T>;
}

/** Send a JSON body and parse the JSON response. */
async function apiSend<T>(path: string, method: string, body?: Json): Promise<T> {
  const res = await authedFetch(path, {
    method,
    body: body !== undefined ? JSON.stringify(body) : undefined,
  }, body !== undefined ? { 'Content-Type': 'application/json' } : undefined);
  if (!res.ok) throw new Error(await problem(res));
  return res.json() as Promise<T>;
}

/** Send a JSON body where the endpoint returns 204 No Content. */
async function apiSendNoContent(path: string, method: string, body?: Json): Promise<void> {
  const res = await authedFetch(path, {
    method,
    body: body !== undefined ? JSON.stringify(body) : undefined,
  }, body !== undefined ? { 'Content-Type': 'application/json' } : undefined);
  if (!res.ok) throw new Error(await problem(res));
}

// ── Auth (preserved) ─────────────────────────────────────────────────────────
export async function portalLogin(email: string, password: string): Promise<AuthResponse> {
  const res = await fetch(`${BASE}/auth/portal/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  if (!res.ok) throw new Error(await problem(res));
  return res.json();
}

export async function fetchMe(accessToken: string): Promise<Me> {
  let res = await fetch(`${BASE}/me`, { headers: { Authorization: `Bearer ${accessToken}` } });
  if (res.status === 401 || res.status === 403) {
    const fresh = await refreshAccess();
    if (fresh) res = await fetch(`${BASE}/me`, { headers: { Authorization: `Bearer ${fresh}` } });
  }
  if (!res.ok) throw new Error('unauthorized');
  return res.json();
}

export async function logout(refreshToken: string): Promise<void> {
  await fetch(`${BASE}/auth/logout`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ refreshToken }),
  });
}

// ── Shop profile ─────────────────────────────────────────────────────────────
export type Shop = {
  id: string;
  name: string;
  description: string | null;
  cuisine_tags: string[] | null;
  status: string;
};

export type CreateShopResult = { shopId: string; status: string };

export type UpdateShopBody = {
  name: string;
  cuisineTags: string[];
  description: string;
  address: string;
  lat: number;
  lng: number;
};

/**
 * GET /shops/me. Returns null when the owner has no shop yet (404 / empty body)
 * so the Profile screen can show the "Create shop" form instead of an error.
 */
export async function getMyShop(): Promise<Shop | null> {
  const res = await authedFetch('/shops/me');
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(await problem(res));
  const text = await res.text();
  if (!text) return null;
  return JSON.parse(text) as Shop;
}

export function createShop(name: string, cuisineTags: string[]): Promise<CreateShopResult> {
  return apiSend<CreateShopResult>('/shops', 'POST', { name, cuisineTags });
}

export function updateMyShop(body: UpdateShopBody): Promise<void> {
  return apiSendNoContent('/shops/me', 'PUT', body);
}

// ── Catalog ──────────────────────────────────────────────────────────────────
export type StoreProduct = {
  id: string;
  raw_brand: string | null;
  raw_name: string;
  raw_size: string | null;
  price_amount: number;
  currency: string;
  stock: number;
  match_status: string;
  canonical_product_id: string | null;
};

export type CreateStoreProductBody = {
  name: string;
  brand: string;
  size: string;
  price: number;
  currency: string;
  stock: number;
};

export type CatalogOutcome = {
  storeProductId: string;
  submittedName: string;
  masterProduct: string | null;
  matchType: string;
  standardizedAt: string;
};

export type BulkUploadResult = { created: number; failed: number };

export function getMyProducts(): Promise<StoreProduct[]> {
  return apiGet<StoreProduct[]>('/shops/me/products');
}

export function createStoreProduct(body: CreateStoreProductBody): Promise<unknown> {
  return apiSend<unknown>('/store-products', 'POST', body);
}

export function updateStoreProduct(id: string, price: number, stock: number): Promise<void> {
  return apiSendNoContent(`/store-products/${id}`, 'PUT', { price, stock });
}

/** Bulk CSV upload. The body is raw CSV ("name,brand,size,price,stock" per line). */
export async function bulkUploadProducts(csv: string): Promise<BulkUploadResult> {
  const res = await authedFetch('/store-products/bulk', { method: 'POST', body: csv }, { 'Content-Type': 'text/csv' });
  if (!res.ok) throw new Error(await problem(res));
  return res.json() as Promise<BulkUploadResult>;
}

export function getCatalogOutcomes(): Promise<CatalogOutcome[]> {
  return apiGet<CatalogOutcome[]>('/shops/me/catalog-outcomes');
}

// ── Dispatch ─────────────────────────────────────────────────────────────────
export type DispatchOrder = {
  orderId: string;
  state: string;
  timing: string;
  driverId: string | null;
  destination: string;
  grandTotal: number;
  currency: string;
  slotStart: string | null;
};

export type CreateDriverResult = { driverId: string };
export type CreateSlotResult = { slotId: string };

export function getDispatch(): Promise<DispatchOrder[]> {
  return apiGet<DispatchOrder[]>('/shops/me/dispatch');
}

export function createDriver(
  email: string,
  password: string,
  displayName: string,
): Promise<CreateDriverResult> {
  return apiSend<CreateDriverResult>('/shops/me/drivers', 'POST', { email, password, displayName });
}

export function createSlot(
  windowStart: string,
  windowEnd: string,
  capacity: number,
): Promise<CreateSlotResult> {
  return apiSend<CreateSlotResult>('/shops/me/slots', 'POST', { windowStart, windowEnd, capacity });
}

export function assignDriver(orderId: string, driverId: string): Promise<void> {
  return apiSendNoContent(`/shops/me/orders/${orderId}/assign`, 'POST', { driverId });
}

// ── Donations ────────────────────────────────────────────────────────────────
export type Donation = {
  donationId: string;
  productRef: string;
  description: string;
  quantity: number;
  unit: string;
  status: string;
};

export type CreateDonationBody = {
  productRef: string;
  description: string;
  quantity: number;
  unit: string;
};

export type CreateDonationResult = { donationId: string; status: string };

export function getMyDonations(): Promise<Donation[]> {
  return apiGet<Donation[]>('/shops/me/donations');
}

export function createDonation(body: CreateDonationBody): Promise<CreateDonationResult> {
  return apiSend<CreateDonationResult>('/donations', 'POST', body);
}

export function updateDonation(
  id: string,
  quantity: number,
  description: string,
): Promise<void> {
  return apiSendNoContent(`/donations/${id}`, 'PUT', { quantity, description });
}

// ── Settlement & payouts ─────────────────────────────────────────────────────
export type SettlementEntry = {
  orderId: string;
  entryType: string;
  amount: number;
  gst: number;
  commission: number;
  currency: string;
  createdAt: string;
};

export type Settlement = {
  entries: SettlementEntry[];
  gross: number;
  commission: number;
  refunds: number;
  net: number;
  paidOut: number;
  netOwed: number;
};

export type Payout = {
  amount: number;
  currency: string;
  periodStart: string | null;
  periodEnd: string | null;
  status: string;
  reason: string | null;
  paidAt: string | null;
};

export function getSettlement(limit = 50): Promise<Settlement> {
  return apiGet<Settlement>(`/shops/me/settlement?limit=${limit}`);
}

export function getPayouts(): Promise<Payout[]> {
  return apiGet<Payout[]>('/shops/me/payouts');
}
