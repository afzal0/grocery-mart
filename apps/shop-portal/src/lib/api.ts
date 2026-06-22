// Minimal typed client for the auth API. (Swap for the generated @grocery-mart/api-contract
// client when the OpenAPI spec covers the auth paths — see packages/api-contract.)
const API = (import.meta.env.VITE_API_BASE_URL as string) ?? 'http://localhost:8080';

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
  const res = await fetch(`${API}/api/v1/me`, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
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
