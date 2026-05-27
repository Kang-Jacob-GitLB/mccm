#!/usr/bin/env node
// SessionStart / Stop hook: bookmark session boundaries.
const fs = require('fs');
const path = require('path');

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

const ev = (p.hook_event_name || '').toLowerCase();
const eventTag = ev === 'sessionstart' ? 'session_start'
    : ev === 'stop' ? 'session_stop'
    : ev || 'session_event';

const now = new Date();
const ym = now.toISOString().slice(0, 7);
const file = path.join(DIR, `worklog-${ENV}-${ym}.jsonl`);

const entry = {
    ts: now.toISOString(),
    env: ENV,
    event: eventTag,
    session_id: p.session_id || null,
    cwd: p.cwd || null,
    source: p.source || null,
};

try {
    fs.mkdirSync(DIR, { recursive: true });
    fs.appendFileSync(file, JSON.stringify(entry) + '\n');
} catch (_) { /* swallow */ }
process.exit(0);
