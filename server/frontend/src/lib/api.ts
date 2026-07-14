// Typed fetchers for the frozen /api contract (see
// handovers/server-rewrite/T23.2-api-routes.md — this file must stay in
// lockstep with that document, not with the backend source directly).

export type DocKind = "markdown" | "text" | "image" | "drawio" | "binary";
export type DocType = "journal" | "asset" | "recipe" | "other";

export interface BreadcrumbPayload {
  name: string;
  target: string;
}

export interface NavPayload {
  prev: string | null;
  next: string | null;
}

export interface DocPayload {
  kind: DocKind;
  doc_type: DocType;
  html: string | null;
  toc: string | null;
  text: string | null;
  language: string | null;
  raw_url: string | null;
  watch_path: string;
  breadcrumbs: BreadcrumbPayload[];
  journal_date: string | null;
  nav: NavPayload | null;
  // NB: Python's mtime_ns is a nanosecond epoch int wider than JS's safe
  // integer range: use it only for equality checks, never arithmetic.
  mtime_ns: number;
  is_secret: boolean;
}

export interface DirEntry {
  name: string;
  relpath: string;
  is_dir: boolean;
  doc_type: DocType;
}

export interface DirPayload {
  breadcrumbs: BreadcrumbPayload[];
  entries: DirEntry[];
}

export interface SearchHit {
  target: string;
  name: string;
  line: number;
  col: number;
  type: string;
  text: string;
}

export interface MetaPayload {
  today: string;
  home: string;
  version: string;
}

export interface CheckboxPatchRequest {
  path: string;
  line_nr: number;
  checked: boolean;
  line_hash: string;
}

export interface CheckboxPatchResponse {
  success: true;
  line_hash: string;
  mtime_ns: number;
}

export type SearchMode = "fixed" | "regex";
export type SearchScope = "journal" | "assets" | "recipes";

export interface SearchParams {
  q: string;
  mode?: SearchMode;
  scope?: SearchScope[];
}

/** Thrown for any non-2xx response; `.detail` mirrors the body's `detail` field
 * (a string for most routes, or FastAPI's validation-error array for 422s). */
export class ApiError extends Error {
  status: number;
  detail: unknown;

  constructor(status: number, detail: unknown) {
    super(typeof detail === "string" ? detail : `API error ${status}`);
    this.status = status;
    this.detail = detail;
  }
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(path, init);
  if (!res.ok) {
    let detail: unknown = res.statusText;
    try {
      detail = (await res.json()).detail;
    } catch {
      // body wasn't JSON (or was empty) — fall back to statusText above.
    }
    throw new ApiError(res.status, detail);
  }
  return res.json() as Promise<T>;
}

/** Encode each path segment but preserve literal `/`s (server routes are
 * FastAPI `{path:path}` converters, which accept raw slashes). */
function encodeRelpath(path: string): string {
  return path.split("/").map(encodeURIComponent).join("/");
}

export function getMeta(): Promise<MetaPayload> {
  return request("/api/meta");
}

export function getJournal(dateStr: string): Promise<DocPayload> {
  return request(`/api/journal/${encodeURIComponent(dateStr)}`);
}

export function getTodo(): Promise<DocPayload> {
  return request("/api/todo");
}

export function getDoc(path: string): Promise<DocPayload> {
  return request(`/api/doc/${encodeRelpath(path)}`);
}

export function getDir(path = ""): Promise<DirPayload> {
  return request(path ? `/api/dir/${encodeRelpath(path)}` : "/api/dir");
}

/** Builds the `/api/raw/...` URL DocPayload.raw_url already points at —
 * exposed here too so callers that only have a relpath (not a fetched
 * DocPayload) can still build it. Not a fetcher: bind straight to <img
 * src>/<a href>, the bytes aren't JSON. */
export function rawUrl(path: string, opts: { download?: boolean } = {}): string {
  const qs = opts.download ? "?download=1" : "";
  return `/api/raw/${encodeRelpath(path)}${qs}`;
}

export function patchCheckbox(body: CheckboxPatchRequest): Promise<CheckboxPatchResponse> {
  return request("/api/checkbox", {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

export function search({ q, mode, scope }: SearchParams): Promise<SearchHit[]> {
  const params = new URLSearchParams({ q });
  if (mode) params.set("mode", mode);
  if (scope && scope.length) params.set("scope", scope.join(","));
  return request(`/api/search?${params.toString()}`);
}
