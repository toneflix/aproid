import type { SignatureBuilder } from "@h3ravel/musket";
import type { AdminCommand } from "../../../worker/admin/protocol/commands";
import { AdminInput } from "../../../worker/admin/protocol/input";
import { AdminRunner } from "../AdminRunner";
import { CliCommand } from "../CliCommand";

/** An admin command, checked here against its definition, guided when interactive, and run on the server. */
export abstract class ForwardedCommand extends CliCommand {
  abstract readonly definition: AdminCommand;

  /** The command class for one admin command. */
  static for(definition: AdminCommand) {
    return class extends ForwardedCommand {
      readonly definition = definition;
    };
  }

  /** Every argument is optional here, so a guided run can ask for the missing ones instead of refusing. */
  override buildSignature(builder: SignatureBuilder) {
    builder.command(this.definition.name).describe(this.definition.description);

    for (const argument of this.definition.arguments) builder.argument(argument.name, { description: argument.description, required: false });

    for (const option of this.definition.options) {
      builder.option(
        option.name,
        option.type === "flag"
          ? { description: option.description }
          : { description: option.description, default: option.default, requiresValue: option.default === undefined, choices: option.choices ? [...option.choices] : undefined },
      );
    }

    return builder.option("json", { description: "Print the result as JSON, without questions" });
  }

  async handle() {
    const args: Record<string, unknown> = this.arguments();
    const options: Record<string, unknown> = this.options();
    const camel = (name: string) => name.replace(/-([a-z])/g, (_, letter: string) => letter.toUpperCase());
    const input = new AdminInput(
      this.definition,
      Object.fromEntries(this.definition.arguments.map((argument) => [argument.name, args[argument.name] as string | undefined])),
      Object.fromEntries(this.definition.options.map((option) => [option.name, options[camel(option.name)] as string | boolean | undefined])),
    );
    const json = options.json === true;

    process.exitCode = await new AdminRunner(this, this.interactive() && !json, json).run(input);
  }
}
