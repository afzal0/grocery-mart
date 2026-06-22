// Token storage for the portal session.
const ACCESS = 'gm_access';
const REFRESH = 'gm_refresh';

export function setTokens(access: string, refresh: string): void {
  localStorage.setItem(ACCESS, access);
  localStorage.setItem(REFRESH, refresh);
}
export function getAccess(): string | null {
  return localStorage.getItem(ACCESS);
}
export function getRefresh(): string | null {
  return localStorage.getItem(REFRESH);
}
export function clearTokens(): void {
  localStorage.removeItem(ACCESS);
  localStorage.removeItem(REFRESH);
}
