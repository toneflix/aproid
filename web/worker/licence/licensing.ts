import { HttpError } from "../http";
import { randomToken, sha256 } from "./crypto";
import type { Account, LicenceStore } from "./store";
import type { TokenKind, TokenSigner } from "./signer";

const day = 24 * 60 * 60;

export interface Machine {
  id: string;
  name: string;
  platform: string;
}

export interface ComputerView {
  machine: string;
  name: string;
  platform: string;
  activatedAt: number;
  seenAt: number;
}

/**
 * The rules of the lifetime licence: one purchase covers an account's computers up to a limit,
 * phones are free, and computers can only be swapped a few times a month.
 */
export class Licensing {
  static readonly maxComputers = 5;
  static readonly removalsPerMonth = 3;
  static readonly trialDays = 14;
  static readonly renewDays = 30;
  static readonly graceDays = 7;

  constructor(
    private readonly store: LicenceStore,
    private readonly signer: TokenSigner,
  ) {}

  /** Activates a computer for a signed-in account and returns its token and refresh secret. */
  async activate(account: Account, machine: Machine, now: number): Promise<{ token: string; secret: string }> {
    if (!(await this.store.hasActiveLicence(account.id))) throw new HttpError(402, "no_licence");

    const active = (await this.store.computers(account.id)).filter((c) => c.removed_at === null);
    const known = active.some((c) => c.machine === machine.id);
    if (!known && active.length >= Licensing.maxComputers) {
      throw new HttpError(409, "computer_limit", { computers: active.map(Licensing.view), limit: Licensing.maxComputers });
    }

    const secret = randomToken();
    await this.store.saveComputer(account.id, machine.id, machine.name, machine.platform, await sha256(secret), now);

    return { token: await this.token("licence", machine.id, now, account.email), secret };
  }

  /** Issues a fresh token to a computer that is still active on a licensed account. */
  async refresh(machine: string, secret: string, now: number): Promise<string> {
    const computer = await this.store.findComputerBySecret(machine, await sha256(secret));
    if (!computer) throw new HttpError(401, "not_activated");

    const account = await this.store.findAccountById(computer.account_id);
    if (!account || !(await this.store.hasActiveLicence(account.id))) throw new HttpError(402, "no_licence");

    await this.store.touchComputer(account.id, machine, now);

    return this.token("licence", machine, now, account.email);
  }

  /** The trial runs from the first time this computer asked, however often it asks again. */
  async trial(machine: string, now: number): Promise<string> {
    const started = await this.store.trialStart(machine, now);
    const ends = started + Licensing.trialDays * day;
    if (ends <= now) throw new HttpError(402, "trial_over");

    return this.signer.sign({ v: 1, kind: "trial", machine, issued: now, renew: ends, expires: ends });
  }

  async computers(account: Account): Promise<ComputerView[]> {
    return (await this.store.computers(account.id)).filter((c) => c.removed_at === null).map(Licensing.view);
  }

  async removalsLeft(account: Account, now: number): Promise<number> {
    const since = now - 30 * day;
    const recent = (await this.store.computers(account.id)).filter((c) => c.removed_at !== null && c.removed_at > since).length;

    return Math.max(0, Licensing.removalsPerMonth - recent);
  }

  async remove(account: Account, machine: string, now: number): Promise<void> {
    if ((await this.removalsLeft(account, now)) === 0) throw new HttpError(429, "removal_limit");

    await this.store.removeComputer(account.id, machine, now);
  }

  private token(kind: TokenKind, machine: string, now: number, email?: string): Promise<string> {
    const renew = now + Licensing.renewDays * day;

    return this.signer.sign({ v: 1, kind, machine, email, issued: now, renew, expires: renew + Licensing.graceDays * day });
  }

  private static view(c: { machine: string; name: string; platform: string; activated_at: number; seen_at: number }): ComputerView {
    return { machine: c.machine, name: c.name, platform: c.platform, activatedAt: c.activated_at, seenAt: c.seen_at };
  }
}
