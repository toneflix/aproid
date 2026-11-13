import { AdminCommands } from "../../../worker/admin/protocol/commands";
import { AdminInput } from "../../../worker/admin/protocol/input";
import { AdminRunner } from "../AdminRunner";
import { CliCommand } from "../CliCommand";

/** Lets the operator pick an admin command by what it does, guides them through it, then offers the menu again. */
export class WizardCommand extends CliCommand {
  signature = "wizard";

  description = "Pick an admin command from a menu and be guided through it";

  async handle() {
    if (!this.interactive()) {
      this.error("The wizard needs a terminal. Run a command directly instead, as flyylink-cli commands lists them.");
      process.exitCode = 1;

      return;
    }

    for (;;) {
      const name = await this.choice(
        "What do you want to do?",
        [...AdminCommands.map((command) => ({ name: command.title, value: command.name, description: command.description })), { name: "Exit", value: "exit" }],
        0,
        20,
      ).catch((error: unknown) => {
        if (error instanceof Error && error.name === "ExitPromptError") return "exit";

        throw error;
      });
      const command = AdminCommands.find((definition) => definition.name === name);

      if (!command) return;

      process.exitCode = await new AdminRunner(this, true).run(new AdminInput(command), true);

      if (process.exitCode === AdminRunner.cancelled) return;

      this.newLine();
    }
  }
}
