import { findAdminCommand } from "../../worker/admin/protocol/commands";
import { AdminInput } from "../../worker/admin/protocol/input";
import type { AdminResult, Listing, Row } from "../../worker/admin/protocol/result";
import { AdminClient } from "./AdminClient";
import type { CliCommand } from "./CliCommand";
import { ConfigStore } from "./ConfigStore";
import { GuidedInput } from "./GuidedInput";
import { ResultAction } from "./ResultAction";
import { ResultPrinter } from "./ResultPrinter";

/**
 * Runs admin commands for a flyylink-admin command. When it is interactive it asks for missing input
 * and, for a listing, lets the operator pick a result and an action to run on it. A result that names
 * a next command, such as an email's next batch, is followed on its own.
 */
export class AdminRunner {
  private client: AdminClient | null = null;

  constructor(
    private readonly cli: CliCommand,
    private readonly interactive: boolean,
    private readonly json = false,
  ) {}

  /** Runs the command and returns its exit status. `chooseOptions` offers its options when none were given. */
  async run(input: AdminInput, chooseOptions = !input.optionsGiven()): Promise<number> {
    try {
      if (this.interactive && !(await new GuidedInput(this.cli).fill(input, chooseOptions))) {
        this.cli.info("Nothing was changed.");

        return 0;
      }

      if (!this.valid(input)) return 1;

      return await this.send(input);
    } catch (error) {
      if (error instanceof Error && error.name === "ExitPromptError") {
        this.cli.newLine().warn("Cancelled.");

        return 130;
      }

      throw error;
    }
  }

  private valid(input: AdminInput): boolean {
    const problems = input.problems();

    for (const problem of problems) this.cli.error(problem);

    if (problems.length) this.cli.line(`Usage: flyylink-admin ${input.usage()}`);

    return !problems.length;
  }

  private async send(input: AdminInput): Promise<number> {
    const client = await this.connect();
    if (!client) return 1;

    const browsing = this.interactive && !this.json && Boolean(input.command.results);
    let result = await client.run(input.toRequest());

    for (;;) {
      this.output(browsing && result.listing?.rows.length ? { ...result, listing: undefined } : result);

      if (result.exit !== 0 || !result.next) break;

      const next = findAdminCommand(result.next.command);
      if (!next) break;

      result = await client.run(new AdminInput(next, result.next.arguments).toRequest());
    }

    if (browsing && result.exit === 0 && result.listing?.rows.length) {
      return await this.browse(input, result.listing);
    }

    return result.exit;
  }

  private output(result: AdminResult): void {
    if (this.json) this.cli.line(JSON.stringify(result));
    else new ResultPrinter(this.cli).print(result);
  }

  /** Lets the operator pick a row of the listing or another page, then runs the action they pick for the row. */
  private async browse(input: AdminInput, listing: Listing): Promise<number> {
    const picked = await this.pick(listing, input.command.results!.label);

    if (picked === "done") return 0;

    if (typeof picked === "number") {
      const page = new AdminInput(input.command, input.arguments, { ...input.options, page: String(picked) });

      return await this.send(page);
    }

    const actions = ResultAction.offered(input.command.results!.actions, picked);
    const choice = await this.cli.choice("What do you want to do with it?", [
      ...actions.map((action, index) => ({ name: action.label, value: String(index) })),
      { name: "Nothing, exit", value: "done" },
    ]);

    if (choice === "done") return 0;

    const action = actions[Number(choice)]!;
    const question = action.confirmation();

    if (question && !(await this.cli.confirm(question, false))) {
      this.cli.info("Nothing was changed.");

      return 0;
    }

    return await this.run(action.input(), !action.action.options);
  }

  /** Asks for a row by its label, another page number, or `done`. */
  private async pick(listing: Listing, label: string): Promise<Row | number | "done"> {
    const { page, lastPage, total } = listing;
    const rows = listing.rows.map((row, index) => ({ name: ResultAction.describe(label, row), value: String(index) }));
    const pages = [...(page < lastPage ? [{ name: "Next page", value: "next" }] : []), ...(page > 1 ? [{ name: "Previous page", value: "previous" }] : [])];
    const choice = await this.cli.choice(`Choose one (page ${page} of ${lastPage}, ${total} in all)`, [...rows, ...pages, { name: "Exit", value: "done" }]);

    if (choice === "done") return "done";
    if (choice === "next") return page + 1;
    if (choice === "previous") return page - 1;

    return listing.rows[Number(choice)]!;
  }

  private async connect(): Promise<AdminClient | null> {
    if (this.client) return this.client;

    const config = await new ConfigStore().load();

    if (!config) this.cli.error("Not connected. Run flyylink-admin login first.");

    this.client = config ? new AdminClient(config) : null;

    return this.client;
  }
}
