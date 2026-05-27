#!/usr/bin/env node
// PostToolUse hook: log git commit invocations only.
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

// WORKLOG_ENV/WORKLOG_DIR 우선, 없으면 OS 자동 감지 (plugin 이식성).
function osDefaults() {
    const os = require('os');
    const home = os.homedir();
    switch (os.platform()) {
        case 'win32':  return { env: 'windows', dir: path.join(process.env.USERPROFILE || home, 'worklog') };
        case 'darwin': return { env: 'macos', dir: path.join(home, 'worklog') };
        default: {     // linux
            let wsl = false;
            try { wsl = /microsoft/i.test(fs.readFileSync('/proc/version', 'utf8')); } catch (_) {}
            return wsl ? { env: 'wsl', dir: '/mnt/c/Users/user/worklog' }   // username 다르면 WORKLOG_DIR 지정
                       : { env: 'linux', dir: path.join(home, 'worklog') };
        }
    }
}
const _d = osDefaults();
const ENV = process.env.WORKLOG_ENV || _d.env;
const DIR = process.env.WORKLOG_DIR || _d.dir;

let stdin = '';
try { stdin = fs.readFileSync(0, 'utf8'); } catch (_) { process.exit(0); }
let p = {};
try { p = JSON.parse(stdin); } catch (_) { process.exit(0); }

if (p.tool_name !== 'Bash') process.exit(0);
const cmd = (p.tool_input && p.tool_input.command) || '';
if (!/\bgit\s+commit\b/.test(cmd)) process.exit(0);
// Skip dry-runs and amends-only-check
if (/\s--dry-run\b/.test(cmd)) process.exit(0);

const resp = p.tool_response || {};
const stdoutText = (typeof resp === 'string') ? resp
    : (resp.stdout || resp.output || resp.content || '');
const shaMatch = stdoutText.match(/\[[^\]]*?\s([0-9a-f]{7,40})\]/);
const sha = shaMatch ? shaMatch[1] : null;

function git(cwd, args) {
    try {
        return execSync('git -C ' + JSON.stringify(cwd) + ' ' + args,
            { stdio: ['ignore', 'pipe', 'ignore'], timeout: 1500 }).toString().trim() || null;
    } catch (_) { return null; }
}

const cwd = p.cwd || process.cwd();
const branch = git(cwd, 'branch --show-current');
const fullSha = sha ? git(cwd, `rev-parse ${sha}`) || sha : git(cwd, 'rev-parse HEAD');
const subject = git(cwd, `log -1 --pretty=%s ${fullSha || 'HEAD'}`);
const body = git(cwd, `log -1 --pretty=%b ${fullSha || 'HEAD'}`);

const now = new Date();
const ym = now.toISOString().slice(0, 7);
const file = path.join(DIR, `worklog-${ENV}-${ym}.jsonl`);

const entry = {
    ts: now.toISOString(),
    env: ENV,
    event: 'commit',
    session_id: p.session_id || null,
    cwd,
    branch,
    sha: fullSha,
    subject,
    body: body || null,
    command: cmd.slice(0, 500),
};

try {
    fs.mkdirSync(DIR, { recursive: true });
    fs.appendFileSync(file, JSON.stringify(entry) + '\n');
} catch (_) { /* swallow */ }
process.exit(0);
