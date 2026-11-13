import { Command } from "@h3ravel/musket";
import { Logger, type LoggerChalk } from "@h3ravel/shared";

/** A flyylink-admin command, whose messages keep their colons instead of turning the text before one into a badge. */
export abstract class CliCommand extends Command {
  override info(message: string): this {
    Logger.info(message, false, true);

    return this;
  }

  override success(message: string): this {
    Logger.success(message, false, true);

    return this;
  }

  override warn(message: string): this {
    Logger.warn(message, false, true);

    return this;
  }

  override error(message: string): this {
    Logger.error(message, false, true);

    return this;
  }

  /** Whether the command may ask questions: on a terminal, without `--no-interaction`. */
  interactive(): boolean {
    return Boolean(process.stdin.isTTY && process.stdout.isTTY) && !this.isNonInteractive();
  }

  /** The text in the given color, for building a line. */
  paint(text: string, color: LoggerChalk): string {
    return Logger.log(text, color, false) as string;
  }

  /** Prints label and value pairs, one per line, with the labels aligned and dimmed. */
  fields(pairs: [string, string][]): this {
    const width = Math.max(...pairs.map(([label]) => label.length));

    for (const [label, value] of pairs) this.line(`${this.paint(label.padEnd(width), "gray")}  ${value}`);

    return this;
  }
}
