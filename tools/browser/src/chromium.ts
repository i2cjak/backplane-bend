// Finding a Chromium to drive. Order: $BACKPLANE_CHROMIUM, an installed
// Chrome/Chromium, then Playwright's own downloads (newest revision first,
// the small headless shell before the full browser).

import { existsSync, readdirSync } from "node:fs";
import { homedir, platform } from "node:os";
import { delimiter, join } from "node:path";

const SYSTEM_NAMES = [
  "google-chrome-stable",
  "google-chrome",
  "chromium",
  "chromium-browser",
  "chrome",
];

const SYSTEM_PATHS = [
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/Applications/Chromium.app/Contents/MacOS/Chromium",
  "/opt/google/chrome/chrome",
  "/snap/bin/chromium",
];

function onPath(name: string): string | null {
  for (const dir of (process.env.PATH ?? "").split(delimiter)) {
    if (!dir) continue;
    const p = join(dir, name);
    if (existsSync(p)) return p;
  }
  return null;
}

function playwrightRoot(): string {
  if (process.env.PLAYWRIGHT_BROWSERS_PATH) return process.env.PLAYWRIGHT_BROWSERS_PATH;
  if (platform() === "darwin") return join(homedir(), "Library", "Caches", "ms-playwright");
  return join(homedir(), ".cache", "ms-playwright");
}

// executables inside a Playwright browser directory, by platform
const PLAYWRIGHT_BINARIES: Array<[string, string[]]> = [
  ["chromium_headless_shell-", [
    "chrome-headless-shell-linux64/chrome-headless-shell",
    "chrome-headless-shell-mac-arm64/chrome-headless-shell",
    "chrome-headless-shell-mac-x64/chrome-headless-shell",
    "chrome-linux/headless_shell",
  ]],
  ["chromium-", [
    "chrome-linux64/chrome",
    "chrome-linux/chrome",
    "chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing",
    "chrome-mac-x64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing",
    "chrome-mac/Chromium.app/Contents/MacOS/Chromium",
  ]],
];

function fromPlaywright(): string | null {
  const root = playwrightRoot();
  let entries: string[];
  try {
    entries = readdirSync(root);
  } catch {
    return null;
  }
  for (const [prefix, bins] of PLAYWRIGHT_BINARIES) {
    const dirs = entries
      .filter((e) => e.startsWith(prefix) && /^\d+$/.test(e.slice(prefix.length)))
      .sort((a, b) => Number(b.slice(prefix.length)) - Number(a.slice(prefix.length)));
    for (const d of dirs) {
      for (const b of bins) {
        const p = join(root, d, b);
        if (existsSync(p)) return p;
      }
    }
  }
  return null;
}

export function findChromium(): string | null {
  const env = process.env.BACKPLANE_CHROMIUM;
  if (env && existsSync(env)) return env;
  for (const n of SYSTEM_NAMES) {
    const p = onPath(n);
    if (p) return p;
  }
  for (const p of SYSTEM_PATHS) if (existsSync(p)) return p;
  return fromPlaywright();
}

export const INSTALL_HINT =
  "no Chromium found: set BACKPLANE_CHROMIUM, install Chrome/Chromium, or run `bunx playwright install chromium`";
