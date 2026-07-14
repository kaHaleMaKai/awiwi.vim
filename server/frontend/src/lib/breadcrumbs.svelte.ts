// Shared breadcrumb trail state, read by App.svelte's <Breadcrumbs>.
//
// Each route view fetches its own DocPayload/DirPayload and calls
// `breadcrumbs.set(payload.breadcrumbs)` once the fetch resolves, replacing
// App.svelte's placeholder. Directory payloads' breadcrumbs already include
// the directory itself (backend `include_cur_dir=True`); doc/journal
// payloads don't (`include_cur_dir=False`), so single-file pages append their
// own synthetic "current" crumb via `withCurrent`.

import type { BreadcrumbPayload } from "./api";

const DEFAULT_CRUMBS: BreadcrumbPayload[] = [{ name: "awiwi", target: "/" }];

class BreadcrumbStore {
  crumbs = $state<BreadcrumbPayload[]>(DEFAULT_CRUMBS);

  set(crumbs: BreadcrumbPayload[]): void {
    this.crumbs = crumbs;
  }

  reset(): void {
    this.crumbs = DEFAULT_CRUMBS;
  }
}

export const breadcrumbs = new BreadcrumbStore();

/** Append a synthetic "current page" crumb to a doc/journal payload's
 * breadcrumb trail (which excludes the current file per backend contract).
 * `target` is cosmetic only — <Breadcrumbs> never links the last item. */
export function withCurrent(
  base: BreadcrumbPayload[],
  name: string,
  target: string,
): BreadcrumbPayload[] {
  return [...base, { name, target }];
}

/** Best-effort crumb trail for a 404/error before any payload arrives — one
 * crumb per path segment, all pointing at `/dir/...` (the universal
 * directory-browse route; only the last crumb's target is ever unused, since
 * <Breadcrumbs> renders it as plain text). Empty path -> home only. */
export function fallbackCrumbs(path: string): BreadcrumbPayload[] {
  const parts = path.split("/").filter(Boolean);
  if (!parts.length) return DEFAULT_CRUMBS;
  return parts.map((name, i) => ({
    name,
    target: `/dir/${parts.slice(0, i + 1).join("/")}`,
  }));
}
