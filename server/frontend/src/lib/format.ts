// Client-side date beautification, pinned byte-for-byte to the Python
// server's `templating.beautify_if_date` (ported from server.old/app.py).
// The output intentionally includes the same `<sup>` ordinal markup — and the
// same historical `11st`/`13rd` ordinal quirk (suffix keys off the last digit
// only). See format.spec.ts for the reference fixtures generated from Python.
//
// The server runs in the C locale, so weekday/month names are English; these
// tables reproduce that. Callers wanting the plain-text form strip `<sup>`.

const WDAY_SHORT = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const WDAY_LONG = [
  "Sunday",
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
];
const MON_SHORT = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
];
const MON_LONG = [
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
];

const ISO_DATE_RE = /^(\d{4})-(\d{2})-(\d{2})$/;

/** Parse a strict `YYYY-MM-DD` string into a UTC Date, or `null` if it isn't a
 * valid calendar date (mirrors `date.fromisoformat` raising for our inputs). */
function parseIsoDate(value: string): Date | null {
  const m = ISO_DATE_RE.exec(value);
  if (!m) return null;
  const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
  const dt = new Date(Date.UTC(y, mo - 1, d));
  // Reject rollovers (e.g. 2026-02-30 -> Mar 2) so they pass through unchanged.
  if (
    dt.getUTCFullYear() !== y ||
    dt.getUTCMonth() !== mo - 1 ||
    dt.getUTCDate() !== d
  ) {
    return null;
  }
  return dt;
}

const pad2 = (n: number): string => String(n).padStart(2, "0");

/** Minimal C-locale strftime for the tokens `beautify_if_date` can emit:
 * `%a %A %b %B %d %-d %m %y %Y %%`. Uses UTC getters (the Date is built in
 * UTC) so results are timezone-independent. */
function strftime(dt: Date, pattern: string): string {
  return pattern.replace(/%[-]?[aAbBdmyY%]/g, (token) => {
    switch (token) {
      case "%a":
        return WDAY_SHORT[dt.getUTCDay()];
      case "%A":
        return WDAY_LONG[dt.getUTCDay()];
      case "%b":
        return MON_SHORT[dt.getUTCMonth()];
      case "%B":
        return MON_LONG[dt.getUTCMonth()];
      case "%d":
        return pad2(dt.getUTCDate());
      case "%-d":
        return String(dt.getUTCDate());
      case "%m":
        return pad2(dt.getUTCMonth() + 1);
      case "%y":
        return pad2(dt.getUTCFullYear() % 100);
      case "%Y":
        return String(dt.getUTCFullYear());
      case "%%":
        return "%";
      default:
        return token;
    }
  });
}

/** Format an ISO date string (or a Date) as e.g. `Tue, 14<sup>th</sup>`,
 * optionally with a trailing strftime `format` suffix (the journal view uses
 * `"%B"` / `"%B %Y"`). Anything that isn't a valid date is returned unchanged
 * — matching `beautify_if_date`, so plain directory names pass through. */
export function beautifyDate(value: string | Date, format?: string | null): string {
  let dt: Date | null;
  if (typeof value === "string") {
    dt = parseIsoDate(value);
    if (dt === null) return value;
  } else {
    dt = value;
  }
  const days = pad2(dt.getUTCDate());
  let suffix: string;
  if (days.endsWith("1")) suffix = "st";
  else if (days.endsWith("2")) suffix = "nd";
  else if (days.endsWith("3")) suffix = "rd";
  else suffix = "th";
  const monthYear = format ? ` ${format}` : "";
  return strftime(dt, `%a, %-d<sup>${suffix}</sup>${monthYear}`);
}
