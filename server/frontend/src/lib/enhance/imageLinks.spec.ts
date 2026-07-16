import { describe, it, expect, afterEach } from "vitest";
import { inlineImageLinks } from "./imageLinks";

const JOURNAL = "journal/2026/07/2026-07-14.md";

function setup(html: string): HTMLElement {
  const container = document.createElement("div");
  container.innerHTML = html;
  document.body.appendChild(container);
  return container;
}

afterEach(() => {
  document.body.innerHTML = "";
});

describe("inlineImageLinks", () => {
  it("replaces an assets/ image link with an <img> (home-relative src, alt from text)", () => {
    const container = setup(
      '<p>See <a href="assets/2026/07/01/photo.png">the photo</a>.</p>',
    );

    inlineImageLinks(container, JOURNAL);

    expect(container.querySelector("a")).toBeNull();
    const img = container.querySelector<HTMLImageElement>("img");
    expect(img).not.toBeNull();
    expect(img!.getAttribute("src")).toBe("assets/2026/07/01/photo.png");
    expect(img!.getAttribute("alt")).toBe("the photo");
  });

  it("inlines a doc-relative image link (scope is not limited to assets/)", () => {
    const container = setup('<a href="../pics/x.jpg">x</a>');

    inlineImageLinks(container, JOURNAL);

    const img = container.querySelector<HTMLImageElement>("img");
    expect(img).not.toBeNull();
    expect(img!.getAttribute("src")).toBe("journal/2026/pics/x.jpg");
  });

  it("leaves a non-image link untouched", () => {
    const container = setup('<a href="assets/notes.md">notes</a>');
    inlineImageLinks(container, JOURNAL);
    expect(container.querySelector("a")).not.toBeNull();
    expect(container.querySelector("img")).toBeNull();
  });

  it("leaves absolute image hrefs untouched", () => {
    const container = setup(
      '<a href="https://example.com/x.png">remote</a>' +
        '<a href="/api/raw/assets/y.png">root</a>',
    );
    inlineImageLinks(container, JOURNAL);
    expect(container.querySelectorAll("a").length).toBe(2);
    expect(container.querySelector("img")).toBeNull();
  });

  it("leaves an anchor that already wraps an <img> untouched", () => {
    const container = setup(
      '<a href="assets/full.png"><img src="assets/thumb.png" alt="t"></a>',
    );
    inlineImageLinks(container, JOURNAL);
    const anchor = container.querySelector("a");
    expect(anchor).not.toBeNull();
    expect(anchor!.querySelector("img")).not.toBeNull();
  });

  it("treats a link with a query string as an image", () => {
    const container = setup('<a href="assets/x.png?v=2">q</a>');
    inlineImageLinks(container, JOURNAL);
    const img = container.querySelector<HTMLImageElement>("img");
    expect(img).not.toBeNull();
    expect(img!.getAttribute("src")).toBe("assets/x.png?v=2");
  });

  it("returns a no-op cleanup that does not throw", () => {
    const container = setup("<p>no links here</p>");
    const cleanup = inlineImageLinks(container, JOURNAL);
    expect(() => cleanup()).not.toThrow();
  });
});
