// Shared relative-path resolution for enhance passes that turn a raw markdown
// link/src into a home-relative repo path. The server (mdrender) emits raw,
// unresolved paths; each pass resolves them the same way: a `assets/…` path is
// already home-relative; any other relative path is resolved against the
// document's own directory. Absolute URLs (scheme, protocol-relative, or
// root-absolute like `/api/raw/…`) can't be a local doc and yield `null`.

function isAbsolute(ref: string): boolean {
  return /^[a-z][a-z0-9+.-]*:/i.test(ref) || ref.startsWith("//") || ref.startsWith("/");
}

// A leading-slash path into an awiwi home root (`/assets/…`, `/journal/…`,
// `/recipes/…`) is home-root-relative, not web-absolute — notes and the vim
// plugin write links this way. `/api/…` and everything else absolute is left
// as-is.
const HOME_ROOT = /^\/(?:assets|journal|recipes)\//;

/** Collapse `.`/`..` segments in a POSIX-style relative path. */
function normalizePosix(path: string): string {
  const out: string[] = [];
  for (const seg of path.split("/")) {
    if (seg === "" || seg === ".") continue;
    if (seg === "..") out.pop();
    else out.push(seg);
  }
  return out.join("/");
}

/** Resolve a link/src `ref` to a home-relative repo path, or `null` when it's
 * empty or absolute (and thus not a local doc). `watchPath` is the containing
 * doc's home-relative path. */
export function resolveRelpath(ref: string, watchPath: string): string | null {
  if (!ref) return null;
  if (HOME_ROOT.test(ref)) return ref.slice(1);
  if (isAbsolute(ref)) return null;
  if (ref.startsWith("assets/")) return ref;
  const dir = watchPath.includes("/") ? watchPath.slice(0, watchPath.lastIndexOf("/")) : "";
  return normalizePosix(dir ? `${dir}/${ref}` : ref);
}
