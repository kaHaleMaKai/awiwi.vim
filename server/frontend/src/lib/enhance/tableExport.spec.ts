import { describe, it, expect } from "vitest";
import {
  tableToRows,
  toMarkdown,
  toCsv,
  toHtml,
  serializeTable,
} from "./tableExport";

const ROWS = [
  ["Flour (g)", "Water (g)", "Hydration"],
  ["500", "350", "70%"],
  ["500", "375", "75%"],
];

describe("toMarkdown", () => {
  it("emits a header row, a separator row, then body rows", () => {
    expect(toMarkdown(ROWS)).toBe(
      [
        "| Flour (g) | Water (g) | Hydration |",
        "| --- | --- | --- |",
        "| 500 | 350 | 70% |",
        "| 500 | 375 | 75% |",
      ].join("\n"),
    );
  });

  it("returns an empty string for no rows", () => {
    expect(toMarkdown([])).toBe("");
  });
});

describe("toCsv", () => {
  it("joins cells with commas and rows with newlines", () => {
    expect(toCsv(ROWS)).toBe(
      ["Flour (g),Water (g),Hydration", "500,350,70%", "500,375,75%"].join("\n"),
    );
  });

  it("quotes and escapes cells with commas, quotes, or newlines", () => {
    const rows = [["a,b", 'he said "hi"', "line1\nline2"]];
    expect(toCsv(rows)).toBe('"a,b","he said ""hi""","line1\nline2"');
  });
});

describe("toHtml", () => {
  it("wraps the header in thead and the rest in tbody", () => {
    expect(toHtml([["A", "B"], ["1", "2"]])).toBe(
      "<table>\n<thead><tr><th>A</th><th>B</th></tr></thead>\n<tbody>\n<tr><td>1</td><td>2</td></tr>\n</tbody>\n</table>",
    );
  });

  it("returns an empty string for no rows", () => {
    expect(toHtml([])).toBe("");
  });
});

describe("tableToRows / serializeTable — against a real table element", () => {
  function makeTable(): HTMLTableElement {
    const el = document.createElement("table");
    el.innerHTML =
      "<thead><tr><th> Flour (g) </th><th>Water (g)</th></tr></thead>" +
      "<tbody><tr><td>500</td><td>350</td></tr></tbody>";
    return el;
  }

  it("extracts trimmed cell text, header row first", () => {
    expect(tableToRows(makeTable())).toEqual([
      ["Flour (g)", "Water (g)"],
      ["500", "350"],
    ]);
  });

  it("serializeTable dispatches to the right serializer", () => {
    const table = makeTable();
    expect(serializeTable(table, "csv")).toBe("Flour (g),Water (g)\n500,350");
    expect(serializeTable(table, "markdown")).toContain("| Flour (g) | Water (g) |");
  });
});
