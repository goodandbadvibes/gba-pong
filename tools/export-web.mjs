#!/usr/bin/env node
// Exports the Web build to build/web, stamping the current git commit into the game so the title
// and pause screens show which build is running ("+" means there were uncommitted changes).
//
//   node tools/export-web.mjs
//
// Godot: $GODOT, else a Godot 4 console executable or `godot` found on PATH.

import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { delimiter, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const infoPath = join(root, "scripts", "build_info.gd");

function findGodot() {
  if (process.env.GODOT) return process.env.GODOT;
  const windows = process.platform === "win32";
  for (const dir of (process.env.PATH || "").split(delimiter)) {
    if (!dir || !existsSync(dir)) continue;
    let files;
    try {
      files = readdirSync(dir);
    } catch {
      continue;
    }
    const consoleExe = files.find((f) => /^Godot_v4.*_console\.exe$/i.test(f));
    if (consoleExe) return join(dir, consoleExe);
    const plain = files.find((f) => (windows ? /^godot4?\.exe$/i : /^godot4?$/).test(f));
    if (plain) return join(dir, plain);
  }
  throw new Error("Godot not found. Put Godot 4 on PATH or set GODOT.");
}

const git = (args) => execFileSync("git", args, { cwd: root, encoding: "utf8" }).trim();
const dirty = git(["status", "--porcelain", "--", ".", ":(exclude)build"]) !== "";
const version = git(["rev-parse", "--short", "HEAD"]) + (dirty ? "+" : "");

const original = readFileSync(infoPath, "utf8");
writeFileSync(infoPath, original.replace(/const VERSION := ".*"/, `const VERSION := "${version}"`));
try {
  mkdirSync(join(root, "build", "web"), { recursive: true });
  const result = spawnSync(findGodot(), ["--headless", "--path", root, "--export-release", "Web", "build/web/index.html"], {
    stdio: ["ignore", "ignore", "inherit"],
  });
  if (result.status !== 0 || !existsSync(join(root, "build", "web", "index.pck"))) {
    throw new Error(`Godot export failed (exit ${result.status})`);
  }
  console.log(`Exported build ${version} to build/web`);
} finally {
  writeFileSync(infoPath, original);
}
