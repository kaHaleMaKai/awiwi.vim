// Client-side language guessing for syntax highlighting.
//
// Hand-mirrored from the server's `mdrender.guess_language`
// (handovers/server-rewrite/T23.3-mdrender.md). Both sides MUST agree, so
// keep `EXT_LANG_MAP`, the dockerfile-by-name rule, the vim-modeline sniff,
// and the `pgsql -> sql` alias in lockstep with `server/src/awiwi/mdrender.py`
// if either grows. Returns a Shiki-style language id, or `null` when nothing
// matches (an expected, non-error outcome).

/** Extension (lowercase, no dot) -> Shiki language id. Mirrors
 * `_EXT_LANG_MAP` in mdrender.py verbatim. */
export const EXT_LANG_MAP: Record<string, string> = {
  py: "python",
  sh: "bash",
  bash: "bash",
  zsh: "bash",
  lua: "lua",
  vim: "vim",
  js: "javascript",
  mjs: "javascript",
  cjs: "javascript",
  jsx: "jsx",
  ts: "typescript",
  tsx: "tsx",
  json: "json",
  yaml: "yaml",
  yml: "yaml",
  toml: "toml",
  md: "markdown",
  markdown: "markdown",
  sql: "sql",
  html: "html",
  htm: "html",
  css: "css",
  c: "c",
  h: "c",
  cpp: "cpp",
  cc: "cpp",
  cxx: "cpp",
  hpp: "cpp",
  rs: "rust",
  go: "go",
  xml: "xml",
  ini: "ini",
  cfg: "ini",
  conf: "ini",
};

/** Modeline-name aliases. Mirrors `LEXER_MAP` in mdrender.py. */
const LEXER_MAP: Record<string, string> = { pgsql: "sql" };

// vim-modeline sniff, e.g. "-- vim: ft=pgsql." -> "pgsql". Mirrors
// `_MODELINE_RE` in mdrender.py (non-greedy, needs a trailing space or dot).
const MODELINE_RE = /vim: ft=(\S+?)([\s.])/;

/** Sniff a `vim: ft=<lang>` modeline out of `text`; `null` if none. Alias
 * resolution is the caller's job (as in the server's `_modeline_language`). */
export function modelineLanguage(text: string): string | null {
  const m = MODELINE_RE.exec(text);
  return m ? m[1] : null;
}

function basename(path: string): string {
  const i = path.lastIndexOf("/");
  return i === -1 ? path : path.slice(i + 1);
}

/** Python `Path.suffix` semantics: the part after the last dot, but only when
 * that dot isn't the first character (so ".bashrc"/"Dockerfile" -> ""). */
function extension(name: string): string {
  const i = name.lastIndexOf(".");
  return i > 0 ? name.slice(i + 1) : "";
}

/** Best-effort Shiki language id for `path` (+ optional file `text`).
 * Precedence mirrors the server: a `vim: ft=` modeline wins over the
 * filename; `Dockerfile`-style names are recognized by prefix; otherwise the
 * lowercase extension is looked up in `EXT_LANG_MAP`. `null` if nothing hits. */
export function guessLanguage(path: string, text?: string | null): string | null {
  if (text != null) {
    const modeline = modelineLanguage(text);
    if (modeline != null) {
      return (LEXER_MAP[modeline] ?? modeline).toLowerCase();
    }
  }
  const name = basename(path).toLowerCase();
  if (name.startsWith("dockerfile")) return "dockerfile";
  const ext = extension(name).toLowerCase();
  return EXT_LANG_MAP[ext] ?? null;
}
