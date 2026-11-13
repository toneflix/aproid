import { AdminSignature } from "../../../worker/admin/protocol/signature";
import { AdminClient } from "../AdminClient";
import { CliCommand } from "../CliCommand";
import { ConfigStore } from "../ConfigStore";

/** Saves the site's URL and makes this machine's operator key, then says how to allow the key on the server. */
export class LoginCommand extends CliCommand {
  signature = `login
    {--url= : The site, such as https://flyylink.toneflix.net}
    {--new-key : Replace this machine's key with a new one}
  `;

  description = "Connect this machine to the FlyyLink server";

  async handle() {
    const url = ConfigStore.normalizeUrl(String(this.option("url") || ConfigStore.defaultUrl));
    const store = new ConfigStore();
    const saved = await store.load();

    if (!url) {
      this.error("Pass --url with the site address, starting with https://");
      process.exitCode = 1;

      return;
    }

    const keys = saved && !this.option("newKey") ? saved : await AdminSignature.generateKeys();
    const config = { url, publicKey: keys.publicKey, privateKey: keys.privateKey };

    await store.save(config);

    this.success(`Saved to ${store.file}`);
    this.fields([
      ["Public key", config.publicKey],
      ["Fingerprint", await AdminSignature.fingerprint(config.publicKey)],
    ]);
    this.newLine();
    this.line("Ask an operator to allow this key with");
    this.line(this.paint(`  flyylink-cli operators:add <your name> ${config.publicKey}`, "cyan"));
    this.line("or, for the first operator, set it as the worker's ADMIN_BOOTSTRAP_KEY secret.");

    if (!(await new AdminClient(config).reachable())) {
      this.newLine();
      this.warn(`${url} did not answer.`);
    }
  }
}
