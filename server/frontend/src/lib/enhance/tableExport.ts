// Serialize a rendered HTML <table> to Markdown / CSV / HTML strings.
// Ported from the T22 mockup serializers (mockups/mockup.js); the row
// extraction and CSV quote-escaping match that reference implementation.

export type TableFormat = "markdown" | "csv" | "html";

/** Extract a table's cell text as a 2D array of trimmed strings (row 0 is the
 * header row, whatever mix of `<th>`/`<td>` each row contains). */
export function tableToRows(table: HTMLTableElement): string[][] {
  return Array.from(table.querySelectorAll("tr")).map((tr) =>
    Array.from(tr.querySelectorAll("th,td")).map((cell) =>
      (cell.textContent ?? "").trim(),
    ),
  );
}

/** GitHub-flavoured Markdown table (header row + `---` separator). */
export function toMarkdown(rows: string[][]): string {
  if (rows.length === 0) return "";
  const out = [
    `| ${rows[0].join(" | ")} |`,
    `| ${rows[0].map(() => "---").join(" | ")} |`,
  ];
  for (const r of rows.slice(1)) out.push(`| ${r.join(" | ")} |`);
  return out.join("\n");
}

/** RFC-4180-ish CSV: quote any cell containing `"`, `,` or a newline, and
 * double interior quotes. */
export function toCsv(rows: string[][]): string {
  return rows
    .map((r) =>
      r
        .map((c) => (/[",\n]/.test(c) ? `"${c.replace(/"/g, '""')}"` : c))
        .join(","),
    )
    .join("\n");
}

/** A minimal HTML table (thead + tbody). Cell text is emitted verbatim,
 * matching the mockup reference. */
export function toHtml(rows: string[][]): string {
  if (rows.length === 0) return "";
  const head = `<tr>${rows[0].map((c) => `<th>${c}</th>`).join("")}</tr>`;
  const body = rows
    .slice(1)
    .map((r) => `<tr>${r.map((c) => `<td>${c}</td>`).join("")}</tr>`)
    .join("\n");
  return `<table>\n<thead>${head}</thead>\n<tbody>\n${body}\n</tbody>\n</table>`;
}

const SERIALIZERS: Record<TableFormat, (rows: string[][]) => string> = {
  markdown: toMarkdown,
  csv: toCsv,
  html: toHtml,
};

/** Serialize a live `<table>` element to the requested format in one step. */
export function serializeTable(table: HTMLTableElement, format: TableFormat): string {
  return SERIALIZERS[format](tableToRows(table));
}
