import type { AdminResult, Listing, Table } from "../../worker/admin/protocol/result";
import type { CliCommand } from "./CliCommand";

/** Prints an admin command's result: its notes in color, then its fields and tables. */
export class ResultPrinter {
  static readonly maxCell = 60;

  constructor(private readonly cli: CliCommand) {}

  print(result: AdminResult): void {
    for (const note of result.notes) this.cli[note.level](note.text);

    if (result.fields?.length) this.cli.fields(result.fields);

    for (const table of result.tables ?? []) this.table(table);

    if (result.listing) this.listing(result.listing);
  }

  /** The table as aligned lines: a dimmed header, then one line per row. */
  static lines(table: Table): string[] {
    const cell = (value: unknown) => {
      const text = value === null || value === undefined ? "-" : String(value).replace(/\s+/g, " ");

      return text.length > ResultPrinter.maxCell ? `${text.slice(0, ResultPrinter.maxCell - 1)}…` : text;
    };
    const rows = table.rows.map((row) => table.columns.map((column) => cell(row[column.key])));
    const widths = table.columns.map((column, i) => Math.max(column.label.length, ...rows.map((row) => row[i].length)));
    const line = (cells: string[]) => cells.map((text, i) => text.padEnd(widths[i])).join("  ").trimEnd();

    return [line(table.columns.map((column) => column.label)), ...rows.map(line)];
  }

  private table(table: Table): void {
    this.cli.newLine();

    if (table.title) this.cli.line(this.cli.paint(table.title, "bold"));

    if (!table.rows.length) {
      this.cli.line(this.cli.paint(table.empty, "gray"));

      return;
    }

    const [header, ...rows] = ResultPrinter.lines(table);

    this.cli.line(this.cli.paint(header, "gray"));
    rows.forEach((row) => this.cli.line(row));
  }

  private listing(listing: Listing): void {
    if (!listing.rows.length) {
      this.cli.info(listing.empty);

      return;
    }

    const [header, ...rows] = ResultPrinter.lines(listing);

    this.cli.line(this.cli.paint(header, "gray"));
    rows.forEach((row) => this.cli.line(row));

    if (listing.lastPage > 1) this.cli.line(this.cli.paint(`Page ${listing.page} of ${listing.lastPage}, ${listing.total} in all. Use --page to see more.`, "gray"));
  }
}
