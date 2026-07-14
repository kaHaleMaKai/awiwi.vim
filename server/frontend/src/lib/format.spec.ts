import { describe, it, expect } from "vitest";
import { beautifyDate } from "./format";

// Fixtures generated from the Python server's `beautify_if_date`
// (C locale) — beautifyDate must match these byte-for-byte, including the
// historical 11st/13rd ordinal quirk.
describe("beautifyDate — pinned to Python beautify_if_date", () => {
  const cases: [string, string | null | undefined, string][] = [
    ["2026-07-14", null, "Tue, 14<sup>th</sup>"],
    ["2026-07-14", "%B", "Tue, 14<sup>th</sup> July"],
    ["2026-07-14", "%B %Y", "Tue, 14<sup>th</sup> July 2026"],
    ["2026-07-01", null, "Wed, 1<sup>st</sup>"],
    ["2026-07-02", null, "Thu, 2<sup>nd</sup>"],
    ["2026-07-03", null, "Fri, 3<sup>rd</sup>"],
    ["2026-07-11", null, "Sat, 11<sup>st</sup>"],
    ["2026-11-13", null, "Fri, 13<sup>rd</sup>"],
    ["2026-07-21", "%B %Y", "Tue, 21<sup>st</sup> July 2026"],
    ["2026-12-31", "%B %Y", "Thu, 31<sup>st</sup> December 2026"],
    ["2000-01-01", "%B %Y", "Sat, 1<sup>st</sup> January 2000"],
  ];
  for (const [input, format, expected] of cases) {
    it(`${input} + ${String(format)} -> ${expected}`, () => {
      expect(beautifyDate(input, format)).toBe(expected);
    });
  }
});

describe("beautifyDate — non-dates pass through unchanged", () => {
  it("returns a non-ISO string verbatim", () => {
    expect(beautifyDate("not-a-date")).toBe("not-a-date");
    expect(beautifyDate("hello", "%B")).toBe("hello");
    expect(beautifyDate("recipes")).toBe("recipes");
  });

  it("returns an invalid calendar date verbatim", () => {
    expect(beautifyDate("2026-02-30")).toBe("2026-02-30");
    expect(beautifyDate("2026-13-01")).toBe("2026-13-01");
  });
});

describe("beautifyDate — accepts a Date object", () => {
  it("formats a Date the same as its ISO string", () => {
    const dt = new Date(Date.UTC(2026, 6, 14));
    expect(beautifyDate(dt, "%B %Y")).toBe("Tue, 14<sup>th</sup> July 2026");
  });
});
