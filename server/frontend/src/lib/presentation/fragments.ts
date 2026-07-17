// Pure helpers for presentation "fragmenting": deciding which elements of a
// rendered slide reveal step-by-step on click. Mirrors slides.ts — no Svelte,
// no side effects; the component (PresentationMode) hides/reveals the returned
// elements and tracks the per-slide revealed count.
//
// Authoring: `.fragment` / `.no-fragment` classes (via markdown attr_list or a
// `<div class="fragment" markdown="1">` wrapper) opt elements in/out. A global
// `#awiwi-settings` JSON blob may set `fragmentAll` to fragment everything by
// default. See docs/architecture.md → presentation mode.

export interface Settings {
  fragmentAll: boolean;
}

/** Parse the `#awiwi-settings` JSON blob from the doc root. Tolerant: a missing
 * div, empty text, or malformed JSON all yield the defaults. Only `fragmentAll`
 * is honored for now. */
export function parseSettings(root: Element | null): Settings {
  const el = root?.querySelector("#awiwi-settings");
  if (!el) return { fragmentAll: false };
  try {
    const parsed = JSON.parse(el.textContent ?? "");
    return { fragmentAll: parsed?.fragmentAll === true };
  } catch {
    return { fragmentAll: false };
  }
}

// Block-level tags the server's markdown pipeline can emit. Step granularity is
// block-level: inline elements (em, code, a, span, …) only step when explicitly
// marked `.fragment`.
const BLOCK = new Set([
  "ADDRESS", "ARTICLE", "ASIDE", "BLOCKQUOTE", "DETAILS", "DD", "DIV", "DL",
  "DT", "FIELDSET", "FIGCAPTION", "FIGURE", "FOOTER", "FORM", "H1", "H2", "H3",
  "H4", "H5", "H6", "HEADER", "HR", "LI", "MAIN", "NAV", "OL", "P", "PRE",
  "SECTION", "TABLE", "TBODY", "TD", "TH", "THEAD", "TR", "UL",
]);

type State = "include" | "exclude" | "unset";

function headingLevel(el: Element): number | null {
  const m = /^H([1-6])$/.exec(el.tagName);
  return m ? Number(m[1]) : null;
}

function selfState(el: Element): State {
  // .no-fragment wins over .fragment when both are present.
  if (el.classList.contains("no-fragment")) return "exclude";
  if (el.classList.contains("fragment")) return "include";
  return "unset";
}

/**
 * Ordered (document order) list of elements to reveal one step at a time.
 *
 * Membership rules, most specific wins:
 *  - self `.fragment`/`.no-fragment` on the element,
 *  - else the nearest enclosing heading's section state — a `.fragment` heading
 *    fragments itself and every following sibling until the next heading of
 *    equal/shallower depth (h2 until the next h2/h1),
 *  - else the nearest ancestor container's state (a `.fragment` div/list marks
 *    all its descendants),
 *  - else `fragmentAll`.
 *
 * Step granularity is "each child separately": a step is an *innermost* included
 * block-level element (or an explicitly `.fragment` inline element). A fragmented
 * container is not a step itself — its frame shows immediately and its children
 * step one by one. `#awiwi-settings` never fragments.
 */
export function fragmentSteps(slideEl: Element, opts: Settings): Element[] {
  const included = new Set<Element>();

  // Classify siblings left-to-right, tracking the active heading section.
  const walk = (parent: Element, inherited: State): void => {
    let sectionState: State = "unset";
    let sectionLevel = 0;

    for (const child of Array.from(parent.children)) {
      if (child.id === "awiwi-settings") continue; // never fragmented, skip subtree

      const lvl = headingLevel(child);
      // A heading of level `lvl` closes any section opened at an equal/shallower
      // depth before it takes effect.
      if (lvl !== null && sectionState !== "unset" && sectionLevel >= lvl) {
        sectionState = "unset";
        sectionLevel = 0;
      }

      const own = selfState(child);
      const eff: State =
        own !== "unset"
          ? own
          : sectionState !== "unset"
            ? sectionState
            : inherited;

      if (eff === "include" || (eff === "unset" && opts.fragmentAll)) {
        included.add(child);
      }

      // A classed heading opens a section for the siblings that follow it.
      if (lvl !== null && own !== "unset") {
        sectionState = own;
        sectionLevel = lvl;
      }

      walk(child, eff);
    }
  };

  walk(slideEl, "unset");

  const stepEligible = (el: Element): boolean =>
    included.has(el) &&
    (BLOCK.has(el.tagName) || el.classList.contains("fragment"));

  const eligible = Array.from(slideEl.querySelectorAll("*")).filter(stepEligible);
  // Innermost only: drop any eligible element that contains another eligible one.
  return eligible.filter(
    (el) => !eligible.some((other) => other !== el && el.contains(other)),
  );
}
