// Hand-rolled runes router — no framework, matcher table + History API.
//
// Route table (order matters only for the final catch-all):
//   /                       -> home
//   /dir/*                 -> dir      (params.rest = remainder, may be "")
//   /todo                   -> todo
//   /journal/:date          -> journal (params.date)
//   /assets/:date/:file     -> asset   (params.date, params.file)
//   /recipes/*              -> recipes (params.rest, may be "")
//   /search                 -> search
//   /*                      -> notfound (catch-all)

export type RouteName =
  | "home"
  | "dir"
  | "todo"
  | "journal"
  | "asset"
  | "recipes"
  | "search"
  | "notfound";

export interface Route {
  name: RouteName;
  params: Record<string, string>;
  path: string;
}

type Matcher = (segments: string[]) => Record<string, string> | null;

const matchers: [RouteName, Matcher][] = [
  ["home", (s) => (s.length === 0 ? {} : null)],
  ["dir", (s) => (s[0] === "dir" ? { rest: s.slice(1).join("/") } : null)],
  ["todo", (s) => (s.length === 1 && s[0] === "todo" ? {} : null)],
  ["journal", (s) => (s.length === 2 && s[0] === "journal" ? { date: s[1] } : null)],
  [
    "asset",
    (s) => (s.length === 3 && s[0] === "assets" ? { date: s[1], file: s[2] } : null),
  ],
  ["recipes", (s) => (s[0] === "recipes" ? { rest: s.slice(1).join("/") } : null)],
  ["search", (s) => (s.length === 1 && s[0] === "search" ? {} : null)],
];

/** Pure path -> Route resolution, exercised directly in tests. */
export function matchRoute(pathname: string): Route {
  const segments = pathname.split("/").filter(Boolean);
  for (const [name, test] of matchers) {
    const params = test(segments);
    if (params) return { name, params, path: pathname };
  }
  return { name: "notfound", params: {}, path: pathname };
}

function isModifiedOrNewTab(e: MouseEvent): boolean {
  return e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey;
}

class Router {
  current = $state<Route>(
    matchRoute(typeof location !== "undefined" ? location.pathname : "/"),
  );
  #started = false;

  navigate(path: string, { replace = false }: { replace?: boolean } = {}): void {
    if (typeof history !== "undefined") {
      if (replace) history.replaceState(null, "", path);
      else history.pushState(null, "", path);
    }
    this.current = matchRoute(path.split("?")[0].split("#")[0]);
  }

  /** Wire popstate + global same-origin <a> click interception. Idempotent. */
  start(): void {
    if (this.#started || typeof window === "undefined") return;
    this.#started = true;

    window.addEventListener("popstate", () => {
      this.current = matchRoute(location.pathname);
    });

    document.addEventListener("click", (e: MouseEvent) => {
      if (isModifiedOrNewTab(e)) return;
      const anchor = (e.target as HTMLElement).closest?.("a");
      if (!anchor || !anchor.href || anchor.hasAttribute("download")) return;
      if (anchor.target && anchor.target !== "_self") return;
      const url = new URL(anchor.href, location.href);
      if (url.origin !== location.origin) return;
      e.preventDefault();
      this.navigate(url.pathname + url.search + url.hash);
    });
  }
}

export const router = new Router();
