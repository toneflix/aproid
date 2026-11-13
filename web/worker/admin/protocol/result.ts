export type Cell = string | number | null;
export type Row = Record<string, Cell>;

export interface Column {
  key: string;
  label: string;
}

export interface Table {
  title?: string;
  columns: Column[];
  rows: Row[];
  /** Shown instead of the table when it has no rows. */
  empty: string;
}

/** A page of a listing, which a guided run lets the operator page through and act on. */
export interface Listing extends Table {
  page: number;
  lastPage: number;
  total: number;
}

export interface Note {
  level: "info" | "success" | "warn" | "error";
  text: string;
}

/** What an admin command answers, for the CLI to print. */
export interface AdminResult {
  exit: number;
  notes: Note[];
  fields?: [string, string][];
  tables?: Table[];
  listing?: Listing;
  /** A command the CLI runs next on its own, such as an email's next batch. */
  next?: { command: string; arguments: Record<string, string> };
}

/** Builds an admin command's result. */
export class Reply {
  private readonly result: AdminResult = { exit: 0, notes: [] };

  info(text: string): this {
    return this.note("info", text);
  }

  success(text: string): this {
    return this.note("success", text);
  }

  warn(text: string): this {
    return this.note("warn", text);
  }

  /** Adds an error and makes the command fail. */
  error(text: string): this {
    this.result.exit = 1;

    return this.note("error", text);
  }

  fields(pairs: [string, string][]): this {
    this.result.fields = pairs;

    return this;
  }

  table(table: Table): this {
    (this.result.tables ??= []).push(table);

    return this;
  }

  listing(listing: Listing): this {
    this.result.listing = listing;

    return this;
  }

  next(command: string, args: Record<string, string>): this {
    this.result.next = { command, arguments: args };

    return this;
  }

  get failed(): boolean {
    return this.result.exit !== 0;
  }

  toJSON(): AdminResult {
    return this.result;
  }

  private note(level: Note["level"], text: string): this {
    this.result.notes.push({ level, text });

    return this;
  }
}
