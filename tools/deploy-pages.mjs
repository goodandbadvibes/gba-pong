#!/usr/bin/env node
// Publishes build/web to the gh-pages branch of origin, which GitHub Pages serves.
// Export first: node tools/export-web.mjs
//
//   node tools/deploy-pages.mjs
//
// Browsers may keep GitHub Pages files for 10 minutes, so a plain index.pck can stay stale after
// a deploy. Each deploy therefore names the game package after its contents (index-<hash>.pck)
// and points index.html at it, so a fresh page always loads the new game. The last few packages
// stay on the branch, so a page that is still cached keeps loading the build it was made for.

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { cpSync, existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const KEEP_PACKS = 5;
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const build = join(root, "build", "web");
if (!existsSync(join(build, "index.html")) || !existsSync(join(build, "index.pck"))) {
  console.error("No build/web/index.html or index.pck. Run node tools/export-web.mjs first.");
  process.exit(1);
}

const git = (args, cwd = root) => execFileSync("git", args, { cwd, encoding: "utf8" }).trim();
const origin = git(["remote", "get-url", "origin"]);
const commit = git(["rev-parse", "--short", "HEAD"]);

const pck = readFileSync(join(build, "index.pck"));
const packName = `index-${createHash("sha256").update(pck).digest("hex").slice(0, 10)}.pck`;

const work = mkdtempSync(join(tmpdir(), "gh-pages-"));
try {
  // Start from the published branch to keep recent packages; fall back to a fresh one.
  let fresh = false;
  try {
    git(["clone", "-q", "--depth", "1", "--branch", "gh-pages", origin, work], root);
  } catch {
    git(["init", "-q", "-b", "gh-pages"], work);
    fresh = true;
  }
  const manifestPath = join(work, "packs.txt");
  const recent = existsSync(manifestPath) ? readFileSync(manifestPath, "utf8").split("\n").filter(Boolean) : [];
  const keep = [packName, ...recent.filter((p) => p !== packName)].slice(0, KEEP_PACKS);

  for (const file of readdirSync(work)) {
    if (file !== ".git" && !(file.startsWith("index-") && keep.includes(file))) rmSync(join(work, file), { recursive: true, force: true });
  }
  for (const file of readdirSync(build)) {
    if (file.endsWith(".import") || file === ".gdignore") continue;
    // index.pck stays too (as the newest build) for pages cached before packages had names.
    if (file === "index.pck") cpSync(join(build, file), join(work, packName));
    cpSync(join(build, file), join(work, file));
  }

  // Point the page at the named package (Godot's web loader reads mainPack and fileSizes).
  const htmlPath = join(work, "index.html");
  let html = readFileSync(htmlPath, "utf8");
  if (!html.includes('"index.pck":')) throw new Error("index.html has no index.pck entry to rename");
  html = html.replace('"index.pck":', `"${packName}":`).replace("const GODOT_CONFIG = {", `const GODOT_CONFIG = {"mainPack":"${packName}",`);
  writeFileSync(htmlPath, html);
  writeFileSync(manifestPath, keep.join("\n") + "\n");
  // Stop GitHub Pages from running Jekyll over the build.
  writeFileSync(join(work, ".nojekyll"), "");

  git(["add", "-A"], work);
  if (git(["status", "--porcelain"], work) === "") {
    console.log("Nothing changed; the live build is already this one.");
  } else {
    git(["commit", "-q", "-m", `Deploy ${commit} (${packName})`], work);
    git(["push", "-q", ...(fresh ? ["--force"] : []), origin, "gh-pages"], work);
    console.log(`Deployed build of ${commit} to gh-pages as ${packName}.`);
  }
} finally {
  rmSync(work, { recursive: true, force: true });
}
