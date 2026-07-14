import { describe, it, expect } from "vitest";
import {
  parseSearchUrl,
  serializeSearchUrl,
  searchPath,
  hitRelpath,
  hitCrumbSegments,
  searchHitHref,
  groupSearchHits,
  type SearchUrlState,
} from "./searchState";
import type { SearchHit } from "./api";

function hit(over: Partial<SearchHit>): SearchHit {
  return { target: "", name: "", line: 1, col: 1, type: "journal", text: "", ...over };
}

describe("parseSearchUrl", () => {
  it("defaults to empty q, fixed mode, no scopes", () => {
    expect(parseSearchUrl("")).toEqual({ q: "", mode: "fixed", scopes: [] });
  });

  it("reads q, mode=regex, and a comma-separated scope list", () => {
    expect(parseSearchUrl("?q=token&mode=regex&scope=journal,recipes")).toEqual({
      q: "token",
      mode: "regex",
      scopes: ["journal", "recipes"],
    });
  });

  it("falls back to fixed for an unrecognized mode", () => {
    expect(parseSearchUrl("?q=x&mode=bogus").mode).toBe("fixed");
  });

  it("drops unrecognized scope tokens", () => {
    expect(parseSearchUrl("?q=x&scope=journal,bogus,recipes").scopes).toEqual([
      "journal",
      "recipes",
    ]);
  });

  it("works without a leading ?", () => {
    expect(parseSearchUrl("q=hi")).toEqual({ q: "hi", mode: "fixed", scopes: [] });
  });
});

describe("serializeSearchUrl / searchPath round-trip", () => {
  const cases: SearchUrlState[] = [
    { q: "", mode: "fixed", scopes: [] },
    { q: "token", mode: "fixed", scopes: [] },
    { q: "token", mode: "regex", scopes: ["journal"] },
    { q: "redacted OR token", mode: "fixed", scopes: ["journal", "assets"] },
    { q: "a,b", mode: "regex", scopes: ["journal", "assets", "recipes"] },
  ];

  for (const state of cases) {
    it(`round-trips ${JSON.stringify(state)}`, () => {
      expect(parseSearchUrl(serializeSearchUrl(state))).toEqual(state);
    });
  }

  it("bare state serializes to an empty string, bare /search path", () => {
    expect(serializeSearchUrl({ q: "", mode: "fixed", scopes: [] })).toBe("");
    expect(searchPath({ q: "", mode: "fixed", scopes: [] })).toBe("/search");
  });

  it("non-empty state produces a /search?... path", () => {
    expect(searchPath({ q: "token", mode: "fixed", scopes: [] })).toBe("/search?q=token");
  });
});

describe("hitRelpath", () => {
  it("maps a todo hit to journal/todos.md", () => {
    expect(hitRelpath(hit({ type: "todo", name: "todo", target: "/todo" }))).toBe(
      "journal/todos.md",
    );
  });

  it("maps a journal hit to its year/month path", () => {
    expect(hitRelpath(hit({ type: "journal", name: "2026-07-14" }))).toBe(
      "journal/2026/07/2026-07-14.md",
    );
  });

  it("maps an asset hit's date/filename name to its year/month/day path", () => {
    expect(
      hitRelpath(hit({ type: "asset", name: "2026-07-14/deploy-notes.txt" })),
    ).toBe("assets/2026/07/14/deploy-notes.txt");
  });

  it("uses the recipe target as-is (already a bare relpath)", () => {
    expect(
      hitRelpath(hit({ type: "recipe", target: "recipes/ops/rotate-credentials.md" })),
    ).toBe("recipes/ops/rotate-credentials.md");
  });
});

describe("hitCrumbSegments", () => {
  it("splits a journal hit's date into y/m/d segments", () => {
    expect(hitCrumbSegments(hit({ type: "journal", name: "2026-07-14" }))).toEqual([
      "journal",
      "2026",
      "07",
      "14",
    ]);
  });

  it("uses directory segments for an asset hit", () => {
    expect(
      hitCrumbSegments(hit({ type: "asset", name: "2026-07-14/deploy-notes.txt" })),
    ).toEqual(["assets", "2026", "07", "14"]);
  });

  it("uses directory segments for a recipe hit", () => {
    expect(
      hitCrumbSegments(hit({ type: "recipe", target: "recipes/ops/rotate-credentials.md" })),
    ).toEqual(["recipes", "ops"]);
  });
});

describe("searchHitHref", () => {
  it("uses the target verbatim for todo/journal/asset (already SPA-route-shaped)", () => {
    expect(searchHitHref(hit({ type: "todo", target: "/todo" }))).toBe("/todo");
    expect(searchHitHref(hit({ type: "journal", target: "/journal/2026-07-14" }))).toBe(
      "/journal/2026-07-14",
    );
    expect(
      searchHitHref(hit({ type: "asset", target: "/assets/2026-07-14/x.txt" })),
    ).toBe("/assets/2026-07-14/x.txt");
  });

  it("prefixes a leading slash for a recipe target", () => {
    expect(
      searchHitHref(hit({ type: "recipe", target: "recipes/ops/rotate-credentials.md" })),
    ).toBe("/recipes/ops/rotate-credentials.md");
  });
});

describe("groupSearchHits", () => {
  it("groups consecutive hits from the same file, preserving order", () => {
    const hits: SearchHit[] = [
      hit({ type: "journal", name: "2026-07-14", line: 14, col: 5 }),
      hit({ type: "journal", name: "2026-07-14", line: 15, col: 1 }),
      hit({
        type: "asset",
        name: "2026-07-14/deploy-notes.txt",
        line: 42,
        col: 1,
      }),
    ];
    const groups = groupSearchHits(hits);
    expect(groups).toHaveLength(2);
    expect(groups[0]).toMatchObject({
      relpath: "journal/2026/07/2026-07-14.md",
      hits: [hits[0], hits[1]],
    });
    expect(groups[1]).toMatchObject({
      relpath: "assets/2026/07/14/deploy-notes.txt",
      hits: [hits[2]],
    });
  });

  it("returns an empty array for no hits", () => {
    expect(groupSearchHits([])).toEqual([]);
  });
});
