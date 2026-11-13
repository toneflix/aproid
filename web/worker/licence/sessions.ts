import { HttpError } from "../http";
import { randomToken, sha256 } from "./crypto";
import type { Account, LicenceStore } from "./store";

const cookie = "flyylink_session";
const lifetime = 30 * 24 * 60 * 60;

/** Website sign-ins, kept in an HttpOnly cookie. */
export class Sessions {
  constructor(
    private readonly db: D1Database,
    private readonly store: LicenceStore,
  ) {}

  async start(account: Account, now: number): Promise<string> {
    const token = randomToken();
    await this.db.prepare("INSERT INTO sessions (token_hash, account_id, expires_at) VALUES (?, ?, ?)").bind(await sha256(token), account.id, now + lifetime).run();

    return `${cookie}=${token}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=${lifetime}`;
  }

  async account(request: Request, now: number): Promise<Account> {
    const token = Sessions.token(request);
    const row = token
      ? await this.db.prepare("SELECT account_id FROM sessions WHERE token_hash = ? AND expires_at > ?").bind(await sha256(token), now).first<{ account_id: string }>()
      : null;
    const account = row ? await this.store.findAccountById(row.account_id) : null;
    if (!account) throw new HttpError(401, "signed_out");

    return account;
  }

  async end(request: Request): Promise<string> {
    const token = Sessions.token(request);
    if (token) await this.db.prepare("DELETE FROM sessions WHERE token_hash = ?").bind(await sha256(token)).run();

    return `${cookie}=; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=0`;
  }

  private static token(request: Request): string | undefined {
    const header = request.headers.get("Cookie") ?? "";

    return header
      .split(";")
      .map((part) => part.trim().split("="))
      .find(([name]) => name === cookie)?.[1];
  }
}
