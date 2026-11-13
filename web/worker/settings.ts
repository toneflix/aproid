import { SettingDefinitions, type SettingKey } from "./admin/protocol/settings";

export interface SettingView {
  key: SettingKey;
  label: string;
  value: string;
  fallback: string;
  changed: boolean;
}

/** Settings operators change with `settings:set`, kept in D1, each falling back to the worker's default. */
export class Settings {
  private stored?: Promise<Map<string, string>>;

  constructor(
    private readonly db: D1Database,
    private readonly defaults: Record<SettingKey, string>,
  ) {}

  async get(key: SettingKey): Promise<string> {
    return (await this.load()).get(key) ?? this.defaults[key];
  }

  async number(key: SettingKey): Promise<number> {
    return Number(await this.get(key));
  }

  async list(key: SettingKey): Promise<string[]> {
    return (await this.get(key))
      .split(",")
      .map((entry) => entry.trim().toLowerCase())
      .filter(Boolean);
  }

  async all(): Promise<SettingView[]> {
    const stored = await this.load();

    return SettingDefinitions.map(({ key, label }) => ({
      key,
      label,
      value: stored.get(key) ?? this.defaults[key],
      fallback: this.defaults[key],
      changed: stored.has(key),
    }));
  }

  async set(key: SettingKey, value: string, now: number): Promise<void> {
    await this.db
      .prepare("INSERT INTO settings (key, value, updated_at) VALUES (?, ?, ?) ON CONFLICT (key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at")
      .bind(key, value, now)
      .run();
    this.stored = undefined;
  }

  async unset(key: SettingKey): Promise<void> {
    await this.db.prepare("DELETE FROM settings WHERE key = ?").bind(key).run();
    this.stored = undefined;
  }

  private load(): Promise<Map<string, string>> {
    this.stored ??= this.db
      .prepare("SELECT key, value FROM settings")
      .all<{ key: string; value: string }>()
      .then(({ results }) => new Map(results.map((row) => [row.key, row.value])));

    return this.stored;
  }
}
