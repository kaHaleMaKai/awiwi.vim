// Client-side date formatting for the SPA (mockups/journal.html,
// dir-journal-month.html). The server no longer beautifies dates itself
// (DocPayload/DirEntry ship plain `YYYY-MM-DD` strings — see schemas.py) so
// formatting is entirely the frontend's call. Two shapes are needed:
//   journalTitle  "Tuesday, July 14 2026"  (journal H1)
//   shortDayDate  "Mon, Jul 13"            (day-nav buttons, dir-month rows)
//
// The server runs in the C locale, so weekday/month names are English; these
// tables reproduce that.

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

/** English ordinal suffix for a day-of-month number. 11/12/13 are always
 * "th" (the historical bug here keyed off the last digit only, so it said
 * "11st"/"12nd"/"13rd" — this checks the 11-13 range first). */
export function ordinalSuffix(day: number): string {
  if (day >= 11 && day <= 13) return "th";
  switch (day % 10) {
    case 1:
      return "st";
    case 2:
      return "nd";
    case 3:
      return "rd";
    default:
      return "th";
  }
}

/** Minimal C-locale strftime for the tokens used below:
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

function toDate(value: string | Date): Date | null {
  return typeof value === "string" ? parseIsoDate(value) : value;
}

/** Journal H1 date, e.g. `Tuesday, July 14 2026`. A value that isn't a valid
 * ISO date is returned unchanged (so non-date strings pass through safely). */
export function journalTitle(value: string | Date): string {
  const dt = toDate(value);
  if (dt === null) return String(value);
  return strftime(dt, "%A, %B %-d %Y");
}

/** Short nav/row date, e.g. `Mon, Jul 13` (day-nav buttons, dir-month rows). */
export function shortDayDate(value: string | Date): string {
  const dt = toDate(value);
  if (dt === null) return String(value);
  // Zero-padded day (mockups/dir-journal-month.html: "Mon, Jul 06", not
  // "Mon, Jul 6") -- journal.html's day-nav only ever shows 2-digit days so
  // this is consistent with that mockup too.
  return strftime(dt, "%a, %b %d");
}
