import { randomBytes } from "node:crypto";
import type { AdminRequest } from "../../worker/admin/protocol/input";
import type { AdminResult } from "../../worker/admin/protocol/result";
import { AdminHeaders, AdminSignature } from "../../worker/admin/protocol/signature";
import type { CliConfig } from "./ConfigStore";

/** Talks to the site's admin API as this machine's operator. */
export class AdminClient {
  static readonly path = "/api/admin/run";

  constructor(
    private readonly config: CliConfig,
    private readonly fetcher: typeof fetch = fetch,
  ) {}

  /** Runs the command on the server. A refusal or network failure comes back as a failed result. */
  async run(request: AdminRequest): Promise<AdminResult> {
    const body = JSON.stringify(request);
    const timestamp = String(Math.floor(Date.now() / 1000));
    const nonce = randomBytes(18).toString("base64url");
    const signature = await AdminSignature.sign(this.config.privateKey, { method: "POST", path: AdminClient.path, timestamp, nonce, body });

    let response: Response;

    try {
      response = await this.fetcher(`${this.config.url}${AdminClient.path}`, {
        method: "POST",
        body,
        headers: {
          "content-type": "application/json",
          [AdminHeaders.key]: this.config.publicKey,
          [AdminHeaders.timestamp]: timestamp,
          [AdminHeaders.nonce]: nonce,
          [AdminHeaders.signature]: signature,
        },
      });
    } catch (error) {
      return AdminClient.failure(`Could not reach ${this.config.url}: ${AdminClient.reason(error)}`);
    }

    if (!response.ok) return AdminClient.failure(`The server refused the command: ${await AdminClient.message(response)}`);

    try {
      return (await response.json()) as AdminResult;
    } catch {
      return AdminClient.failure("The server sent an answer flyylink-admin could not read.");
    }
  }

  /** Whether the site answers at all. */
  async reachable(): Promise<boolean> {
    try {
      return (await this.fetcher(this.config.url, { method: "HEAD" })).ok;
    } catch {
      return false;
    }
  }

  private static failure(text: string): AdminResult {
    return { exit: 1, notes: [{ level: "error", text }] };
  }

  private static async message(response: Response): Promise<string> {
    const text = await response.text().catch(() => "");

    try {
      const body = JSON.parse(text) as { message?: string; error?: string };

      return body.message ?? body.error ?? `HTTP ${response.status}`;
    } catch {
      return text.trim().slice(0, 200) || `HTTP ${response.status}`;
    }
  }

  private static reason(error: unknown): string {
    const cause = error instanceof Error && error.cause instanceof Error ? error.cause : error;

    return cause instanceof Error ? cause.message : String(cause);
  }
}
