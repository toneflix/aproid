import type { LoggerChalk } from "@h3ravel/shared";
import type { AdminResult, Cell, Listing, Row, Table } from "../../worker/admin/protocol/result";
import type { CliCommand } from "./CliCommand";

/** Values that read as good or bad news, colored so a list can be scanned. */
const tones: Record<string, LoggerChalk> = {
  active: "green",
  yes: "green",
  ok: "green",
  sent: "green",
  revoked: "red",
  no: "red",
  failed: "red",
  sending: "yellow",
};

/**
 * Prints an admin command's result: its notes in color, then its fields, and each row of a table or
 * listing as its own block of labelled values.
 */
export class ResultPrinter {
  static readonly maxValue = 100;

  constructor(private readonly cli: CliCommand) {}

  print(result: AdminResult): void {
    for (const note of result.notes) this.cli[note.level](note.text);

    if (result.fields?.length) this.fields(result.fields);

    for (const table of result.tables ?? []) this.table(table);

    if (result.listing) this.listing(result.listing);
  }

  /** A value as it is shown: on one line, shortened when long, and a dash when empty. */
  static text(value: Cell | undefined): string {
    const text = value === null || value === undefined || value === "" ? "-" : String(value).replace(/\s+/g, " ");

    return text.length > ResultPrinter.maxValue ? `${text.slice(0, ResultPrinter.maxValue - 1)}…` : text;
  }

  /** The label and value pairs of one row, in column order. */
  static pairs(table: Table, row: Row): [string, string][] {
    return table.columns.map((column) => [column.label, ResultPrinter.text(row[column.key])]);
  }

  private fields(pairs: [string, string][], first = false): void {
    const width = Math.max(...pairs.map(([label]) => label.length));

    pairs.forEach(([label, value], index) => this.cli.line(`${this.cli.paint(label.padEnd(width), "gray")}  ${this.value(value, first && index === 0)}`));
  }

  private value(text: string, lead: boolean): string {
    if (lead) return this.cli.paint(text, ["cyan", "bold"]);
    if (text === "-") return this.cli.paint(text, "gray");

    const tone = tones[text.toLowerCase()];

    return tone ? this.cli.paint(text, tone) : text;
  }

  private rows(table: Table): void {
    table.rows.forEach((row, index) => {
      if (index > 0) this.cli.newLine();

      this.fields(ResultPrinter.pairs(table, row), true);
    });
  }

  private table(table: Table): void {
    this.cli.newLine();

    if (table.title) this.cli.line(this.cli.paint(table.title, "bold"));

    if (!table.rows.length) {
      this.cli.line(this.cli.paint(table.empty, "gray"));

      return;
    }

    this.rows(table);
  }

  private listing(listing: Listing): void {
    if (!listing.rows.length) {
      this.cli.info(listing.empty);

      return;
    }

    this.rows(listing);

    if (listing.lastPage > 1) {
      this.cli.newLine();
      this.cli.line(this.cli.paint(`Page ${listing.page} of ${listing.lastPage}, ${listing.total} in all. Use --page to see more.`, "gray"));
    }
  }
}
