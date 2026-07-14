import { describe, it, expect } from "vitest";
import { resolveMediaSrc } from "./media";

const JOURNAL = "journal/2026/07/2026-07-14.md";

describe("resolveMediaSrc", () => {
  it("treats an assets/ path as already home-relative", () => {
    expect(resolveMediaSrc("assets/2026/07/14/pic.png", JOURNAL)).toBe(
      "/api/raw/assets/2026/07/14/pic.png",
    );
  });

  it("resolves a ../-relative path against the doc's directory", () => {
    expect(resolveMediaSrc("../../../assets/2026/07/14/pic.png", JOURNAL)).toBe(
      "/api/raw/assets/2026/07/14/pic.png",
    );
  });

  it("resolves a sibling path against the doc's directory", () => {
    expect(resolveMediaSrc("diagram.svg", "recipes/bread/sourdough.md")).toBe(
      "/api/raw/recipes/bread/diagram.svg",
    );
  });

  it("strips a leading ./", () => {
    expect(resolveMediaSrc("./pic.png", "recipes/x.md")).toBe(
      "/api/raw/recipes/pic.png",
    );
  });

  it("leaves absolute URLs untouched (returns null)", () => {
    expect(resolveMediaSrc("https://example.com/a.png", JOURNAL)).toBeNull();
    expect(resolveMediaSrc("//cdn/a.png", JOURNAL)).toBeNull();
    expect(resolveMediaSrc("/api/raw/assets/a.png", JOURNAL)).toBeNull();
    expect(resolveMediaSrc("data:image/png;base64,AAAA", JOURNAL)).toBeNull();
  });

  it("returns null for an empty src", () => {
    expect(resolveMediaSrc("", JOURNAL)).toBeNull();
  });
});
