// Pure helpers for DirPage's journal-month week banding (T22 mockup item —
// dir-journal-month.html groups day rows under ISO week headers).
//
// ISO-8601 week number via the standard "nearest Thursday" method. Verified
// against Python's `date.isocalendar()` for the year-boundary edge cases
// (2018-12-31 -> 2019-W01, 2020-12-31 -> 2020-W53, 2016-01-04 -> 2016-W01,
// 2017-01-01 -> 2016-W52) — see weekBands.spec.ts.

const ISO_DAY_RE = /^\d{4}-\d{2}-\d{2}$/;

/** True for a journal day-file name (`YYYY-MM-DD`), as opposed to a year/month
 * directory name or `todos.md`. */
export function isJournalDayName(name: string): boolean {
  return ISO_DAY_RE.test(name);
}

export interface IsoWeek {
  isoYear: number;
  week: number;
}

/** ISO-8601 week number for a calendar date. `month` is 1-12. */
export function isoWeekNumber(year: number, month: number, day: number): IsoWeek {
  const date = new Date(Date.UTC(year, month - 1, day));
  const dayNum = (date.getUTCDay() + 6) % 7; // Mon=0 .. Sun=6
  date.setUTCDate(date.getUTCDate() - dayNum + 3); // nearest Thursday
  const isoYear = date.getUTCFullYear();
  const firstThursday = new Date(Date.UTC(isoYear, 0, 4));
  const firstDayNum = (firstThursday.getUTCDay() + 6) % 7;
  firstThursday.setUTCDate(firstThursday.getUTCDate() - firstDayNum + 3);
  const week = 1 + Math.round((date.getTime() - firstThursday.getTime()) / (7 * 86400000));
  return { isoYear, week };
}

export interface WeekBand<T> {
  label: string;
  days: T[];
}

/** Group day entries (named `YYYY-MM-DD`) into ISO-week bands, ascending.
 * Safe to key by bare week number (no isoYear) because callers only ever
 * pass entries from a single directory listing (one calendar month), where a
 * Dec/Jan wraparound always produces distinct week numbers, never a
 * same-number collision. */
export function bandByWeek<T extends { name: string }>(entries: T[]): WeekBand<T>[] {
  const bands = new Map<number, T[]>();
  for (const entry of entries) {
    const [y, m, d] = entry.name.split("-").map(Number);
    const { week } = isoWeekNumber(y, m, d);
    const bucket = bands.get(week);
    if (bucket) bucket.push(entry);
    else bands.set(week, [entry]);
  }
  return [...bands.entries()]
    .sort(([a], [b]) => a - b)
    .map(([week, days]) => ({ label: `Week ${week}`, days }));
}
