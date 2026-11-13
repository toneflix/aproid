import type { AdminCommandName } from "../protocol/commands";
import type { AdminInput } from "../protocol/input";
import type { Column, Listing, Reply, Row } from "../protocol/result";
import type { Found, Paging } from "../../licence/store";

/** What a command handler gets: the checked input, the reply to fill, who is running it and when. */
export interface CommandContext {
  input: AdminInput;
  reply: Reply;
  actor: string;
  now: number;
}

export type CommandHandler = (context: CommandContext) => Promise<void>;

/** A set of related admin commands and the handler for each. */
export abstract class CommandGroup {
  abstract handlers(): Partial<Record<AdminCommandName, CommandHandler>>;

  /** The page and page size the input asks for, capped at 100 rows. */
  protected static paging(input: AdminInput): Paging & { page: number } {
    const page = Math.max(1, input.number("page"));
    const limit = Math.min(100, Math.max(1, input.number("limit")));

    return { page, limit, offset: (page - 1) * limit };
  }

  protected static listing<T>(found: Found<T>, paging: { page: number; limit: number }, columns: Column[], toRow: (item: T) => Row, empty: string): Listing {
    return {
      columns,
      rows: found.rows.map(toRow),
      page: paging.page,
      lastPage: Math.max(1, Math.ceil(found.total / paging.limit)),
      total: found.total,
      empty,
    };
  }

  /** A Unix time as `2026-11-13 14:05` UTC, or a dash. */
  protected static when(seconds: number | null | undefined): string {
    return seconds ? new Date(seconds * 1000).toISOString().slice(0, 16).replace("T", " ") : "-";
  }

  protected static yesNo(value: unknown): string {
    return value ? "yes" : "no";
  }
}
