#!/usr/bin/env node
import { Kernel } from "@h3ravel/musket";
import { AdminCommands } from "../../worker/admin/protocol/commands";
import pkg from "../package.json" with { type: "json" };
import { Application } from "./Application";
import { CommandsCommand } from "./commands/CommandsCommand";
import { ForwardedCommand } from "./commands/ForwardedCommand";
import { LoginCommand } from "./commands/LoginCommand";
import { LogoutCommand } from "./commands/LogoutCommand";
import { StatusCommand } from "./commands/StatusCommand";
import { WizardCommand } from "./commands/WizardCommand";

await Kernel.init(new Application(), {
  name: "flyylink-admin",
  logo: "FlyyLink Admin",
  version: pkg.version,
  baseCommands: [LoginCommand, LogoutCommand, StatusCommand, CommandsCommand, WizardCommand, ...AdminCommands.map((definition) => ForwardedCommand.for(definition))],
});
