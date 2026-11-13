import { AdminSignature } from "../../../worker/admin/protocol/signature";
import { AdminClient } from "../AdminClient";
import { CliCommand } from "../CliCommand";
import { ConfigStore } from "../ConfigStore";

/** Shows which server this machine is connected to and whether it answers. */
export class StatusCommand extends CliCommand {
  signature = "status";

  description = "Show the server this machine is connected to";

  async handle() {
    const config = await new ConfigStore().load();

    if (!config) {
      this.error("Not connected. Run flyylink-cli login first.");
      process.exitCode = 1;

      return;
    }

    const reachable = await new AdminClient(config).reachable();

    this.fields([
      ["Server", config.url],
      ["Fingerprint", await AdminSignature.fingerprint(config.publicKey)],
      ["Reachable", reachable ? this.paint("yes", "green") : this.paint("no", "red")],
    ]);
  }
}
