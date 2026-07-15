import { afterEach, describe, expect, it, vi } from "vitest";
import { matchRoute, router } from "./router.svelte";

describe("matchRoute", () => {
  it("matches the home route", () => {
    expect(matchRoute("/")).toEqual({ name: "home", params: {}, path: "/" });
  });

  it("matches /dir with no remainder", () => {
    expect(matchRoute("/dir")).toEqual({
      name: "dir",
      params: { rest: "" },
      path: "/dir",
    });
  });

  it("matches /dir/* with a nested remainder", () => {
    expect(matchRoute("/dir/journal/2026/07")).toEqual({
      name: "dir",
      params: { rest: "journal/2026/07" },
      path: "/dir/journal/2026/07",
    });
  });

  it("matches /todo exactly", () => {
    expect(matchRoute("/todo")).toEqual({ name: "todo", params: {}, path: "/todo" });
  });

  it("matches /journal/:date", () => {
    expect(matchRoute("/journal/2026-07-14")).toEqual({
      name: "journal",
      params: { date: "2026-07-14" },
      path: "/journal/2026-07-14",
    });
  });

  it("matches /assets/:date/:file", () => {
    expect(matchRoute("/assets/2026-07-14/photo.jpg")).toEqual({
      name: "asset",
      params: { date: "2026-07-14", file: "photo.jpg" },
      path: "/assets/2026-07-14/photo.jpg",
    });
  });

  it("matches /recipes/* with a nested remainder", () => {
    expect(matchRoute("/recipes/baking/bread")).toEqual({
      name: "recipes",
      params: { rest: "baking/bread" },
      path: "/recipes/baking/bread",
    });
  });

  it("matches /search exactly", () => {
    expect(matchRoute("/search")).toEqual({ name: "search", params: {}, path: "/search" });
  });

  it("falls back to the notfound catch-all for unknown paths", () => {
    expect(matchRoute("/nope/nested")).toEqual({
      name: "notfound",
      params: {},
      path: "/nope/nested",
    });
  });

  it("does not match /journal without a date segment", () => {
    expect(matchRoute("/journal").name).toBe("notfound");
  });

  it("does not match /assets with a missing file segment", () => {
    expect(matchRoute("/assets/2026-07-14").name).toBe("notfound");
  });

  it("ignores trailing slashes via segment filtering", () => {
    expect(matchRoute("/journal/2026-07-14/")).toEqual({
      name: "journal",
      params: { date: "2026-07-14" },
      path: "/journal/2026-07-14/",
    });
  });
});

describe("router.current — search & hash", () => {
  afterEach(() => {
    router.navigate("/", { replace: true });
  });

  it("exposes an empty search/hash for a plain path", () => {
    router.navigate("/todo", { replace: true });
    expect(router.current.search).toBe("");
    expect(router.current.hash).toBe("");
  });

  it("exposes the querystring (with leading '?') reactively, even query-only", () => {
    router.navigate("/search", { replace: true });
    router.navigate("/search?q=cats", { replace: true });
    expect(router.current.name).toBe("search");
    expect(router.current.search).toBe("?q=cats");
  });

  it("exposes the hash (with leading '#') reactively, even hash-only", () => {
    router.navigate("/todo", { replace: true });
    router.navigate("/todo#section-2", { replace: true });
    expect(router.current.hash).toBe("#section-2");
  });

  it("re-derives search/hash on a query-only navigation on the same path", () => {
    router.navigate("/journal/2026-07-14?x=1", { replace: true });
    const first = router.current;
    router.navigate("/journal/2026-07-14?x=2", { replace: true });
    expect(router.current).not.toBe(first);
    expect(router.current.search).toBe("?x=2");
  });
});

describe("router — hash scroll", () => {
  afterEach(() => {
    document.body.innerHTML = "";
    router.navigate("/", { replace: true });
  });

  it("scrolls the matching element into view after navigating to a hash", async () => {
    const el = document.createElement("div");
    el.id = "section-2";
    document.body.appendChild(el);
    const spy = vi.spyOn(el, "scrollIntoView").mockImplementation(() => {});

    router.navigate("/todo#section-2", { replace: true });
    await new Promise((resolve) => requestAnimationFrame(resolve));

    expect(spy).toHaveBeenCalled();
  });

  it("scrolls on a same-path, hash-only navigation (no route change)", async () => {
    router.navigate("/todo", { replace: true });
    const el = document.createElement("div");
    el.id = "section-3";
    document.body.appendChild(el);
    const spy = vi.spyOn(el, "scrollIntoView").mockImplementation(() => {});

    router.navigate("/todo#section-3", { replace: true });
    await new Promise((resolve) => requestAnimationFrame(resolve));

    expect(spy).toHaveBeenCalled();
  });

  it("does not throw when navigating without a hash", async () => {
    router.navigate("/todo", { replace: true });
    await new Promise((resolve) => requestAnimationFrame(resolve));
  });
});
