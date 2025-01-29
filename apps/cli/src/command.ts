import { Command, Usage } from "clipanion";

/**
 * Base class for all commands that include aptos-specific pre-flight checks
 * such as authentication, and enforce some common behavior.
 */
export abstract class BaseCommand extends Command {
  // This ensures that all commands have a usage property, which is required by
  // clipanion to be displayed in the help output.
  static usage: Usage = Command.Usage({
    category: "uncategorized",
    description:
      "Please set the usage property for this command in the subclass.",
  });

  // The child implements executeInner while we implement execute to ensure that the
  // child's implementation is preceded by the auth cache stuff.
  async execute(): Promise<number> {
    return this.executeInner();
  }

  // The child implements this.
  abstract executeInner(): Promise<number>;

  constructor() {
    super();
  }
}
