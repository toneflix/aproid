import { HttpError } from "../http";
import { hmac, sameText } from "./crypto";
import type { Mailer } from "./mailer";

const codeLifetime = 10 * 60;
const sendWindow = 60 * 60;
const sendsPerWindow = 5;
const attemptsPerCode = 5;

interface CodeRow {
  code_hash: string;
  expires_at: number;
  attempts: number;
  window_start: number;
  sends: number;
}

/** Six-digit codes sent by email, which is how people sign in on the site and in the apps. */
export class SignInCodes {
  constructor(
    private readonly db: D1Database,
    private readonly mailer: Mailer,
    private readonly secret: string,
  ) {}

  static normalise(email: string): string {
    const clean = email.trim().toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(clean) || clean.length > 254) throw new HttpError(400, "bad_email");

    return clean;
  }

  async send(email: string, now: number): Promise<void> {
    const row = await this.row(email);
    const fresh = !row || row.window_start + sendWindow <= now;
    if (!fresh && row.sends >= sendsPerWindow) throw new HttpError(429, "too_many_codes");

    const code = String(crypto.getRandomValues(new Uint32Array(1))[0] % 1_000_000).padStart(6, "0");
    await this.db
      .prepare(
        "INSERT INTO codes (email, code_hash, expires_at, attempts, window_start, sends) VALUES (?, ?, ?, 0, ?, 1) " +
          "ON CONFLICT (email) DO UPDATE SET code_hash = excluded.code_hash, expires_at = excluded.expires_at, attempts = 0, " +
          "window_start = CASE WHEN ? THEN excluded.window_start ELSE codes.window_start END, " +
          "sends = CASE WHEN ? THEN 1 ELSE codes.sends + 1 END",
      )
      .bind(email, await this.hash(email, code), now + codeLifetime, now, fresh ? 1 : 0, fresh ? 1 : 0)
      .run();

    await this.mailer.send(email, `${code} is your Aproid code`, `Your Aproid sign-in code is ${code}.\n\nIt works for 10 minutes.`);
  }

  /** Uses up the code when it matches. */
  async verify(email: string, code: string, now: number): Promise<void> {
    const row = await this.row(email);
    if (!row || row.expires_at <= now || row.attempts >= attemptsPerCode) throw new HttpError(401, "bad_code");

    if (!sameText(row.code_hash, await this.hash(email, code.trim()))) {
      await this.db.prepare("UPDATE codes SET attempts = attempts + 1 WHERE email = ?").bind(email).run();
      throw new HttpError(401, "bad_code");
    }

    await this.db.prepare("UPDATE codes SET expires_at = 0 WHERE email = ?").bind(email).run();
  }

  private row(email: string): Promise<CodeRow | null> {
    return this.db.prepare("SELECT * FROM codes WHERE email = ?").bind(email).first<CodeRow>();
  }

  private hash(email: string, code: string): Promise<string> {
    return hmac(this.secret, `${email}:${code}`);
  }
}
