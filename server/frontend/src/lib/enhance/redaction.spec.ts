import { describe, it, expect } from "vitest";
import { wireRedaction } from "./redaction";

function setup(html: string): HTMLElement {
  const container = document.createElement("div");
  container.innerHTML = html;
  document.body.appendChild(container);
  return container;
}

describe("wireRedaction", () => {
  it("applies button semantics and a reveal title", () => {
    const container = setup('<span class="redacted">secret</span>');
    wireRedaction(container);
    const el = container.querySelector<HTMLElement>(".redacted")!;
    expect(el.getAttribute("role")).toBe("button");
    expect(el.getAttribute("tabindex")).toBe("0");
    expect(el.getAttribute("aria-pressed")).toBe("false");
    expect(el.getAttribute("title")).toBe("Click to reveal");
  });

  it("toggles .is-revealed, aria-pressed and title on click", () => {
    const container = setup('<span class="redacted">secret</span>');
    wireRedaction(container);
    const el = container.querySelector<HTMLElement>(".redacted")!;

    el.click();
    expect(el.classList.contains("is-revealed")).toBe(true);
    expect(el.getAttribute("aria-pressed")).toBe("true");
    expect(el.getAttribute("title")).toBe("Click to redact");

    el.click();
    expect(el.classList.contains("is-revealed")).toBe(false);
    expect(el.getAttribute("aria-pressed")).toBe("false");
  });

  it("cleanup detaches the listener", () => {
    const container = setup('<div class="redacted">body</div>');
    const cleanup = wireRedaction(container);
    const el = container.querySelector<HTMLElement>(".redacted")!;
    cleanup();
    el.click();
    expect(el.classList.contains("is-revealed")).toBe(false);
  });
});
