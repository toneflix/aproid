import { AdminCommands } from "../../../worker/admin/protocol/commands";
import { CliCommand } from "../CliCommand";

/** Lists the admin commands this CLI can run. */
export class CommandsCommand extends CliCommand {
  signature = "commands";

  description = "List the admin commands you can run";

  async handle() {
    const width = Math.max(...AdminCommands.map((command) => command.name.length));

    for (const command of AdminCommands) this.line(`  ${this.paint(command.name.padEnd(width), "green")}  ${command.description}`);

    this.newLine();
    this.line(`Run one as ${this.paint("flyylink-cli <command> [arguments]", "cyan")}. Add --help to see its options.`);
  }
}
