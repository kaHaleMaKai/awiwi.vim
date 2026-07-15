// TOC scrollspy: marks the rail link for the heading currently in view with
// `.is-active` (mockups/journal.html — "Morning" is `.is-active` while
// reading that section). Wired directly from the page component (Journal/
// Todo/Doc), not the shared `enhance()` pipeline, since it reads the article's
// headings but writes into the separate `.rail`/`.toc` DOM, not the enhanced
// container itself.
export function watchToc(article: HTMLElement, toc: HTMLElement): () => void {
  const links = new Map(
    Array.from(toc.querySelectorAll<HTMLAnchorElement>("a[href^='#']")).map((a) => [
      a.getAttribute("href")!.slice(1),
      a,
    ]),
  );
  const headings = Array.from(
    article.querySelectorAll<HTMLElement>("h2[id], h3[id]"),
  ).filter((h) => links.has(h.id));
  if (headings.length === 0) return () => {};

  let activeId: string | null = null;
  function setActive(id: string): void {
    if (id === activeId) return;
    if (activeId) links.get(activeId)?.classList.remove("is-active");
    links.get(id)?.classList.add("is-active");
    activeId = id;
  }

  // A heading counts as "current" once it crosses a thin band just below the
  // sticky header — ponytail: simple band heuristic, not a "most visible
  // heading" ranking; good enough for single-column journal/doc bodies.
  const observer = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) setActive(entry.target.id);
      }
    },
    { rootMargin: "-80px 0px -85% 0px", threshold: 0 },
  );
  for (const h of headings) observer.observe(h);
  setActive(headings[0].id);

  return () => observer.disconnect();
}
