#!/usr/bin/env node
// Fire-and-forget status hook: posts every hook event to the NotchAI
// relay so the iOS widget can show what the session is doing.
// Never blocks or fails the session — always exits 0 quickly.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const CONFIG_PATH = path.join(os.homedir(), '.notchai', 'config.json');

function loadConfig() {
  try { return JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8')); } catch { return {}; }
}

async function main() {
  const config = loadConfig();
  const base = process.env.CW_URL || config.url || 'http://127.0.0.1:8787';
  const token = process.env.CW_TOKEN || config.token;
  if (!token) return;

  const payload = JSON.parse(fs.readFileSync(0, 'utf8'));

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 3000);
  try {
    await fetch(`${base}/event`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
      body: JSON.stringify(payload),
      signal: controller.signal,
    });
  } catch {
    // relay down — ignore
  } finally {
    clearTimeout(timer);
  }
}

main().then(() => process.exit(0)).catch(() => process.exit(0));
