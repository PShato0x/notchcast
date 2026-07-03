#!/usr/bin/env node
// PreToolUse hook: forwards the permission request to the Claude Widget relay
// and waits for a decision from the iPhone.
//
// Output contract (Claude Code hooks):
//   - print {"hookSpecificOutput":{"permissionDecision":"allow"|"deny", ...}} to decide
//   - print nothing / exit 0 to fall through to the normal terminal prompt
//
// This hook FAILS OPEN: if the relay is down, remote mode is off, or the phone
// doesn't answer before the timeout, it prints nothing and Claude Code shows
// its regular permission prompt in the terminal.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const CONFIG_PATH = path.join(os.homedir(), '.claude-widget', 'config.json');

function loadConfig() {
  try { return JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8')); } catch { return {}; }
}

async function main() {
  const config = loadConfig();
  const base = process.env.CW_URL || config.url || 'http://127.0.0.1:8787';
  const token = process.env.CW_TOKEN || config.token;
  if (!token) return; // not configured -> passthrough

  const payload = JSON.parse(fs.readFileSync(0, 'utf8'));

  // Give the phone slightly less time than the hook's own timeout so we can
  // still exit cleanly and fall back to the terminal prompt.
  const gateTimeoutMs = Number(config.gateTimeoutMs || 120_000);
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), gateTimeoutMs + 10_000);

  let result;
  try {
    const res = await fetch(`${base}/gate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
      body: JSON.stringify(payload),
      signal: controller.signal,
    });
    if (!res.ok) return;
    result = await res.json();
  } catch {
    return; // relay unreachable -> passthrough
  } finally {
    clearTimeout(timer);
  }

  if (result?.decision === 'allow' || result?.decision === 'deny') {
    process.stdout.write(JSON.stringify({
      hookSpecificOutput: {
        hookEventName: 'PreToolUse',
        permissionDecision: result.decision,
        permissionDecisionReason: result.reason || 'Decided via Claude Widget',
      },
    }));
  }
  // 'passthrough' or anything else -> print nothing
}

main().then(() => process.exit(0)).catch(() => process.exit(0));
