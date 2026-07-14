import { describe, it, expect } from "vitest";
import { highlightMatch } from "./searchHighlight";

describe("highlightMatch", () => {
  it("splits before/match/after for a fixed literal match, case-insensitively", () => {
    expect(highlightMatch("export AWIWI_TOKEN=...", "token", "fixed")).toEqual({
      before: "export AWIWI_",
      match: "TOKEN",
      after: "=...",
    });
  });

  it("treats fixed-mode query characters as literal, not regex syntax", () => {
    expect(highlightMatch("price is $5.00 today", "$5.00", "fixed")).toEqual({
      before: "price is ",
      match: "$5.00",
      after: " today",
    });
  });

  it("matches as a real pattern in regex mode", () => {
    expect(highlightMatch("rotate token every 30 days", "\\d+ days", "regex")).toEqual({
      before: "rotate token every ",
      match: "30 days",
      after: "",
    });
  });

  it("returns null when there's no match", () => {
    expect(highlightMatch("nothing here", "missing", "fixed")).toBeNull();
  });

  it("returns null for an empty query", () => {
    expect(highlightMatch("some text", "", "fixed")).toBeNull();
  });

  it("returns null (never throws) for an invalid regex in regex mode", () => {
    expect(highlightMatch("some text", "(unclosed", "regex")).toBeNull();
  });
});
