import type { AuditLog } from "../audit";
import type { Operators } from "../operators";
import { AdminSignature } from "../protocol/signature";
import { CommandGroup, type CommandContext } from "./group";

/** Who may run admin commands, and what they ran. */
export class OperatorCommands extends CommandGroup {
  constructor(
    private readonly operators: Operators,
    private readonly audit: AuditLog,
  ) {
    super();
  }

  handlers() {
    return {
      "operators:add": (context: CommandContext) => this.add(context),
      "operators:list": (context: CommandContext) => this.list(context),
      "operators:revoke": (context: CommandContext) => this.revoke(context),
      "audit:list": (context: CommandContext) => this.auditList(context),
    };
  }

  private async add({ input, reply, actor, now }: CommandContext): Promise<void> {
    const name = input.argument("name").toLowerCase();
    const key = input.argument("key");

    if (!/^[a-z0-9][a-z0-9._-]{0,39}$/.test(name) || name === "bootstrap") {
      reply.error("Use a name of letters, digits, dots, dashes or underscores, such as obi. bootstrap is taken.");

      return;
    }

    if (!AdminSignature.isPublicKey(key)) {
      reply.error("That is not a public key. Copy the one flyylink-admin login printed.");

      return;
    }

    if (await this.operators.findByName(name)) {
      reply.error(`There is already an operator called ${name}.`);

      return;
    }

    if (await this.operators.findByKey(key)) {
      reply.error("That key already belongs to an operator.");

      return;
    }

    await this.operators.add(name, key, actor, now);

    reply.success(`${name} is an operator now (${await AdminSignature.fingerprint(key)}).`);
  }

  private async list({ input, reply }: CommandContext): Promise<void> {
    const paging = OperatorCommands.paging(input);
    const found = await this.operators.list(paging);
    const fingerprints = new Map(await Promise.all(found.rows.map(async (operator) => [operator.name, await AdminSignature.fingerprint(operator.public_key)] as const)));

    reply.listing(
      OperatorCommands.listing(
        found,
        paging,
        [
          { key: "name", label: "Name" },
          { key: "status", label: "Status" },
          { key: "fingerprint", label: "Key" },
          { key: "added", label: "Added" },
          { key: "used", label: "Last used" },
        ],
        (operator) => ({
          name: operator.name,
          status: operator.revoked_at ? "revoked" : "active",
          fingerprint: fingerprints.get(operator.name) ?? "",
          added: `${OperatorCommands.when(operator.created_at)} by ${operator.created_by}`,
          used: OperatorCommands.when(operator.last_used_at),
        }),
        "No operators yet.",
      ),
    );
  }

  private async revoke({ input, reply, now }: CommandContext): Promise<void> {
    const operator = await this.operators.findByName(input.argument("name").toLowerCase());

    if (!operator || operator.revoked_at) {
      reply.error(`No active operator is called ${input.argument("name")}.`);

      return;
    }

    await this.operators.revoke(operator.name, now);

    reply.success(`Revoked ${operator.name}'s key.`);
  }

  private async auditList({ input, reply }: CommandContext): Promise<void> {
    const paging = OperatorCommands.paging(input);
    const found = await this.audit.list(input.text("actor").toLowerCase(), paging);

    reply.listing(
      OperatorCommands.listing(
        found,
        paging,
        [
          { key: "at", label: "When" },
          { key: "actor", label: "Who" },
          { key: "command", label: "Command" },
          { key: "input", label: "Input" },
          { key: "result", label: "Result" },
        ],
        (entry) => ({ at: OperatorCommands.when(entry.created_at), actor: entry.actor, command: entry.command, input: entry.input, result: entry.exit === 0 ? "ok" : "failed" }),
        "Nothing in the audit log yet.",
      ),
    );
  }
}
