import { readdirSync, readFileSync } from "node:fs";
import { DatabaseSync, type SQLInputValue } from "node:sqlite";
import path from "node:path";

/** Enough of D1 for tests, on an in-memory SQLite database with the real migrations applied. */
class Statement {
  constructor(
    private readonly db: DatabaseSync,
    private readonly sql: string,
    private readonly values: SQLInputValue[] = [],
  ) {}

  bind(...values: unknown[]): Statement {
    return new Statement(this.db, this.sql, values.map((value) => (value === undefined ? null : (value as SQLInputValue))));
  }

  async first<T>(): Promise<T | null> {
    return (this.db.prepare(this.sql).get(...this.values) as T | undefined) ?? null;
  }

  async all<T>(): Promise<{ results: T[] }> {
    return { results: this.db.prepare(this.sql).all(...this.values) as T[] };
  }

  async run(): Promise<{ meta: { changes: number } }> {
    const result = this.db.prepare(this.sql).run(...this.values);

    return { meta: { changes: Number(result.changes) } };
  }
}

export function testDatabase(): D1Database {
  const db = new DatabaseSync(":memory:");
  const migrations = path.join(import.meta.dirname, "../../migrations");

  for (const file of readdirSync(migrations).sort()) db.exec(readFileSync(path.join(migrations, file), "utf8"));

  return {
    prepare: (sql: string) => new Statement(db, sql),
    batch: async (statements: Statement[]) => Promise.all(statements.map((statement) => statement.run())),
  } as unknown as D1Database;
}
