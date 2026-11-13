import type { AdminRequest } from "./protocol/input";

export interface AuditEntry {
  id: number;
  actor: string;
  command: string;
  input: string;
  exit: number;
  created_at: number;
}

/** Every admin command run, who ran it and whether it worked. */
export class AuditLog {
  constructor(private readonly db: D1Database) {}

  async record(actor: string, request: AdminRequest, exit: number, now: number): Promise<void> {
    await this.db
      .prepare("INSERT INTO admin_audit (actor, command, input, exit, created_at) VALUES (?, ?, ?, ?, ?)")
      .bind(actor, request.command, JSON.stringify({ arguments: request.arguments, options: request.options }), exit, now)
      .run();
  }

  async list(actor: string, paging: { offset: number; limit: number }): Promise<{ rows: AuditEntry[]; total: number }> {
    const where = actor ? "WHERE actor = ?" : "";
    const binds = actor ? [actor] : [];
    const { results } = await this.db
      .prepare(`SELECT * FROM admin_audit ${where} ORDER BY id DESC LIMIT ? OFFSET ?`)
      .bind(...binds, paging.limit, paging.offset)
      .all<AuditEntry>();
    const count = await this.db.prepare(`SELECT COUNT(*) AS n FROM admin_audit ${where}`).bind(...binds).first<{ n: number }>();

    return { rows: results, total: count?.n ?? 0 };
  }
}
