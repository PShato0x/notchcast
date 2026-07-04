#!/usr/bin/env node
// NotchCast relay server.
// Runs on the Mac next to Claude Code. Hooks POST events here; clients (the
// island) poll /status and answer permission requests via /respond.
// Zero dependencies — requires Node 18+.

import http from 'node:http';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const CONFIG_DIR = path.join(os.homedir(), '.notchcast');
const CONFIG_PATH = path.join(CONFIG_DIR, 'config.json');
const RULES_PATH = path.join(CONFIG_DIR, 'rules.json');

function loadJSON(p, fallback) {
  try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch { return fallback; }
}
function saveJSON(p, value) {
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, JSON.stringify(value, null, 2));
}

const fileConfig = loadJSON(CONFIG_PATH, {});
const PORT = Number(process.env.CW_PORT || fileConfig.port || 8787);
// Localhost-only by default; set host: "0.0.0.0" in config.json to pair a
// remote client (use Tailscale — never expose this port to the internet).
const HOST = process.env.CW_HOST || fileConfig.host || '127.0.0.1';
const TOKEN = process.env.CW_TOKEN || fileConfig.token;
const GATE_TIMEOUT_MS = Number(process.env.CW_GATE_TIMEOUT_MS || fileConfig.gateTimeoutMs || 120_000);
const CLAUDE_BIN = process.env.CW_CLAUDE_BIN || fileConfig.claudeBin || 'claude';
const SESSION_TTL_MS = 24 * 60 * 60 * 1000;

if (!TOKEN) {
  console.error('No auth token configured. Run install.sh or set CW_TOKEN / token in ~/.notchcast/config.json');
  process.exit(1);
}

let remoteMode = fileConfig.remoteMode ?? true;
let rules = loadJSON(RULES_PATH, []); // array of signature strings, e.g. "Bash:npm"

// ---------- update check ----------

const SRC_DIR = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const VERSION_URL = process.env.CW_VERSION_URL
  || fileConfig.versionUrl
  || 'https://raw.githubusercontent.com/PShato0x/notchcast/main/VERSION';
const CURRENT_VERSION = (() => {
  try { return fs.readFileSync(path.join(SRC_DIR, 'VERSION'), 'utf8').trim(); } catch { return '0.0.0'; }
})();

let latestVersion = null;
let lastUpdateCheck = 0;

function versionGt(a, b) {
  const pa = String(a).split('.').map(Number);
  const pb = String(b).split('.').map(Number);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const d = (pa[i] || 0) - (pb[i] || 0);
    if (d) return d > 0;
  }
  return false;
}

function checkForUpdate() {
  if (Date.now() - lastUpdateCheck < 6 * 60 * 60 * 1000) return; // every 6h
  lastUpdateCheck = Date.now();
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 5000);
  fetch(VERSION_URL, { signal: controller.signal })
    .then((r) => (r.ok ? r.text() : null))
    .then((text) => { if (text) latestVersion = text.trim(); })
    .catch(() => {})
    .finally(() => clearTimeout(timer));
}

const sessions = new Map(); // sessionId -> {id, title, cwd, state, lastPrompt, currentTool, message, updatedAt}
const pending = new Map();  // requestId -> {info, resolve, timer}
const asks = new Map();     // askId -> {id, prompt, state, answer, error, createdAt}

// ---------- helpers ----------

function truncate(s, n) {
  if (typeof s !== 'string') return '';
  return s.length > n ? s.slice(0, n - 1) + '…' : s;
}

// A stable "kind of action" key used for Always-allow rules.
function signatureFor(tool, input = {}) {
  if (tool === 'Bash' && typeof input.command === 'string') {
    // Skip leading VAR=... assignments so "FOO=bar npm test" -> "npm", and
    // avoid junk signatures like "Bash:TAG=$(curl".
    const tokens = input.command.trim().split(/\s+/);
    const word = tokens.find((t) => !/^[A-Za-z_][A-Za-z0-9_]*=/.test(t)) || tokens[0] || '';
    return `Bash:${truncate(word, 32)}`;
  }
  if (tool === 'WebFetch' && typeof input.url === 'string') {
    try { return `WebFetch:${new URL(input.url).host}`; } catch { return 'WebFetch'; }
  }
  return tool;
}

