import { type AdminAction, findAdminCommand } from "../../worker/admin/protocol/commands";
import { AdminInput } from "../../worker/admin/protocol/input";
import type { Row } from "../../worker/admin/protocol/result";

/** One of a listing's actions, applied to one row of its results. */
export class ResultAction {
  constructor(
    readonly action: AdminAction,
    readonly row: Row,
  ) {}

  /** The actions the listing offers for the row. */
  static offered(actions: readonly AdminAction[], row: Row): ResultAction[] {
    return actions
      .filter((action) => Object.entries(action.when ?? {}).every(([field, value]) => String(row[field]) === value))
      .map((action) => new ResultAction(action, row));
  }

  /** The template with each `{field}` replaced by that field of the row. */
  static describe(template: string, row: Row): string {
    return template.replace(/\{(\w+)\}/g, (_, field: string) => String(row[field] ?? ""));
  }

  get label(): string {
    return this.action.label;
  }

  /** The confirmation question, with the row's fields filled in, or null when none is needed. */
  confirmation(): string | null {
    return this.action.confirm ? ResultAction.describe(this.action.confirm, this.row) : null;
  }

  /** The input that runs the action's command for the row. */
  input(): AdminInput {
    const command = findAdminCommand(this.action.command);

    if (!command) throw new Error(`${this.action.command} is not an admin command.`);

    const fill = (value: string) => ResultAction.describe(value, this.row);
    const args = Object.fromEntries(Object.entries(this.action.arguments ?? {}).map(([name, value]) => [name, fill(value)]));
    const options = Object.fromEntries(Object.entries(this.action.options ?? {}).map(([name, value]) => [name, typeof value === "string" ? fill(value) : value]));

    return new AdminInput(command, args, options);
  }
}
