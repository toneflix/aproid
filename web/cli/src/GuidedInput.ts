import type { AdminOption } from "../../worker/admin/protocol/commands";
import { AdminInput } from "../../worker/admin/protocol/input";

type Choices = readonly string[] | readonly { name: string; value: string }[];

/** The prompts a Musket command offers, which guided input asks its questions through. */
export interface Prompter {
  ask(message: string, defaultValue?: string): Promise<string>;
  choice(message: string, choices: Choices): Promise<string>;
  confirm(message: string, defaultValue?: boolean): Promise<boolean>;
  checkbox(message: string, choices: Choices, required?: boolean): Promise<string[]>;
}

/** Asks the operator, step by step, for the input an admin command still needs. */
export class GuidedInput {
  constructor(private readonly cli: Prompter) {}

  /**
   * Asks for each missing required argument, then each option the command asks for in turn, and, when
   * `chooseOptions` is set, lets the operator pick any of the remaining options to set. A command that
   * needs confirming asks last, and the result is false when the operator declines.
   */
  async fill(input: AdminInput, chooseOptions: boolean): Promise<boolean> {
    for (const argument of input.missing()) {
      input.arguments[argument.name] = argument.choices
        ? await this.cli.choice(argument.label, argument.choices)
        : (await this.cli.ask(argument.label)).trim();
    }

    for (const option of input.command.options) {
      if (option.ask && !AdminInput.filled(input.options[option.name])) input.options[option.name] = await this.value(option);
    }

    if (chooseOptions && input.command.chooseOptions) await this.chooseOptions(input);

    return await this.confirm(input);
  }

  /** Lets the operator pick the optional options to set, then asks for each one picked. */
  private async chooseOptions(input: AdminInput): Promise<void> {
    const optional = input.command.options.filter(
      (option) => !option.ask && option.guided !== false && option.name !== input.command.confirm?.option && !AdminInput.filled(input.options[option.name]),
    );

    if (!optional.length) return;

    const chosen = await this.cli.checkbox(
      "Choose the options to set, or press enter for none",
      optional.map((option) => ({ name: option.label, value: option.name })),
      false,
    );

    for (const option of optional.filter((option) => chosen.includes(option.name))) input.options[option.name] = await this.value(option);
  }

  /** Asks the command's confirmation unless its option already gives it, and sets that option. */
  private async confirm(input: AdminInput): Promise<boolean> {
    const confirm = input.command.confirm;

    if (!confirm || AdminInput.filled(input.options[confirm.option]) || input.flag("dry-run")) return true;

    const question = confirm.question.replace(/\{(\w+)\}/g, (_, name: string) => String(input.arguments[name] ?? ""));

    input.options[confirm.option] = await this.cli.confirm(question, false);

    return input.options[confirm.option] === true;
  }

  /** Asks for one option's value in the way its type calls for. */
  async value(option: AdminOption): Promise<string | boolean> {
    if (option.type === "flag") return true;
    if (option.choices) return await this.cli.choice(option.label, option.choices);

    return (await this.cli.ask(option.label, option.default === undefined ? undefined : String(option.default))).trim();
  }
}
