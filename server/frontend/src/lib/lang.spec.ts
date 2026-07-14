import { describe, it, expect } from "vitest";
import { guessLanguage, modelineLanguage } from "./lang";

describe("guessLanguage — extension map", () => {
  it("maps common extensions to Shiki ids", () => {
    expect(guessLanguage("a.py")).toBe("python");
    expect(guessLanguage("a.rs")).toBe("rust");
    expect(guessLanguage("a.ts")).toBe("typescript");
    expect(guessLanguage("a.tsx")).toBe("tsx");
    expect(guessLanguage("a.sh")).toBe("bash");
    expect(guessLanguage("a.zsh")).toBe("bash");
    expect(guessLanguage("a.yml")).toBe("yaml");
    expect(guessLanguage("a.yaml")).toBe("yaml");
    expect(guessLanguage("a.cc")).toBe("cpp");
    expect(guessLanguage("a.h")).toBe("c");
    expect(guessLanguage("a.conf")).toBe("ini");
    expect(guessLanguage("a.md")).toBe("markdown");
  });

  it("is case-insensitive on the extension", () => {
    expect(guessLanguage("README.MD")).toBe("markdown");
    expect(guessLanguage("Main.PY")).toBe("python");
  });

  it("honours a directory prefix on the path", () => {
    expect(guessLanguage("recipes/db/schema.sql")).toBe("sql");
  });

  it("returns null for an unknown extension", () => {
    expect(guessLanguage("a.xyz")).toBeNull();
    expect(guessLanguage("noext")).toBeNull();
  });

  it("treats a leading-dot filename as having no extension", () => {
    expect(guessLanguage(".bashrc")).toBeNull();
  });
});

describe("guessLanguage — dockerfile by name", () => {
  it("recognizes Dockerfile-style names regardless of case or suffix", () => {
    expect(guessLanguage("Dockerfile")).toBe("dockerfile");
    expect(guessLanguage("dockerfile")).toBe("dockerfile");
    expect(guessLanguage("build/Dockerfile.prod")).toBe("dockerfile");
  });
});

describe("guessLanguage — modeline", () => {
  it("wins over the filename extension", () => {
    expect(guessLanguage("notes.txt", "-- vim: ft=sql\n")).toBe("sql");
  });

  it("applies the pgsql -> sql alias, lowercased", () => {
    expect(guessLanguage("x.txt", "-- vim: ft=pgsql.\n")).toBe("sql");
  });

  it("falls through to the filename when no modeline is present", () => {
    expect(guessLanguage("a.py", "print('hi')\n")).toBe("python");
  });
});

describe("modelineLanguage", () => {
  it("sniffs the ft name (non-greedy, needs trailing space or dot)", () => {
    expect(modelineLanguage("-- vim: ft=pgsql.\n")).toBe("pgsql");
    expect(modelineLanguage("# vim: ft=python\n")).toBe("python");
    expect(modelineLanguage("no modeline here")).toBeNull();
  });
});
