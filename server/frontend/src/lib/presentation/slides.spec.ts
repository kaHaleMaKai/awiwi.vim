import { describe, it, expect } from "vitest";
import { splitSlides, step, arrowOpacity } from "./slides";

function setup(html: string): HTMLElement {
  const container = document.createElement("div");
  container.innerHTML = html;
  return container;
}

describe("splitSlides", () => {
  it("splits n h1s into n slides, each starting with its own h1", () => {
    const root = setup(
      "<h1>One</h1><p>a</p><h1>Two</h1><p>b</p><h1>Three</h1><p>c</p>",
    );
    const slides = splitSlides(root);
    expect(slides.length).toBe(3);
    expect(slides[0].startsWith("<h1>One</h1>")).toBe(true);
    expect(slides[0]).toContain("<p>a</p>");
    expect(slides[1].startsWith("<h1>Two</h1>")).toBe(true);
    expect(slides[1]).toContain("<p>b</p>");
    expect(slides[2].startsWith("<h1>Three</h1>")).toBe(true);
    expect(slides[2]).toContain("<p>c</p>");
  });

  it("puts a non-empty preamble before the first h1 into slide 0", () => {
    const root = setup("<p>intro</p><h1>One</h1><p>a</p>");
    const slides = splitSlides(root);
    expect(slides.length).toBe(2);
    expect(slides[0]).toBe("<p>intro</p>");
    expect(slides[1].startsWith("<h1>One</h1>")).toBe(true);
  });

  it("does not create an extra slide for whitespace-only preamble", () => {
    const root = setup("   \n  <h1>One</h1><p>a</p>");
    const slides = splitSlides(root);
    expect(slides.length).toBe(1);
    expect(slides[0].startsWith("<h1>One</h1>")).toBe(true);
  });

  it("returns exactly one slide when there are zero h1s", () => {
    const root = setup("<p>a</p><h2>sub</h2><p>b</p>");
    const slides = splitSlides(root);
    expect(slides.length).toBe(1);
    expect(slides[0]).toContain("<p>a</p>");
    expect(slides[0]).toContain("<h2>sub</h2>");
    expect(slides[0]).toContain("<p>b</p>");
  });

  it("does not treat an h1 nested inside a blockquote as a boundary", () => {
    const root = setup(
      "<h1>One</h1><blockquote><h1>Nested</h1></blockquote><h1>Two</h1>",
    );
    const slides = splitSlides(root);
    expect(slides.length).toBe(2);
    expect(slides[0]).toContain("<blockquote><h1>Nested</h1></blockquote>");
    expect(slides[1].startsWith("<h1>Two</h1>")).toBe(true);
  });

  it("does not treat an h1 nested inside a details element as a boundary", () => {
    const root = setup(
      "<h1>One</h1><details><h1>Nested</h1></details><h1>Two</h1>",
    );
    const slides = splitSlides(root);
    expect(slides.length).toBe(2);
    expect(slides[0]).toContain("<details><h1>Nested</h1></details>");
    expect(slides[1].startsWith("<h1>Two</h1>")).toBe(true);
  });
});

describe("arrowOpacity", () => {
  it("is dim going backward from the first slide", () => {
    expect(arrowOpacity(0, 3, -1)).toBe(0.1);
  });

  it("is bright going forward from the first slide", () => {
    expect(arrowOpacity(0, 3, 1)).toBe(0.5);
  });

  it("is bright in both directions from a middle slide", () => {
    expect(arrowOpacity(1, 3, -1)).toBe(0.5);
    expect(arrowOpacity(1, 3, 1)).toBe(0.5);
  });

  it("is dim going forward from the last slide", () => {
    expect(arrowOpacity(2, 3, 1)).toBe(0.1);
  });

  it("is bright going backward from the last slide", () => {
    expect(arrowOpacity(2, 3, -1)).toBe(0.5);
  });

  it("is dim in both directions when there is only one slide", () => {
    expect(arrowOpacity(0, 1, 1)).toBe(0.1);
    expect(arrowOpacity(0, 1, -1)).toBe(0.1);
  });
});

describe("step", () => {
  it("clamps at the last slide when stepping forward", () => {
    expect(step(2, 3, 1)).toBe(2);
  });

  it("clamps at the first slide when stepping backward", () => {
    expect(step(0, 3, -1)).toBe(0);
  });

  it("advances by one within bounds", () => {
    expect(step(0, 3, 1)).toBe(1);
    expect(step(1, 3, -1)).toBe(0);
  });
});
