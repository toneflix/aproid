import { CliCommand } from "../CliCommand";
import { ConfigStore } from "../ConfigStore";

/** Deletes the saved site URL and this machine's operator key. */
export class LogoutCommand extends CliCommand {
  signature = "logout";

  description = "Forget the server and this machine's key";

  async handle() {
    const store = new ConfigStore();

    await store.clear();

    this.success(`Removed ${store.file}. Revoke the key with operators:revoke if it should stop working.`);
  }
}