// Human-readable one-liner for the widget: "run `npm test`", "edit src/app.ts", ...
function summaryFor(tool, input = {}) {
  if (tool === 'Bash' && input.command) return `run \`${truncate(input.command, 120)}\``;
  if ((tool === 'Edit' || tool === 'MultiEdit' || tool === 'NotebookEdit') && input.file_path)
    return `edit ${truncate(path.basename(input.file_path) === input.file_path ? input.file_path : input.file_path, 100)}`;
  if (tool === 'Write' && input.file_path) return `write ${truncate(input.file_path, 100)}`;
  if (tool === 'WebFetch' && input.url) return `fetch ${truncate(input.url, 100)}`;
  const blob = truncate(JSON.stringify(input), 100);
  return `use ${tool}${blob && blob !== '{}' ? ` ${blob}` : ''}`;
}

function touchSession(payload, patch = {}) {
  const id = payload.session_id || 'unknown';
  const prev = sessions.get(id) || {
    id,
    title: payload.cwd ? path.basename(payload.cwd) : 'Claude session',
    cwd: payload.cwd || '',
    state: 'working',
    lastPrompt: '',
    currentTool: '',
    message: '',
  };
  const next = { ...prev, ...patch, updatedAt: Date.now() };
  sessions.set(id, next);
  return next;
}

function pruneSessions() {
  const cutoff = Date.now() - SESSION_TTL_MS;
  for (const [id, s] of sessions) if (s.updatedAt < cutoff) sessions.delete(id);
}

function snapshot() {
  pruneSessions();
  checkForUpdate(); // async, throttled; result lands in a later snapshot
  return {
    remoteMode,
    serverTime: Date.now(),
    sessions: [...sessions.values()].sort((a, b) => b.updatedAt - a.updatedAt),
    pending: [...pending.values()]
      .map((p) => p.info)
      .sort((a, b) => a.createdAt - b.createdAt),
    rules,
    version: CURRENT_VERSION,
    latestVersion,
    updateAvailable: latestVersion ? versionGt(latestVersion, CURRENT_VERSION) : false,
  };
}

function persistRemoteMode() {
  const cfg = loadJSON(CONFIG_PATH, {});
  cfg.remoteMode = remoteMode;
  saveJSON(CONFIG_PATH, cfg);
}

// ---------- request plumbing ----------

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', (c) => {
      data += c;
      if (data.length > 1_000_000) { reject(new Error('body too large')); req.destroy(); }
    });
    req.on('end', () => resolve(data));
    req.on('error', reject);
  });
}

function send(res, code, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(code, { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) });
  res.end(body);
}

function authorized(req, url) {
  const header = req.headers.authorization || '';
  const bearer = header.startsWith('Bearer ') ? header.slice(7) : '';
  const q = url.searchParams.get('token') || '';
  const candidate = bearer || q;
  if (candidate.length !== TOKEN.length) return false;
  return crypto.timingSafeEqual(Buffer.from(candidate), Buffer.from(TOKEN));
}

// ---------- handlers ----------

async function handleGate(payload, res) {
  const tool = payload.tool_name || 'unknown';
  const input = payload.tool_input || {};
  const sig = signatureFor(tool, input);

  if (!remoteMode) return send(res, 200, { decision: 'passthrough' });

  if (rules.includes(sig)) {
    touchSession(payload, { state: 'working', currentTool: tool });
    return send(res, 200, { decision: 'allow', reason: `Matched saved rule "${sig}" (NotchCast)` });
  }

  const id = crypto.randomUUID();
  const info = {
    id,
    sessionId: payload.session_id || 'unknown',
    project: payload.cwd ? path.basename(payload.cwd) : 'Claude session',
    cwd: payload.cwd || '',
    tool,
    signature: sig,
    summary: summaryFor(tool, input),
    createdAt: Date.now(),
  };
  touchSession(payload, { state: 'waiting', currentTool: tool, message: info.summary });

  const decision = await new Promise((resolve) => {
    const timer = setTimeout(() => {
      pending.delete(id);
      resolve({ decision: 'passthrough' }); // fall back to the terminal prompt
    }, GATE_TIMEOUT_MS);
    pending.set(id, { info, resolve, timer });
  });

  touchSession(payload, { state: 'working', message: '' });
  send(res, 200, decision);
}

function handleRespond(body, res) {
  const { id, decision } = body || {};
  const entry = pending.get(id);
  if (!entry) return send(res, 410, { error: 'request expired or already answered' });
  if (!['always', 'once', 'deny'].includes(decision)) return send(res, 400, { error: 'decision must be always|once|deny' });

  clearTimeout(entry.timer);
  pending.delete(id);

  if (decision === 'always' && !rules.includes(entry.info.signature)) {
    rules.push(entry.info.signature);
    saveJSON(RULES_PATH, rules);
  }
  entry.resolve(
    decision === 'deny'
      ? { decision: 'deny', reason: 'Denied remotely (NotchCast)' }
      : { decision: 'allow', reason: `Approved remotely (${decision === 'always' ? 'always allow' : 'allow once'})` }
  );
  send(res, 200, { ok: true });
}

