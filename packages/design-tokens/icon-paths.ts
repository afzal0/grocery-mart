/* Grocery-Mart — shared icon geometry.
   SF-Symbols-adjacent: 20x20 viewBox, 1.5 stroke, round caps/joins, drawn in currentColor.

   Pure path data with NO imports, deliberately: this file lives outside either portal's
   node_modules, so anything importing React here would fail to resolve. Each portal renders
   these through its own tiny <Icon> component instead, which keeps the geometry single-sourced
   while the React binding stays local. */

export type IconName =
  | 'store' | 'box' | 'truck' | 'receipt' | 'gift' | 'chart' | 'shield' | 'wallet'
  | 'pin' | 'search' | 'check' | 'x' | 'plus' | 'minus' | 'trash' | 'chevronDown'
  | 'chevronRight' | 'refresh' | 'logout' | 'alert' | 'settings' | 'users' | 'merge' | 'heart';

/** Each entry is one or more <path>/<circle> children, as raw SVG markup fragments. */
export const ICON_PATHS: Record<IconName, string> = {
  store:
    '<path d="M3 7.5 4.5 3h11L17 7.5M3 7.5h14M3 7.5v9h14v-9M3 7.5a2.2 2.2 0 0 0 4.4 0 2.2 2.2 0 0 0 4.4 0 2.2 2.2 0 0 0 4.4 0"/>',
  box:
    '<path d="M10 2.5 17 6v8l-7 3.5L3 14V6l7-3.5ZM3 6l7 3.5M17 6l-7 3.5m0 0v8"/>',
  truck:
    '<path d="M1.5 5.5h9v8h-9zM10.5 8.5h3.5l2.5 2.5v2.5h-6z"/><circle cx="5" cy="15.5" r="1.6"/><circle cx="13.5" cy="15.5" r="1.6"/>',
  receipt:
    '<path d="M4.5 2.5h11v15l-2-1.3-1.8 1.3-1.7-1.3-1.8 1.3-1.7-1.3-2 1.3zM7.5 6.5h5M7.5 10h5"/>',
  gift:
    '<path d="M2.5 8.5h15v3h-15zM4 11.5h12v6H4zM10 8.5v9M10 8.5C10 6 8.5 4 6.8 4a2 2 0 0 0 0 4.5M10 8.5c0-2.5 1.5-4.5 3.2-4.5a2 2 0 0 1 0 4.5"/>',
  chart:
    '<path d="M2.5 17h15M5 14V9M9 14V4.5M13 14v-6M17 14v-3"/>',
  shield:
    '<path d="M10 2.5 16 5v5c0 4-2.5 6.6-6 7.5C6.5 16.6 4 14 4 10V5l6-2.5ZM7.6 10l1.7 1.7 3.2-3.4"/>',
  wallet:
    '<path d="M2.5 6.5A2 2 0 0 1 4.5 4.5H15v2M2.5 6.5v9A2 2 0 0 0 4.5 17.5h12v-11h-12a2 2 0 0 1-2-2Z"/><circle cx="13" cy="12" r="1" fill="currentColor" stroke="none"/>',
  pin:
    '<path d="M10 17.5s5.5-5 5.5-9a5.5 5.5 0 1 0-11 0c0 4 5.5 9 5.5 9Z"/><circle cx="10" cy="8.5" r="2"/>',
  search:
    '<circle cx="8.8" cy="8.8" r="5.3"/><path d="m12.8 12.8 4 4"/>',
  check:
    '<path d="m4 10.5 4 4 8-9"/>',
  x:
    '<path d="m5 5 10 10M15 5 5 15"/>',
  plus:
    '<path d="M10 4v12M4 10h12"/>',
  minus:
    '<path d="M4 10h12"/>',
  trash:
    '<path d="M3.5 5.5h13M8 5.5V3.5h4v2M5.5 5.5l.8 11.5h7.4l.8-11.5M8.5 9v5M11.5 9v5"/>',
  chevronDown:
    '<path d="m5 7.5 5 5 5-5"/>',
  chevronRight:
    '<path d="m7.5 4 5 6-5 6"/>',
  refresh:
    '<path d="M17 4.5v4.5h-4.5M3 15.5V11h4.5"/><path d="M16.2 9a6.5 6.5 0 0 0-11.4-3M3.8 11a6.5 6.5 0 0 0 11.4 3"/>',
  logout:
    '<path d="M7.5 3.5h-4v13h4M13 6.5l3.5 3.5L13 13.5M16.5 10h-9"/>',
  alert:
    '<path d="M10 3 2.5 16.5h15L10 3ZM10 8v4"/><circle cx="10" cy="14.3" r=".8" fill="currentColor" stroke="none"/>',
  settings:
    '<circle cx="10" cy="10" r="2.5"/><path d="M10 2.5v2M10 15.5v2M17.5 10h-2M4.5 10h-2M15.3 4.7l-1.4 1.4M6.1 13.9l-1.4 1.4M15.3 15.3l-1.4-1.4M6.1 6.1 4.7 4.7"/>',
  users:
    '<circle cx="7.5" cy="7" r="2.8"/><path d="M2.5 16.5c0-2.8 2.2-4.5 5-4.5s5 1.7 5 4.5M13.5 5a2.8 2.8 0 0 1 0 5.4M14.5 12.4c1.8.4 3 1.9 3 4.1"/>',
  merge:
    '<path d="M6 3v4.5c0 2 1.5 3 3.5 3.5s3.5 1.5 3.5 3.5V17M14 3v4M6 17v-3"/><path d="m11 14.5 2 2.5 2-2.5"/>',
  heart:
    '<path d="M10 16.5S3 12.5 3 7.9A3.4 3.4 0 0 1 10 6a3.4 3.4 0 0 1 7 1.9c0 4.6-7 8.6-7 8.6Z"/>',
};
