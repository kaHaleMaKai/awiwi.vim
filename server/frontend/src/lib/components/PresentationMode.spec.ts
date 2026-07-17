import { describe, it, expect, beforeAll, vi, afterEach } from "vitest";
import { mount, unmount, flushSync } from "svelte";
import PresentationMode from "./PresentationMode.svelte";

// Controllable clock so the component's duplicate-input coalescing (50ms window)
// doesn't eat synchronous test presses. Each press() advances it well past 50ms;
// dispatching two events without advancing simulates one physical double-fire.
let clock = 0;
function tick(ms = 100) {
  clock += ms;
}

// happy-dom lacks the fullscreen API the component pokes on open()/close();
// stub it so mount() doesn't throw. matchMedia exists in happy-dom.
beforeAll(() => {
  performance.now = () => clock;
  // @ts-expect-error test stub
  Element.prototype.requestFullscreen = () => Promise.resolve();
  // @ts-expect-error test stub
  document.exitFullscreen = () => Promise.resolve();
  // Report reduced-motion so flyDuration() is 0 and Svelte skips the WAAPI
  // animation (happy-dom has no element.animate).
  window.matchMedia = (query: string) =>
    ({
      matches: true,
      media: query,
      addEventListener() {},
      removeEventListener() {},
    }) as unknown as MediaQueryList;
});

// A two-slide fragmentAll deck with DIFFERENT fragment counts per slide, so a
// stale/foreign stepCount is observable: slide 0 has 3 steps (h1 + 2 <p>),
// slide 1 has 4 (h1 + 3 <p>).
const DECK = `
  <h1>Slide One</h1>
  <div id="awiwi-settings">{"fragmentAll": true}</div>
  <p>a1</p>
  <p>a2</p>
  <h1>Slide Two</h1>
  <p>b1</p>
  <p>b2</p>
  <p>b3</p>
`;

function makeRoot(html: string): Element {
  const root = document.createElement("div");
  root.className = "markdown-body";
  root.innerHTML = html;
  return root;
}

/** The incoming (current) slide is the last .pm-slide in the stage. */
function currentSlide(target: Element): Element {
  const slides = target.querySelectorAll(".pm-slide");
  return slides[slides.length - 1];
}

function currentHeading(target: Element): string {
  return currentSlide(target).querySelector("h1")?.textContent?.trim() ?? "";
}

function revealedCount(target: Element): number {
  return currentSlide(target).querySelectorAll(".pm-frag:not(.pm-frag-hidden)")
    .length;
}

function press(key: string) {
  tick();
  document.dispatchEvent(new KeyboardEvent("keydown", { key, bubbles: true }));
  flushSync();
}

function pressOn(el: Element, key: string) {
  tick();
  el.dispatchEvent(new KeyboardEvent("keydown", { key, bubbles: true }));
  flushSync();
}

function openDeck(): { target: Element; inst: Record<string, () => void> } {
  const target = document.createElement("div");
  document.body.appendChild(target);
  const root = makeRoot(DECK);
  const inst = mount(PresentationMode, {
    target,
    props: { getRoot: () => root },
  }) as unknown as Record<string, () => void>;
  inst.open();
  flushSync();
  return { target, inst };
}

describe("PresentationMode — fragment navigation", () => {
  it("reveals every fragment of a slide before crossing to the next", () => {
    const target = document.createElement("div");
    document.body.appendChild(target);
    const root = makeRoot(DECK);
    const inst = mount(PresentationMode, {
      target,
      props: { getRoot: () => root },
    });
    inst.open();
    flushSync();

    // Slide 0 starts with all 3 fragments hidden.
    expect(currentHeading(target)).toBe("Slide One");
    expect(revealedCount(target)).toBe(0);

    // Three clicks reveal the three fragments — still on slide 0 after the last.
    press("ArrowRight");
    expect(currentHeading(target)).toBe("Slide One");
    expect(revealedCount(target)).toBe(1);

    press("ArrowRight");
    expect(currentHeading(target)).toBe("Slide One");
    expect(revealedCount(target)).toBe(2);

    press("ArrowRight");
    // The click that reveals the LAST fragment must NOT advance the slide.
    expect(currentHeading(target)).toBe("Slide One");
    expect(revealedCount(target)).toBe(3);

    // Only the next click crosses to slide 1.
    press("ArrowRight");
    expect(currentHeading(target)).toBe("Slide Two");

    unmount(inst);
    target.remove();
  });

  it("hides a fresh slide's fragments instantly (no flash on slide change)", () => {
    // A freshly mounted slide must hide its fragments without the transition
    // class — otherwise the first fragment fades opacity 1→0 and flashes over
    // the outgoing slide during the fly. The reveal transition is opt-in per
    // user input, so .pm-animate only appears after a press.
    const { target, inst } = openDeck();
    const frags = currentSlide(target).querySelectorAll(".pm-frag");
    expect(frags.length).toBeGreaterThan(0);
    frags.forEach((f) => expect(f.classList.contains("pm-animate")).toBe(false));

    press("ArrowRight");
    const shown = currentSlide(target).querySelector(
      ".pm-frag:not(.pm-frag-hidden)",
    );
    expect(shown?.classList.contains("pm-animate")).toBe(true);

    unmount(inst as never);
    target.remove();
  });

  it("‹ / › buttons skip fragments and jump a whole slide", () => {
    const { target, inst } = openDeck();
    const nextBtn = target.querySelector('[aria-label="Next slide"]') as HTMLElement;
    const prevBtn = target.querySelector(
      '[aria-label="Previous slide"]',
    ) as HTMLElement;

    // Slide One still has hidden fragments; › jumps straight to Slide Two.
    expect(currentHeading(target)).toBe("Slide One");
    expect(revealedCount(target)).toBe(0);
    tick();
    nextBtn.click();
    flushSync();
    expect(currentHeading(target)).toBe("Slide Two");

    // ‹ jumps straight back to Slide One, now with all its fragments revealed.
    tick();
    prevBtn.click();
    flushSync();
    expect(currentHeading(target)).toBe("Slide One");
    expect(revealedCount(target)).toBe(3);

    unmount(inst as never);
    target.remove();
  });

  it("uses the current slide's own fragment count after crossing", () => {
    const target = document.createElement("div");
    document.body.appendChild(target);
    const root = makeRoot(DECK);
    const inst = mount(PresentationMode, {
      target,
      props: { getRoot: () => root },
    });
    inst.open();
    flushSync();

    // Cross to slide 1: reveal all 3 of slide 0, then one more to advance.
    for (let i = 0; i < 4; i++) press("ArrowRight");
    expect(currentHeading(target)).toBe("Slide Two");
    expect(revealedCount(target)).toBe(0);

    // Slide 1 has 4 fragments — all must reveal before it clamps at the end.
    press("ArrowRight");
    press("ArrowRight");
    press("ArrowRight");
    press("ArrowRight");
    expect(currentHeading(target)).toBe("Slide Two");
    expect(revealedCount(target)).toBe(4);

    unmount(inst);
    target.remove();
  });
});

