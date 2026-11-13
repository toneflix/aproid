import { chmod, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import path from "node:path";
import { AdminSignature } from "../../worker/admin/protocol/signature";

/** What `flyylink-cli login` saves: the site's URL and this machine's operator key pair. */
export interface CliConfig {
  url: string;
  publicKey: string;
  privateKey: string;
}

/** The operator's saved login, kept in a file only its owner can read. */
export class ConfigStore {
  static readonly defaultUrl = "https://flyylink.toneflix.net";

  constructor(readonly file = ConfigStore.defaultFile()) {}

  /** `FLYYLINK_CLI_CONFIG`, or `flyylink-cli/config.json` in the user's config directory. */
  static defaultFile(): string {
    if (process.env.FLYYLINK_CLI_CONFIG) return process.env.FLYYLINK_CLI_CONFIG;

    const base = process.env.XDG_CONFIG_HOME || path.join(homedir(), ".config");

    return path.join(base, "flyylink-cli", "config.json");
  }

  /** The URL without a trailing slash, or null when it is not an http or https URL. */
  static normalizeUrl(text: string): string | null {
    try {
      const url = new URL(text.trim());

      if (!["http:", "https:"].includes(url.protocol)) return null;

      return url.toString().replace(/\/+$/, "");
    } catch {
      return null;
    }
  }

  async load(): Promise<CliConfig | null> {
    try {
      const saved = JSON.parse(await readFile(this.file, "utf8")) as Partial<CliConfig>;

      if (!saved.url || !saved.privateKey || !AdminSignature.isPublicKey(saved.publicKey ?? "")) return null;

      return saved as CliConfig;
    } catch {
      return null;
    }
  }

  async save(config: CliConfig): Promise<void> {
    await mkdir(path.dirname(this.file), { recursive: true, mode: 0o700 });
    await writeFile(this.file, `${JSON.stringify(config, null, 2)}\n`, { mode: 0o600 });
    await chmod(this.file, 0o600);
  }

  async clear(): Promise<void> {
    await rm(this.file, { force: true });
  }
}
