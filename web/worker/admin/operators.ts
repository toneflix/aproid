export interface Operator {
  name: string;
  public_key: string;
  created_by: string;
  created_at: number;
  last_used_at: number | null;
  revoked_at: number | null;
}

/** The people allowed to run admin commands, each known by the Ed25519 key their CLI made. */
export class Operators {
  constructor(private readonly db: D1Database) {}

  findByKey(publicKey: string): Promise<Operator | null> {
    return this.db.prepare("SELECT * FROM operators WHERE public_key = ?").bind(publicKey).first<Operator>();
  }

  findByName(name: string): Promise<Operator | null> {
    return this.db.prepare("SELECT * FROM operators WHERE name = ?").bind(name).first<Operator>();
  }

  async any(): Promise<boolean> {
    return (await this.db.prepare("SELECT 1 AS found FROM operators LIMIT 1").first()) !== null;
  }

  async list(paging: { offset: number; limit: number }): Promise<{ rows: Operator[]; total: number }> {
    const { results } = await this.db.prepare("SELECT * FROM operators ORDER BY created_at, name LIMIT ? OFFSET ?").bind(paging.limit, paging.offset).all<Operator>();
    const count = await this.db.prepare("SELECT COUNT(*) AS n FROM operators").first<{ n: number }>();

    return { rows: results, total: count?.n ?? 0 };
  }

  async add(name: string, publicKey: string, actor: string, now: number): Promise<void> {
    await this.db.prepare("INSERT INTO operators (name, public_key, created_by, created_at) VALUES (?, ?, ?, ?)").bind(name, publicKey, actor, now).run();
  }

  async revoke(name: string, now: number): Promise<void> {
    await this.db.prepare("UPDATE operators SET revoked_at = ? WHERE name = ? AND revoked_at IS NULL").bind(now, name).run();
  }

  async used(name: string, now: number): Promise<void> {
    await this.db.prepare("UPDATE operators SET last_used_at = ? WHERE name = ?").bind(now, name).run();
  }

  /** Records a request's nonce. False when it was used before, which means the request is a replay. */
  async claimNonce(nonce: string, now: number, lifetime: number): Promise<boolean> {
    await this.db.prepare("DELETE FROM admin_nonces WHERE expires_at < ?").bind(now).run();
    const result = await this.db.prepare("INSERT INTO admin_nonces (nonce, expires_at) VALUES (?, ?) ON CONFLICT (nonce) DO NOTHING").bind(nonce, now + lifetime).run();

    return (result.meta.changes ?? 0) > 0;
  }
}
