import { HttpError } from "../http";
import type { Router } from "../router";
import type { AuditLog } from "./audit";
import type { AdminAuthenticator } from "./authenticator";
import type { CommandGroup, CommandHandler } from "./commands/group";
import { AdminCommands } from "./protocol/commands";
import { AdminInput } from "./protocol/input";
import { Reply } from "./protocol/result";

/** Readable text for the error codes the licence code throws. */
const errors: Record<string, string> = {
  bad_email: "That is not an email address.",
};

/** `POST /api/admin/run`: runs one admin command for a signed-in operator and answers with its result. */
export class AdminApi {
  static readonly maxBody = 20_000;

  private readonly handlers = new Map<string, CommandHandler>();

  constructor(
    private readonly authenticator: AdminAuthenticator,
    private readonly audit: AuditLog,
    groups: CommandGroup[],
  ) {
    for (const group of groups) {
      for (const [name, handler] of Object.entries(group.handlers())) this.handlers.set(name, handler);
    }
  }

  register(router: Router): void {
    router.post("/api/admin/run", (request) => this.run(request, Math.floor(Date.now() / 1000)));
  }

  /** Admin commands without a handler, which should always be none. */
  unhandled(): string[] {
    return AdminCommands.map((command) => command.name).filter((name) => !this.handlers.has(name));
  }

  async run(request: Request, now: number): Promise<Response> {
    const body = await request.text();
    if (body.length > AdminApi.maxBody) throw new HttpError(413, "too_large");

    const actor = await this.authenticator.authenticate(request, body, now);
    const input = AdminInput.fromRequest(AdminApi.parse(body));
    if (!input) throw new HttpError(400, "bad_request", { message: "That is not an admin command." });

    const reply = new Reply();
    const problems = input.problems();

    if (problems.length) {
      problems.forEach((problem) => reply.error(problem));
      reply.info(`Usage: flyylink-admin ${input.usage()}`);
    } else {
      await this.handle(input, reply, actor, now);
    }

    await this.audit.record(actor, input.toRequest(), reply.toJSON().exit, now);

    return Response.json(reply.toJSON(), { headers: { "Cache-Control": "no-store" } });
  }

  private async handle(input: AdminInput, reply: Reply, actor: string, now: number): Promise<void> {
    try {
      await this.handlers.get(input.command.name)!({ input, reply, actor, now });
    } catch (error) {
      if (!(error instanceof HttpError)) throw error;

      reply.error(errors[error.code] ?? `The server refused it: ${error.code}.`);
    }
  }

  private static parse(body: string): unknown {
    try {
      return JSON.parse(body);
    } catch {
      return null;
    }
  }
}
