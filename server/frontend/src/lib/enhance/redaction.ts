// Click-to-reveal for redacted spans/divs (T22 feedback round 1 item 4).
//
// On localhost the server embeds the real value in the DOM, obscured purely by
// CSS (`.redacted`: ink block, transparent text). The frontend only toggles
// visibility: click or Enter/Space flips `.is-revealed`, `aria-pressed`, and
// the title. Accessibility attributes (role/tabindex) are applied here so they
// don't have to be baked into the server HTML.

/** Wire every `.redacted` element in `container` for click-to-reveal.
 * Returns a cleanup that detaches the listeners. */
export function wireRedaction(container: HTMLElement): () => void {
  const els = Array.from(container.querySelectorAll<HTMLElement>(".redacted"));
  const removers: Array<() => void> = [];

  for (const el of els) {
    el.setAttribute("role", "button");
    el.setAttribute("tabindex", "0");
    el.setAttribute("aria-pressed", "false");
    el.setAttribute("title", "Click to reveal");

    const toggle = () => {
      const on = el.classList.toggle("is-revealed");
      el.setAttribute("aria-pressed", String(on));
      el.setAttribute("title", on ? "Click to redact" : "Click to reveal");
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Enter" || e.key === " ") {
        e.preventDefault();
        toggle();
      }
    };
    el.addEventListener("click", toggle);
    el.addEventListener("keydown", onKey);
    removers.push(() => {
      el.removeEventListener("click", toggle);
      el.removeEventListener("keydown", onKey);
    });
  }

  return () => {
    for (const remove of removers) remove();
  };
}
