#!/usr/bin/env node
// Publishes build/web to the gh-pages branch of origin, which GitHub Pages serves.
// Export first: godot --headless --path . --export-release "Web" build/web/index.html
//
//   node tools/deploy-pages.mjs
//
// The gh-pages branch holds only the latest build, so each deploy replaces it (force push).

import { execFileSync } from "node:child_process";
import { cpSync, existsSync, mkdtempSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const build = join(root, "build", "web");
if (!existsSync(join(build, "index.html"))) {
  console.error("No build/web/index.html. Export the Web preset first.");
  process.exit(1);
}

const git = (args, cwd = root) => execFileSync("git", args, { cwd, encoding: "utf8" }).trim();
const origin = git(["remote", "get-url", "origin"]);
const commit = git(["rev-parse", "--short", "HEAD"]);

const work = mkdtempSync(join(tmpdir(), "gh-pages-"));
try {
  for (const file of readdirSync(build)) {
    if (!file.endsWith(".import") && file !== ".gdignore") cpSync(join(build, file), join(work, file));
  }
  // Stop GitHub Pages from running Jekyll over the build.
  writeFileSync(join(work, ".nojekyll"), "");
  git(["init", "-q", "-b", "gh-pages"], work);
  git(["add", "-A"], work);
  git(["commit", "-q", "-m", `Deploy ${commit}`], work);
  git(["push", "-q", "--force", origin, "gh-pages"], work);
  console.log(`Deployed build of ${commit} to gh-pages.`);
} finally {
  rmSync(work, { recursive: true, force: true });
}
