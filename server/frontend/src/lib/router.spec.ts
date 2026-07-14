import { describe, expect, it } from "vitest";
import { matchRoute } from "./router.svelte";

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
