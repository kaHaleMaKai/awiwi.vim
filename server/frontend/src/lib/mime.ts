// Client-side MIME guess from a filename, for the "File info" cards on
// binary/image asset views (DocPayload carries no MIME field). Mirrors
// Python's `mimetypes.guess_type` closely enough for display purposes: a
// small extension table, with compression suffixes (.gz/.bz2/.xz) stripped
// before matching so e.g. "backup.tar.gz" resolves off ".tar" like the
// stdlib does, not a hardcoded (and wrong) "application/gzip".
const TYPES: Record<string, string> = {
  ".tar": "application/x-tar",
  ".zip": "application/zip",
  ".pdf": "application/pdf",
  ".json": "application/json",
  ".txt": "text/plain",
  ".md": "text/markdown",
  ".csv": "text/csv",
  ".html": "text/html",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".svg": "image/svg+xml",
  ".webp": "image/webp",
  ".mp3": "audio/mpeg",
  ".mp4": "video/mp4",
};

const COMPRESSION_SUFFIXES: Record<string, string> = {
  ".gz": "gzip",
  ".bz2": "bzip2",
  ".xz": "xz",
};

function ext(name: string): string {
  const i = name.lastIndexOf(".");
  return i <= 0 ? "" : name.slice(i).toLowerCase();
}

export function guessMimeType(filename: string): string | null {
  let name = filename;
  let suffix = ext(name);
  let encoding: string | null = null;
  if (suffix in COMPRESSION_SUFFIXES) {
    encoding = COMPRESSION_SUFFIXES[suffix];
    name = name.slice(0, -suffix.length);
    suffix = ext(name);
  }
  const type = TYPES[suffix];
  if (!type) return encoding ? `application/${encoding}` : null;
  return type;
}
