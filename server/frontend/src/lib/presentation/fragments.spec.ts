import { describe, it, expect } from "vitest";
import { parseSettings, fragmentSteps, type Settings } from "./fragments";

function setup(html: string): HTMLElement {
  const container = document.createElement("div");
  container.innerHTML = html;
  return container;
}

const OFF: Settings = { fragmentAll: false };
const ALL: Settings = { fragmentAll: true };

// Compact view of a step list for assertions: tag + class.
function tags(steps: Element[]): string[] {
  return steps.map((e) => e.tagName.toLowerCase());
}
function texts(steps: Element[]): string[] {
  return steps.map((e) => e.textContent?.trim() ?? "");
}

describe("parseSettings", () => {
  it("defaults to fragmentAll:false when the settings div is absent", () => {
    expect(parseSettings(setup("<p>hi</p>"))).toEqual({ fragmentAll: false });
  });

  it("reads fragmentAll:true from the settings div", () => {
    const root = setup('<div id="awiwi-settings">{"fragmentAll": true}</div>');
    expect(parseSettings(root)).toEqual({ fragmentAll: true });
  });

  it("reads fragmentAll:false explicitly", () => {
    const root = setup('<div id="awiwi-settings">{"fragmentAll": false}</div>');
    expect(parseSettings(root)).toEqual({ fragmentAll: false });
  });

  it("tolerates malformed JSON", () => {
    const root = setup('<div id="awiwi-settings">{not json}</div>');
    expect(parseSettings(root)).toEqual({ fragmentAll: false });
  });

  it("tolerates a null root", () => {
    expect(parseSettings(null)).toEqual({ fragmentAll: false });
  });

  it("ignores unknown keys", () => {
    const root = setup('<div id="awiwi-settings">{"wat": 1}</div>');
    expect(parseSettings(root)).toEqual({ fragmentAll: false });
  });
});

describe("fragmentSteps — opt-in via .fragment", () => {
  it("returns nothing when no element is marked and fragmentAll is off", () => {
    const slide = setup("<h1>T</h1><p>a</p><p>b</p>");
    expect(fragmentSteps(slide, OFF)).toEqual([]);
  });

  it("makes a single marked paragraph one step", () => {
    const slide = setup('<p class="fragment">a</p><p>b</p>');
    const steps = fragmentSteps(slide, OFF);
    expect(tags(steps)).toEqual(["p"]);
    expect(texts(steps)).toEqual(["a"]);
  });

  it("reveals each list item separately when the list is marked", () => {
    const slide = setup(
      '<ul class="fragment"><li>a</li><li>b</li><li>c</li></ul>',
    );
    const steps = fragmentSteps(slide, OFF);
    // The <ul> frame is not its own step; each <li> is.
    expect(tags(steps)).toEqual(["li", "li", "li"]);
    expect(texts(steps)).toEqual(["a", "b", "c"]);
  });

  it("keeps a marked paragraph as one step despite inline children", () => {
    const slide = setup('<p class="fragment">a <em>b</em> c</p>');
    const steps = fragmentSteps(slide, OFF);
    expect(tags(steps)).toEqual(["p"]);
  });

  it("steps an explicitly marked inline span on its own", () => {
    const slide = setup('<p>a <span class="fragment">b</span> c</p>');
    const steps = fragmentSteps(slide, OFF);
    expect(tags(steps)).toEqual(["span"]);
  });

  it("preserves document order across separate marked elements", () => {
    const slide = setup(
      '<p class="fragment">a</p><p>skip</p><ul class="fragment"><li>b</li></ul>',
    );
    expect(texts(fragmentSteps(slide, OFF))).toEqual(["a", "b"]);
  });
});

describe("fragmentSteps — headings and sections", () => {
  it("fragments a marked heading and everything under it until the next same-level heading", () => {
    const slide = setup(
      '<h2 class="fragment">Sec</h2><p>a</p><p>b</p><h2>Next</h2><p>c</p>',
    );
    const steps = fragmentSteps(slide, OFF);
    expect(texts(steps)).toEqual(["Sec", "a", "b"]);
  });

  it("a deeper heading does not close a shallower section", () => {
    const slide = setup(
      '<h2 class="fragment">Sec</h2><p>a</p><h3>Sub</h3><p>b</p><h2>Next</h2><p>c</p>',
    );
    const steps = fragmentSteps(slide, OFF);
    // h3 is deeper than the h2 section, so it and its content stay in the section.
    expect(texts(steps)).toEqual(["Sec", "a", "Sub", "b"]);
  });

  it("a shallower heading closes the section", () => {
    const slide = setup(
      '<h3 class="fragment">Sub</h3><p>a</p><h2>Top</h2><p>b</p>',
    );
    const steps = fragmentSteps(slide, OFF);
    expect(texts(steps)).toEqual(["Sub", "a"]);
  });
});

describe("fragmentSteps — .no-fragment exclusion", () => {
  it("excludes a .no-fragment element inside a fragmented container", () => {
    const slide = setup(
      '<ul class="fragment"><li>a</li><li class="no-fragment">b</li><li>c</li></ul>',
    );
    expect(texts(fragmentSteps(slide, OFF))).toEqual(["a", "c"]);
  });

  it("no-fragment on a heading excludes its whole section under fragmentAll", () => {
    const slide = setup(
      '<h2 class="no-fragment">Sec</h2><p>a</p><h2>Keep</h2><p>b</p>',
    );
    expect(texts(fragmentSteps(slide, ALL))).toEqual(["Keep", "b"]);
  });
});

describe("fragmentSteps — fragmentAll", () => {
  it("fragments every block element by default", () => {
    const slide = setup("<h1>T</h1><p>a</p><ul><li>x</li><li>y</li></ul>");
    const steps = fragmentSteps(slide, ALL);
    // h1, p, and each li — the ul is a container, not a step.
    expect(texts(steps)).toEqual(["T", "a", "x", "y"]);
  });

  it("does not step inline elements under fragmentAll", () => {
    const slide = setup("<p>a <em>b</em> c</p>");
    expect(tags(fragmentSteps(slide, ALL))).toEqual(["p"]);
  });

  it("skips a .no-fragment subtree under fragmentAll", () => {
    const slide = setup(
      '<p>a</p><div class="no-fragment"><p>hidden</p><p>too</p></div><p>b</p>',
    );
    expect(texts(fragmentSteps(slide, ALL))).toEqual(["a", "b"]);
  });
});

describe("fragmentSteps — awiwi-settings", () => {
  it("never fragments the settings div even under fragmentAll", () => {
    const slide = setup(
      '<div id="awiwi-settings">{"fragmentAll": true}</div><p>a</p>',
    );
    expect(texts(fragmentSteps(slide, ALL))).toEqual(["a"]);
  });
});
