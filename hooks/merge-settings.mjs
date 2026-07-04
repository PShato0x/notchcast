#!/usr/bin/env node
// Idempotently merges the NotchCast hooks into ~/.claude/settings.json.
// Existing settings and hooks are preserved; a .bak backup is written before
// any change. Safe to run repeatedly (e.g. on every update).

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const SETTINGS_PATH = path.join(os.homedir(), '.claude', 'settings.json');

// Use THIS node's absolute path: hooks also run in contexts with a minimal
// PATH (launchd services, headless `claude -p` children) where a bare `node`
// is not found and every hook would silently fail.
const NODE_BIN = process.execPath;
const GATE_CMD = `"${NODE_BIN}" "$HOME/.notchcast/hooks/permission-gate.mjs"`;
const REPORT_CMD = `"${NODE_BIN}" "$HOME/.notchcast/hooks/status-report.mjs"`;

let settings = {};
try {
  settings = JSON.parse(fs.readFileSync(SETTINGS_PATH, 'utf8'));
} catch {
  // no settings yet — start fresh
}
settings.hooks ||= {};

function hasCommand(entries, needle) {
  return (entries || []).some((entry) =>
    (entry.hooks || []).some((h) => typeof h.command === 'string' && h.command.includes(needle))
  );
}

let changed = false;

// Normalize existing NotchCast hook commands: migrate pre-rename paths
// (~/.claude-widget, ~/.notchai) and rewrite to the canonical commands
// (absolute node path included).
for (const entries of Object.values(settings.hooks)) {
  for (const entry of entries || []) {
    for (const h of entry.hooks || []) {
      if (typeof h.command !== 'string') continue;
      let canonical = null;
      if (/(\.claude-widget|\.notchai|\.notchcast)\/hooks\/permission-gate\.mjs/.test(h.command)) {
        canonical = GATE_CMD;
      } else if (/(\.claude-widget|\.notchai|\.notchcast)\/hooks\/status-report\.mjs/.test(h.command)) {
        canonical = REPORT_CMD;
      }
      if (canonical && h.command !== canonical) {
        h.command = canonical;
        changed = true;
      }
    }
  }
}

if (!hasCommand(settings.hooks.PreToolUse, 'permission-gate.mjs')) {
  settings.hooks.PreToolUse ||= [];
  settings.hooks.PreToolUse.push({
    matcher: 'Bash|Edit|MultiEdit|Write|NotebookEdit|WebFetch',
    hooks: [{ type: 'command', command: GATE_CMD, timeout: 180 }],
  });
  changed = true;
}

for (const event of ['UserPromptSubmit', 'PostToolUse', 'Stop', 'Notification', 'SessionEnd']) {
  if (!hasCommand(settings.hooks[event], 'status-report.mjs')) {
    settings.hooks[event] ||= [];
    settings.hooks[event].push({
      hooks: [{ type: 'command', command: REPORT_CMD, timeout: 10 }],
    });
    changed = true;
  }
}

if (changed) {
  fs.mkdirSync(path.dirname(SETTINGS_PATH), { recursive: true });
  if (fs.existsSync(SETTINGS_PATH)) fs.copyFileSync(SETTINGS_PATH, SETTINGS_PATH + '.bak');
  fs.writeFileSync(SETTINGS_PATH, JSON.stringify(settings, null, 2) + '\n');
  console.log(`Merged NotchCast hooks into ${SETTINGS_PATH} (backup: settings.json.bak)`);
} else {
  console.log('NotchCast hooks already present — settings unchanged.');
}
