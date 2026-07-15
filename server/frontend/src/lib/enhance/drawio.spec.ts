import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

const getDocMock = vi.fn();
vi.mock("../api", () => ({
  getDoc: (...args: unknown[]) => getDocMock(...args),
}));

const loadDrawioViewerMock = vi.fn();
vi.mock("../drawioViewer", () => ({
  loadDrawioViewer: (...args: unknown[]) => loadDrawioViewerMock(...args),
}));

import { enhanceDrawio, resolveDrawioPath } from "./drawio";

const JOURNAL = "journal/2026/07/2026-07-14.md";

function setup(html: string): HTMLElement {
  const container = document.createElement("div");
  container.innerHTML = html;
  document.body.appendChild(container);
  return container;
}

function flush(): Promise<void> {
  // Let queued microtasks (fetch/viewer-load promise chains) settle.
  return new Promise((resolve) => setTimeout(resolve, 0));
}

describe("resolveDrawioPath", () => {
  it("treats an assets/ href as already home-relative", () => {
    expect(resolveDrawioPath("assets/2026/07/14/diagram.drawio", JOURNAL)).toBe(
      "assets/2026/07/14/diagram.drawio",
    );
  });

  it("resolves a relative href against the doc's directory", () => {
    expect(resolveDrawioPath("../../../assets/2026/07/14/diagram.drawio", JOURNAL)).toBe(
      "assets/2026/07/14/diagram.drawio",
    );
  });

  it("returns null for absolute hrefs", () => {
    expect(resolveDrawioPath("https://example.com/a.drawio", JOURNAL)).toBeNull();
    expect(resolveDrawioPath("/api/raw/assets/a.drawio", JOURNAL)).toBeNull();
  });

  it("returns null for an empty href", () => {
    expect(resolveDrawioPath("", JOURNAL)).toBeNull();
  });
});

describe("enhanceDrawio", () => {
  beforeEach(() => {
    getDocMock.mockReset();
    loadDrawioViewerMock.mockReset();
    loadDrawioViewerMock.mockResolvedValue(undefined);
    window.GraphViewer = { processElements: vi.fn() };
  });

  afterEach(() => {
    delete (window as { GraphViewer?: unknown }).GraphViewer;
    document.body.innerHTML = "";
  });

  it("replaces a drawio link with a figure, viewer div, and captioned link", async () => {
    getDocMock.mockResolvedValue({ text: "<mxGraphModel/>" });
    const container = setup(
      '<p>See <a href="assets/2026/07/14/diagram.drawio">the diagram</a> for detail.</p>',
    );

    enhanceDrawio(container, JOURNAL);
    await flush();

    expect(getDocMock).toHaveBeenCalledWith("assets/2026/07/14/diagram.drawio");
    const figure = container.querySelector("figure.drawio-inline");
    expect(figure).not.toBeNull();

    const graph = figure!.querySelector<HTMLElement>(".mxgraph");
    expect(graph).not.toBeNull();
    const payload = JSON.parse(graph!.getAttribute("data-mxgraph")!);
    expect(payload).toEqual({ xml: "<mxGraphModel/>", lightbox: false });

    const captionLink = figure!.querySelector<HTMLAnchorElement>("figcaption a");
    expect(captionLink).not.toBeNull();
    expect(captionLink!.getAttribute("href")).toBe("assets/2026/07/14/diagram.drawio");
    expect(captionLink!.textContent).toBe("the diagram");

    expect(window.GraphViewer!.processElements).toHaveBeenCalled();
    // The plain <a> is gone from the body — only the caption anchor remains.
    expect(container.querySelectorAll("p > a").length).toBe(0);
  });

  it("degrades gracefully back to the plain link on fetch failure", async () => {
    getDocMock.mockRejectedValue(new Error("404"));
    const container = setup('<a href="assets/missing.drawio">broken</a>');

    enhanceDrawio(container, JOURNAL);
    await flush();

    expect(container.querySelector("figure.drawio-inline")).toBeNull();
    const anchor = container.querySelector<HTMLAnchorElement>("a");
    expect(anchor).not.toBeNull();
    expect(anchor!.getAttribute("href")).toBe("assets/missing.drawio");
    expect(anchor!.textContent).toBe("broken");
  });

  it("degrades gracefully when the viewer script fails to load", async () => {
    getDocMock.mockResolvedValue({ text: "<mxGraphModel/>" });
    loadDrawioViewerMock.mockRejectedValue(new Error("script load failed"));
    const container = setup('<a href="assets/x.drawio">x</a>');

    enhanceDrawio(container, JOURNAL);
    await flush();

    expect(container.querySelector("figure.drawio-inline")).toBeNull();
    expect(container.querySelector("a")).not.toBeNull();
  });

  it("ignores non-local (absolute) drawio hrefs, leaving the link untouched", async () => {
    const container = setup('<a href="https://example.com/a.drawio">remote</a>');

    enhanceDrawio(container, JOURNAL);
    await flush();

    expect(getDocMock).not.toHaveBeenCalled();
    expect(container.querySelector("figure.drawio-inline")).toBeNull();
    expect(container.querySelector("a")).not.toBeNull();
  });

  it("is idempotent: a second pass over the same container does not re-fetch or double-wrap", async () => {
    getDocMock.mockResolvedValue({ text: "<mxGraphModel/>" });
    const container = setup('<a href="assets/diagram.drawio">the diagram</a>');

    enhanceDrawio(container, JOURNAL);
    await flush();
    expect(getDocMock).toHaveBeenCalledTimes(1);
    expect(container.querySelectorAll("figure.drawio-inline").length).toBe(1);

    enhanceDrawio(container, JOURNAL);
    await flush();

    expect(getDocMock).toHaveBeenCalledTimes(1);
    expect(container.querySelectorAll("figure.drawio-inline").length).toBe(1);
    expect(container.querySelectorAll("figcaption a").length).toBe(1);
  });

  it("returns a no-op cleanup", () => {
    const container = setup('<p>no links here</p>');
    const cleanup = enhanceDrawio(container, JOURNAL);
    expect(() => cleanup()).not.toThrow();
  });
});
