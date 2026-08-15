import { ICON_PATHS, type IconName } from '../../../../packages/design-tokens/icon-paths';

/**
 * Renders one of the shared icons. Geometry is single-sourced in the design-tokens package;
 * only this React binding is per-portal (that package sits outside node_modules, so it cannot
 * import React itself).
 *
 * Decorative by default. When an icon is a control's ONLY content, put an aria-label on the
 * control — the icon itself is hidden from screen readers.
 */
export function Icon({ name, size = 20 }: { name: IconName; size?: number }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 20 20"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.5}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
      style={{ flex: 'none' }}
      dangerouslySetInnerHTML={{ __html: ICON_PATHS[name] }}
    />
  );
}
