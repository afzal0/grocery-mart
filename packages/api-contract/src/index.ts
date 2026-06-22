// Grocery-Mart API contract — typed surface generated from openapi.yaml.
// Regenerate after spec changes:  pnpm --filter @grocery-mart/api-contract gen:ts
export type { paths, components, operations } from './gen/schema';
import type { components } from './gen/schema';

export type PingResponse = components['schemas']['PingResponse'];
export type Problem = components['schemas']['Problem'];
export type Money = components['schemas']['Money'];

export const API_BASE: string =
  (import.meta as { env?: Record<string, string> }).env?.VITE_API_BASE_URL ?? 'http://localhost:8080';
