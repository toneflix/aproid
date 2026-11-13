import { HttpError } from "../http";
import type { Operators } from "./operators";
import { AdminHeaders, AdminSignature } from "./protocol/signature";

/** Checks an operator request's signature, timestamp and nonce, and names who sent it. */
export class AdminAuthenticator {
  constructor(
    private readonly operators: Operators,
    /** The key `ADMIN_BOOTSTRAP_KEY` allows while no operator exists yet. */
    private readonly bootstrapKey: string | undefined,
  ) {}

  /** The actor name the audit log records: an operator's name, or `bootstrap`. */
  async authenticate(request: Request, body: string, now: number): Promise<string> {
    const header = (name: string) => request.headers.get(name) ?? "";
    const key = header(AdminHeaders.key).trim();
    const parts = { method: request.method, path: new URL(request.url).pathname, timestamp: header(AdminHeaders.timestamp), nonce: header(AdminHeaders.nonce), body };

    if (!AdminSignature.isPublicKey(key)) throw AdminAuthenticator.refuse("Missing or invalid operator key.");
    if (!AdminSignature.fresh(parts.timestamp, now * 1000)) throw AdminAuthenticator.refuse("The request time is too far from the server's clock.");
    if (!/^[A-Za-z0-9_-]{16,64}$/.test(parts.nonce)) throw AdminAuthenticator.refuse("Missing or invalid nonce.");
    if (!(await AdminSignature.verify(key, parts, header(AdminHeaders.signature)))) throw AdminAuthenticator.refuse("Invalid signature.");

    const actor = await this.identify(key);

    if (!actor) throw AdminAuthenticator.refuse("This key is not an operator.");
    if (!(await this.operators.claimNonce(parts.nonce, now, 2 * AdminSignature.windowSeconds))) throw AdminAuthenticator.refuse("This request was already used.");
    if (actor !== "bootstrap") await this.operators.used(actor, now);

    return actor;
  }

  private async identify(key: string): Promise<string | null> {
    const operator = await this.operators.findByKey(key);

    if (operator) return operator.revoked_at === null ? operator.name : null;
    if (this.bootstrapKey?.trim() === key && !(await this.operators.any())) return "bootstrap";

    return null;
  }

  private static refuse(message: string): HttpError {
    return new HttpError(401, "not_operator", { message });
  }
}
