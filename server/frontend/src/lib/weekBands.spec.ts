import { describe, it, expect } from "vitest";
import { isJournalDayName, isoWeekNumber, bandByWeek } from "./weekBands";

describe("isJournalDayName", () => {
  it("matches ISO day names", () => {
    expect(isJournalDayName("2026-07-14")).toBe(true);
  });
  it("rejects year/month dir names and todos.md", () => {
    expect(isJournalDayName("2026")).toBe(false);
    expect(isJournalDayName("07")).toBe(false);
    expect(isJournalDayName("todos.md")).toBe(false);
  });
});

describe("isoWeekNumber", () => {
  // Fixtures cross-checked against Python's datetime.date(...).isocalendar().
  const cases: [number, number, number, number, number][] = [
    [2018, 12, 31, 2019, 1],
    [2019, 1, 1, 2019, 1],
    [2020, 12, 31, 2020, 53],
    [2021, 1, 1, 2020, 53],
    [2026, 7, 6, 2026, 28],
    [2026, 7, 13, 2026, 29],
    [2026, 7, 14, 2026, 29],
    [2026, 7, 31, 2026, 31],
    [2026, 1, 4, 2026, 1],
    [2016, 1, 4, 2016, 1],
    [2017, 1, 1, 2016, 52],
    [2017, 1, 2, 2017, 1],
  ];
  for (const [y, m, d, isoYear, week] of cases) {
    it(`${y}-${m}-${d} -> ISO ${isoYear}-W${week}`, () => {
      expect(isoWeekNumber(y, m, d)).toEqual({ isoYear, week });
    });
  }
});

describe("bandByWeek", () => {
  it("groups day entries by ISO week, ascending, within one month", () => {
    const entries = [
      { name: "2026-07-01" },
      { name: "2026-07-06" },
      { name: "2026-07-07" },
      { name: "2026-07-13" },
      { name: "2026-07-14" },
      { name: "2026-07-31" },
    ];
    const bands = bandByWeek(entries);
    expect(bands.map((b) => b.label)).toEqual(["Week 27", "Week 28", "Week 29", "Week 31"]);
    expect(bands[0].days).toEqual([{ name: "2026-07-01" }]);
    expect(bands[1].days).toEqual([{ name: "2026-07-06" }, { name: "2026-07-07" }]);
    expect(bands[2].days).toEqual([{ name: "2026-07-13" }, { name: "2026-07-14" }]);
    expect(bands[3].days).toEqual([{ name: "2026-07-31" }]);
  });
});
