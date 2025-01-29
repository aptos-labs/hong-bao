export function getUsageCategoryFromPaths(
  paths: string[][],
): string | undefined {
  // Get the longest path and determine the usage category from it
  if (paths.length > 0) {
    const longestPath = paths.reduce((a, b) => (a.length > b.length ? a : b));
    if (longestPath.length == 0) {
      return undefined; // it's empty
    } else if (longestPath.length < 1) {
      return longestPath[0];
    } else {
      // slice it
      const firstPathSlice = longestPath.slice(0, -1);
      return firstPathSlice.join(" ");
    }
  }
  return undefined;
}

/**
 * Takes in a command option like `--my-option=value` and returns a pretty printed version like `--my-option="value"`
 */
export function prettyPrintCommandOption(op: string): string {
  const parts = op.split("=");
  if (parts.length > 1) {
    const key = parts[0];
    const value = parts.slice(1).join("=");
    return `${key}="${value}"`;
  }
  return op;
}
