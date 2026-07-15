import { describe, it, expect } from "vitest";
import { journalTitle, shortDayDate, ordinalSuffix } from "./format";

describe("ordinalSuffix", () => {
  const cases: [number, string][] = [
    [1, "st"],
    [2, "nd"],
    [3, "rd"],
    [4, "th"],
    // the historical bug: these were "st"/"nd"/"rd" (keyed off the last
    // digit only) instead of "th".
    [11, "th"],
    [12, "th"],
    [13, "th"],
    [21, "st"],
    [22, "nd"],
    [23, "rd"],
    [31, "st"],
  ];
  for (const [day, expected] of cases) {
    it(`${day} -> ${expected}`, () => {
      expect(ordinalSuffix(day)).toBe(expected);
    });
  }
});

describe("journalTitle — mockups/journal.html H1 shape", () => {
  it('formats "Tuesday, July 14 2026"', () => {
    expect(journalTitle("2026-07-14")).toBe("Tuesday, July 14 2026");
  });

  it("formats a Date the same as its ISO string", () => {
    const dt = new Date(Date.UTC(2026, 6, 14));
    expect(journalTitle(dt)).toBe("Tuesday, July 14 2026");
  });

  it("returns non-dates unchanged", () => {
    expect(journalTitle("not-a-date")).toBe("not-a-date");
    expect(journalTitle("2026-02-30")).toBe("2026-02-30");
  });
});

describe("shortDayDate — day-nav / dir-month row shape", () => {
  const cases: [string, string][] = [
    ["2026-07-13", "Mon, Jul 13"],
    ["2026-07-14", "Tue, Jul 14"],
    ["2026-07-15", "Wed, Jul 15"],
    ["2026-11-13", "Fri, Nov 13"],
    ["2026-07-06", "Mon, Jul 06"],
    ["2026-07-09", "Thu, Jul 09"],
  ];
  for (const [input, expected] of cases) {
    it(`${input} -> ${expected}`, () => {
      expect(shortDayDate(input)).toBe(expected);
    });
  }

  it("returns non-dates unchanged", () => {
    expect(shortDayDate("recipes")).toBe("recipes");
    expect(shortDayDate("2026-13-01")).toBe("2026-13-01");
  });
});
