import { type AdminCommand, type AdminOption, findAdminCommand } from "./commands";

export type InputValue = string | number | boolean | null | undefined;

/** The body of `POST /api/admin/run`. */
export interface AdminRequest {
  command: string;
  arguments: Record<string, string>;
  options: Record<string, string | boolean>;
}

/** The arguments and options given to one admin command, checked against its definition. */
export class AdminInput {
  readonly arguments: Record<string, InputValue>;
  readonly options: Record<string, InputValue>;

  constructor(
    readonly command: AdminCommand,
    args: Record<string, InputValue> = {},
    options: Record<string, InputValue> = {},
  ) {
    this.arguments = { ...args };
    this.options = { ...options };
  }

  /** The input a request asks for, or null when it names no admin command or is not shaped like one. */
  static fromRequest(body: unknown): AdminInput | null {
    const request = (body ?? {}) as Partial<AdminRequest>;
    const command = typeof request.command === "string" ? findAdminCommand(request.command) : null;

    if (!command || !AdminInput.record(request.arguments) || !AdminInput.record(request.options)) return null;

    const args = Object.fromEntries(command.arguments.map((argument) => [argument.name, request.arguments![argument.name]]));
    const options = Object.fromEntries(command.options.map((option) => [option.name, request.options![option.name]]));

    return new AdminInput(command, args, options);
  }

  static filled(value: InputValue): boolean {
    if (typeof value === "boolean") return value;

    return value !== null && value !== undefined && String(value).trim() !== "";
  }

  /** Whether any option was set to something other than its default. */
  optionsGiven(): boolean {
    return this.command.options.some((option) => AdminInput.filled(this.options[option.name]) && this.options[option.name] !== option.default);
  }

  /** The required arguments that were not given. */
  missing() {
    return this.command.arguments.filter((argument) => argument.required !== false && !AdminInput.filled(this.arguments[argument.name]));
  }

  /** What is wrong with the input, as messages for the operator. Empty when it can run. */
  problems(): string[] {
    const problems = this.missing().map((argument) => `Missing <${argument.name}>: ${argument.description.toLowerCase()}.`);

    for (const argument of this.command.arguments) {
      const value = this.arguments[argument.name];

      if (argument.choices && AdminInput.filled(value) && !argument.choices.includes(String(value))) {
        problems.push(`<${argument.name}> must be one of ${argument.choices.join(", ")}.`);
      }
    }

    for (const option of this.command.options) problems.push(...AdminInput.optionProblems(option, this.options[option.name]));

    return problems;
  }

  /** How to run the command, for messages that refuse it. */
  usage(): string {
    const args = this.command.arguments.map((argument) => (argument.required === false ? `[${argument.name}]` : `<${argument.name}>`));

    return [this.command.name, ...args, "[options]"].join(" ");
  }

  /** The request that runs this input, leaving out options that are unset or at their default. */
  toRequest(): AdminRequest {
    const args: Record<string, string> = {};
    const options: Record<string, string | boolean> = {};

    for (const argument of this.command.arguments) {
      const value = this.arguments[argument.name];

      if (AdminInput.filled(value)) args[argument.name] = String(value).trim();
    }

    for (const option of this.command.options) {
      const value = this.options[option.name];

      if (!AdminInput.filled(value) || value === option.default) continue;

      options[option.name] = option.type === "flag" ? true : String(value).trim();
    }

    return { command: this.command.name, arguments: args, options };
  }

  /** An argument's value as given, trimmed, or an empty string. */
  argument(name: string): string {
    return AdminInput.filled(this.arguments[name]) ? String(this.arguments[name]).trim() : "";
  }

  /** An option's value, or its default, or an empty string. */
  text(name: string): string {
    const value = this.options[name];

    if (AdminInput.filled(value) && typeof value !== "boolean") return String(value).trim();

    const fallback = this.command.options.find((option) => option.name === name)?.default;

    return fallback === undefined ? "" : String(fallback);
  }

  number(name: string): number {
    return Number(this.text(name)) || 0;
  }

  flag(name: string): boolean {
    const value = this.options[name];

    return value === true || value === "true";
  }

  private static optionProblems(option: AdminOption, value: InputValue): string[] {
    if (!AdminInput.filled(value)) return [];
    if (option.type === "flag") return value === true || value === "true" ? [] : [`--${option.name} takes no value.`];
    if (option.choices && !option.choices.includes(String(value))) return [`--${option.name} must be one of ${option.choices.join(", ")}.`];
    if (option.type === "number" && !/^\d+$/.test(String(value).trim())) return [`--${option.name} must be a whole number.`];

    return [];
  }

  private static record(value: unknown): boolean {
    return (
      typeof value === "object" &&
      value !== null &&
      !Array.isArray(value) &&
      Object.values(value).every((entry) => (typeof entry === "string" && entry.length <= 5000) || typeof entry === "boolean")
    );
  }
}
