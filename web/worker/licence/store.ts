export interface Account {
  id: string;
  email: string;
}

export interface Computer {
  machine: string;
  name: string;
  platform: string;
  secret_hash: string;
  activated_at: number;
  seen_at: number;
  removed_at: number | null;
}

/** Reads and writes the licence database. Holds no rules; `Licensing` does. */
export class LicenceStore {
  constructor(private readonly db: D1Database) {}

  findAccount(email: string): Promise<Account | null> {
    return this.db.prepare("SELECT id, email FROM accounts WHERE email = ?").bind(email).first<Account>();
  }

  findAccountById(id: string): Promise<Account | null> {
    return this.db.prepare("SELECT id, email FROM accounts WHERE id = ?").bind(id).first<Account>();
  }

  async accountFor(email: string, now: number): Promise<Account> {
    await this.db
      .prepare("INSERT INTO accounts (id, email, created_at) VALUES (?, ?, ?) ON CONFLICT (email) DO NOTHING")
      .bind(crypto.randomUUID(), email, now)
      .run();

    return (await this.findAccount(email))!;
  }

  async addLicence(accountId: string, provider: string, orderId: string, now: number): Promise<void> {
    await this.db
      .prepare(
        "INSERT INTO licences (id, account_id, provider, order_id, status, created_at) VALUES (?, ?, ?, ?, 'active', ?) " +
          "ON CONFLICT (provider, order_id) DO NOTHING",
      )
      .bind(crypto.randomUUID(), accountId, provider, orderId, now)
      .run();
  }

  async setLicenceStatus(provider: string, orderId: string, status: "active" | "revoked"): Promise<void> {
    await this.db.prepare("UPDATE licences SET status = ? WHERE provider = ? AND order_id = ?").bind(status, provider, orderId).run();
  }

  async hasActiveLicence(accountId: string): Promise<boolean> {
    const row = await this.db
      .prepare("SELECT 1 AS found FROM licences WHERE account_id = ? AND status = 'active' LIMIT 1")
      .bind(accountId)
      .first();

    return row !== null;
  }

  async computers(accountId: string): Promise<Computer[]> {
    const { results } = await this.db
      .prepare("SELECT * FROM computers WHERE account_id = ? ORDER BY activated_at")
      .bind(accountId)
      .all<Computer>();

    return results;
  }

  async saveComputer(accountId: string, machine: string, name: string, platform: string, secretHash: string, now: number): Promise<void> {
    await this.db
      .prepare(
        "INSERT INTO computers (account_id, machine, name, platform, secret_hash, activated_at, seen_at) VALUES (?, ?, ?, ?, ?, ?, ?) " +
          "ON CONFLICT (account_id, machine) DO UPDATE SET name = excluded.name, platform = excluded.platform, " +
          "secret_hash = excluded.secret_hash, seen_at = excluded.seen_at, removed_at = NULL, " +
          "activated_at = CASE WHEN computers.removed_at IS NULL THEN computers.activated_at ELSE excluded.activated_at END",
      )
      .bind(accountId, machine, name, platform, secretHash, now, now)
      .run();
  }

  async touchComputer(accountId: string, machine: string, now: number): Promise<void> {
    await this.db.prepare("UPDATE computers SET seen_at = ? WHERE account_id = ? AND machine = ?").bind(now, accountId, machine).run();
  }

  async removeComputer(accountId: string, machine: string, now: number): Promise<void> {
    await this.db
      .prepare("UPDATE computers SET removed_at = ? WHERE account_id = ? AND machine = ? AND removed_at IS NULL")
      .bind(now, accountId, machine)
      .run();
  }

  findComputerBySecret(machine: string, secretHash: string): Promise<(Computer & { account_id: string }) | null> {
    return this.db
      .prepare("SELECT * FROM computers WHERE machine = ? AND secret_hash = ? AND removed_at IS NULL")
      .bind(machine, secretHash)
      .first();
  }

  async trialStart(machine: string, now: number): Promise<number> {
    await this.db.prepare("INSERT INTO trials (machine, started_at) VALUES (?, ?) ON CONFLICT (machine) DO NOTHING").bind(machine, now).run();
    const row = await this.db.prepare("SELECT started_at FROM trials WHERE machine = ?").bind(machine).first<{ started_at: number }>();

    return row!.started_at;
  }
}