// A single input must cause exactly one navigation step. The overlay advances on
// both click and Enter, the document listener advances on Space/arrows, and the
// overlay also contains native control buttons — overlapping paths that can fire
// next() twice (native button activation + a bubbled keydown handler), which
// reveals the last fragment AND jumps in one input.
describe("PresentationMode — debug logging", () => {
  afterEach(() => vi.restoreAllMocks());

  const pmLogs = (spy: ReturnType<typeof vi.spyOn>) =>
    spy.mock.calls.filter((c) => c[0] === "[awiwi:presentation]");

  it('logs lifecycle when "debug": true is set', () => {
    const spy = vi.spyOn(console, "log").mockImplementation(() => {});
    const target = document.createElement("div");
    document.body.appendChild(target);
    const root = makeRoot(
      DECK.replace('{"fragmentAll": true}', '{"fragmentAll": true, "debug": true}'),
    );
    const inst = mount(PresentationMode, {
      target,
      props: { getRoot: () => root },
    }) as unknown as Record<string, () => void>;
    inst.open();
    flushSync();
    press("ArrowRight"); // reveal a fragment

    const msgs = pmLogs(spy).map((c) => c.join(" "));
    expect(msgs.some((m) => m.includes("open deck"))).toBe(true);
    expect(msgs.some((m) => m.includes("open slide"))).toBe(true);
    expect(msgs.some((m) => m.includes("input: key"))).toBe(true);
    expect(msgs.some((m) => m.includes("show element"))).toBe(true);

    unmount(inst as never);
    target.remove();
  });

  it("stays silent by default (debug off)", () => {
    const spy = vi.spyOn(console, "log").mockImplementation(() => {});
    const { target, inst } = openDeck(); // DECK has no debug flag
    press("ArrowRight");

    expect(pmLogs(spy)).toHaveLength(0);

    unmount(inst as never);
    target.remove();
  });
});

describe("PresentationMode — one input, one step", () => {
  it("Space/Enter on the overlay itself advances (reveals) once", () => {
    const { target, inst } = openDeck();
    const overlay = target.querySelector(".pm-overlay")!;

    pressOn(overlay, " ");
    expect(revealedCount(target)).toBe(1);
    pressOn(overlay, "Enter");
    expect(revealedCount(target)).toBe(2);

    unmount(inst as never);
    target.remove();
  });

  it("Space on a focused control button does not also advance via the document handler", () => {
    const { target, inst } = openDeck();
    const nextBtn = target.querySelector('[aria-label="Next slide"]')!;

    // The button activates itself natively; the document handler must NOT also
    // fire next() (would be a double-step).
    pressOn(nextBtn, " ");
    expect(revealedCount(target)).toBe(0);

    unmount(inst as never);
    target.remove();
  });

  it("collapses a duplicate navigation fired within the coalesce window", () => {
    const { target, inst } = openDeck();
    const overlay = target.querySelector(".pm-overlay")!;

    // Two keydowns at the same instant simulate one physical input delivered
    // twice (remote click+key, native activation + bubbled handler). Only the
    // first should take effect, so the last-fragment click can't also advance.
    tick(); // off the fresh-mount baseline
    overlay.dispatchEvent(
      new KeyboardEvent("keydown", { key: "ArrowRight", bubbles: true }),
    );
    overlay.dispatchEvent(
      new KeyboardEvent("keydown", { key: "ArrowRight", bubbles: true }),
    );
    flushSync();
    expect(revealedCount(target)).toBe(1); // not 2

    unmount(inst as never);
    target.remove();
  });

  it("Enter bubbling from a focused control button does not double-advance via the overlay handler", () => {
    const { target, inst } = openDeck();
    const nextBtn = target.querySelector('[aria-label="Next slide"]')!;

    // The button's native Enter activation is the single legitimate advance; the
    // overlay's onkeydown must ignore the bubbled event (target !== overlay).
    pressOn(nextBtn, "Enter");
    expect(revealedCount(target)).toBe(0);

    unmount(inst as never);
    target.remove();
  });
});
