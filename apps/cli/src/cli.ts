#!/usr/bin/env -S npx tsx --no-warnings

// Import all the commands.
import { Cli, Builtins } from "clipanion";
import { commands as reclaimCommands } from "./reclaim/index.js";

const [node, app, ...args] = process.argv;

const cli = new Cli({
  enableColors: true,
  enableCapture: true,
  // We override this so in the help text it shows how to invoke this program.
  binaryName: `pnpm cli`,
  binaryLabel: `Shepherd platform TS CLI`,
  binaryVersion: `0.0.1`,
});

export let commands = [
  Builtins.DefinitionsCommand,
  Builtins.HelpCommand,
  Builtins.VersionCommand,
  ...reclaimCommands,
];

commands.map((cmd) => cli.register(cmd));
cli.runExit(args);