function handleEvent(payload, res) {
  const event = payload.hook_event_name;
  switch (event) {
    case 'UserPromptSubmit':
      touchSession(payload, { state: 'working', lastPrompt: truncate(payload.prompt || '', 200), message: '' });
      break;
    case 'PreToolUse':
      touchSession(payload, { state: 'working', currentTool: payload.tool_name || '' });
      break;
    case 'PostToolUse':
      touchSession(payload, { state: 'working' });
      break;
    case 'Stop':
    case 'SubagentStop':
      touchSession(payload, { state: 'idle', currentTool: '', message: '' });
      break;
    case 'Notification':
      touchSession(payload, { state: 'attention', message: truncate(payload.message || 'Claude needs your attention', 200) });
      break;
    case 'SessionEnd':
      touchSession(payload, { state: 'ended', currentTool: '', message: '' });
      break;
    default:
      touchSession(payload);
  }
  send(res, 200, { ok: true });
}

function handleAsk(body, res) {
  const prompt = (body?.prompt || '').trim();
  if (!prompt) return send(res, 400, { error: 'prompt required' });

  const id = crypto.randomUUID();
  const job = { id, prompt: truncate(prompt, 300), state: 'running', answer: '', error: '', createdAt: Date.now() };
  asks.set(id, job);
  if (asks.size > 50) asks.delete(asks.keys().next().value);

  const child = spawn(CLAUDE_BIN, ['-p', prompt, '--output-format', 'json'], {
    cwd: body?.cwd || os.homedir(),
    env: process.env,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let out = '', err = '';
  child.stdout.on('data', (c) => (out += c));
  child.stderr.on('data', (c) => (err += c));
  child.on('error', (e) => { job.state = 'error'; job.error = String(e.message || e); });
  child.on('close', (code) => {
    if (job.state === 'error') return;
    if (code !== 0) { job.state = 'error'; job.error = truncate(err || `claude exited with code ${code}`, 500); return; }
    try {
      const parsed = JSON.parse(out);
      job.answer = parsed.result || out;
    } catch { job.answer = out.trim(); }
    job.state = 'done';
  });

  send(res, 200, { id });
}

// ---------- server ----------

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  if (!authorized(req, url)) return send(res, 401, { error: 'unauthorized' });

  let body = {};
  if (req.method === 'POST') {
    try { body = JSON.parse((await readBody(req)) || '{}'); } catch { return send(res, 400, { error: 'invalid JSON' }); }
  }

  try {
    if (req.method === 'GET' && url.pathname === '/status') return send(res, 200, snapshot());
    if (req.method === 'POST' && url.pathname === '/gate') return handleGate(body, res);
    if (req.method === 'POST' && url.pathname === '/respond') return handleRespond(body, res);
    if (req.method === 'POST' && url.pathname === '/event') return handleEvent(body, res);
    if (req.method === 'POST' && url.pathname === '/mode') {
      remoteMode = Boolean(body.remoteMode);
      persistRemoteMode();
      return send(res, 200, { ok: true, remoteMode });
    }
    if (req.method === 'POST' && url.pathname === '/rules/clear') {
      rules = [];
      saveJSON(RULES_PATH, rules);
      return send(res, 200, { ok: true });
    }
    if (req.method === 'POST' && url.pathname === '/ask') return handleAsk(body, res);
    if (req.method === 'GET' && url.pathname.startsWith('/ask/')) {
      const job = asks.get(url.pathname.slice('/ask/'.length));
      if (!job) return send(res, 404, { error: 'not found' });
      return send(res, 200, job);
    }
    send(res, 404, { error: 'not found' });
  } catch (e) {
    send(res, 500, { error: String(e?.message || e) });
  }
});

server.listen(PORT, HOST, () => {
  console.log(`NotchCast relay listening on http://${HOST}:${PORT}`);
  if (HOST !== '127.0.0.1') {
    const nets = os.networkInterfaces();
    const lan = Object.values(nets).flat().find((n) => n && n.family === 'IPv4' && !n.internal);
    if (lan) console.log(`  reachable on the network at http://${lan.address}:${PORT} — keep the token safe`);
  }
  console.log(`  remote approvals: ${remoteMode ? 'ON' : 'OFF'}`);
});
