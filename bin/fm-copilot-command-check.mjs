#!/usr/bin/env node
// Native Copilot command-hook transport, not another command-policy owner.
// Usage: fm-copilot-command-check.mjs arm|cd < hook-payload.json
// Reuses the existing semantic policies without a Git Bash/jq transport tree.
// It never executes submitted command text. Missing/malformed input or an
// unavailable policy/scope preserves the legacy transport's silent allow.
// The cd transport retains its plain-checkout scope, including override roots;
// neither an absent .git nor a linked task worktree acquires primary scope.
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, realpathSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { decision as armDecision } from "./fm-arm-command-policy.mjs";
import { decision as cdDecision } from "./fm-cd-command-policy.mjs";

const codeRoot = realpathSync(path.dirname(path.dirname(fileURLToPath(import.meta.url))));

function nativePath(value) {
  if (process.platform !== "win32" || !value.startsWith("/")) return value;
  // Ask Git for Windows about its actual mounts rather than inventing a /tmp
  // mapping or case-folding path identities. Ordinary native inputs need no call.
  const converted = spawnSync("cygpath", ["-w", value], {
    encoding: "utf8", windowsHide: true, timeout: 2000,
  });
  return converted.status === 0 ? converted.stdout.trim() : value;
}

function plainCheckout(root) {
  if (!existsSync(path.join(root, "AGENTS.md")) || !existsSync(path.join(root, "bin"))) return false;
  const result = spawnSync("git", ["-C", root, "rev-parse", "--git-dir", "--git-common-dir"], {
    encoding: "utf8", windowsHide: true, timeout: 5000,
  });
  const lines = (result.stdout || "").trim().split(/\r?\n/);
  return result.status === 0 && lines.length === 2 && lines[0] !== "" && lines[0] === lines[1];
}

try {
  if (process.env.COPILOT_CLI === "1") {
    const policy = process.argv[2];
    if (policy !== "arm" && policy !== "cd") throw new Error("unknown command policy");
    const payload = JSON.parse(readFileSync(0, "utf8").replace(/^\uFEFF/, ""));
    // Preserve the foreign-delivery exclusion owned by fm-hook-host-lib.sh;
    // an inherited environment marker is not evidence that Cursor sent a
    // Copilot event. All actual command decisions still belong to the policies.
    const command = typeof payload?.cursor_version === "string" ? undefined
      : payload?.toolInput?.command ?? payload?.tool_input?.command;
    if (typeof command === "string" && command.length > 0) {
      let result;
      if (policy === "arm") {
        result = armDecision(command, codeRoot, process.env.FM_HOME || codeRoot);
      } else {
        const root = nativePath(process.env.FM_ROOT_OVERRIDE || codeRoot);
        if (plainCheckout(root)) result = cdDecision(command);
      }
      if (result?.decision === "deny") {
        process.stdout.write(JSON.stringify({
          permissionDecision: "deny",
          permissionDecisionReason: `[${result.code}] ${result.reason}`,
        }) + "\n");
      }
    }
  }
} catch {
  // This is the existing malformed-transport/unavailable-classifier contract,
  // not permission to reuse another checkout's policy or an earlier verdict.
}
