// G7 — no dangling pending-handoff UI symbols remain in lib/ (direct model).
// Scans Dart source for CALL/USAGE patterns (not prose comments).
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

const banned = [
  /TaskRepository\.acceptHandoff/, /TaskRepository\.rejectHandoff/,
  /\.rpc\(\s*'accept_handoff'/, /\.rpc\(\s*'reject_handoff'/,
  /onAcceptHandoff\s*:/, /onRejectHandoff\s*:/,
  /_WaitingList\s*\(/, /_acceptHandoff\s*\(/, /_rejectHandoff\s*\(/,
];

function walk(dir) {
  let out = [];
  for (const e of readdirSync(dir)) {
    const p = join(dir, e);
    if (statSync(p).isDirectory()) out = out.concat(walk(p));
    else if (p.endsWith('.dart')) out.push(p);
  }
  return out;
}

const hits = [];
for (const f of walk('lib')) {
  const src = readFileSync(f, 'utf8');
  for (const re of banned) {
    const m = src.match(re);
    if (m) hits.push(`${f}: ${m[0]}`);
  }
}
if (hits.length) { console.log('G7_FAIL:\n' + hits.join('\n')); process.exit(1); }
console.log('G7_PASS');
