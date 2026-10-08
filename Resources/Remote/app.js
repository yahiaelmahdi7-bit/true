'use strict';
// True on the web: a thin window onto panes the Mac already has open. The Mac stays authoritative:
// this page never resizes a PTY, it renders at the Mac's cols and scales/scrolls to fit.
const $ = (id) => document.getElementById(id);
const enc = new TextEncoder();
const KEYS = { esc: '\x1b', tab: '\t', up: '\x1b[A', down: '\x1b[B', right: '\x1b[C', left: '\x1b[D', cc: '\x03' };

let view = 'list', paneId = null, term = null, ws = null, cols = 80, rows = 24;
let fit = true, ctrl = false, retry = 0, retryTimer = null, listFails = 0, wsEverOpen = false;

function banner(msg) { const b = $('banner'); b.textContent = msg || ''; b.hidden = !msg; }

// ---------- list ----------
async function loadList() {
  if (view !== 'list') return;
  try {
    const r = await fetch('/api/tabs', { credentials: 'same-origin', cache: 'no-store' });
    if (r.status === 401 || r.status === 403) { location.reload(); return; }
    const data = await r.json();
    listFails = 0; banner('');
    renderList(data.tabs || []);
  } catch (e) {
    if (++listFails >= 2) banner('Mac asleep or offline — retrying…');
  }
}

function renderList(tabs) {
  const host = $('tabs'); host.textContent = '';
  let n = 0;
  for (const t of tabs) {
    const sec = document.createElement('section'); sec.className = 'tab';
    const h = document.createElement('h2'); h.textContent = t.title; sec.appendChild(h);
    for (const p of t.panes) {
      n++;
      const b = document.createElement('button');
      b.className = 'pane' + (p.live ? '' : ' dead'); b.disabled = !p.live;
      const box = document.createElement('span'); box.className = 't';
      const a = document.createElement('span'); a.className = 'n'; a.textContent = p.title;
      const c = document.createElement('span'); c.className = 'c'; c.textContent = p.cwd || '';
      box.append(a, c); b.appendChild(box);
      if (p.needsYou) { const s = document.createElement('span'); s.className = 'chip need'; s.textContent = 'Needs you'; b.appendChild(s); }
      else if (p.busy) { const s = document.createElement('span'); s.className = 'chip busy'; s.textContent = 'Working'; b.appendChild(s); }
      b.onclick = () => openPane(p.id, p.title);
      sec.appendChild(b);
    }
    host.appendChild(sec);
  }
  $('empty').hidden = n > 0;
  $('clock').textContent = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

// ---------- terminal ----------
function ensureTerm() {
  if (term) return;
  term = new Terminal({
    cols, rows, scrollback: 3000, cursorBlink: false, allowProposedApi: true, convertEol: false,
    fontFamily: 'ui-monospace, "SF Mono", Menlo, monospace', fontSize: 13,
    theme: { background: '#000000', foreground: '#f2f2f2', cursor: '#f2f2f2' },
  });
  term.open($('xt'));
  term.onData((d) => {
    if (ctrl && d.length === 1) {
      const c = d.toUpperCase().charCodeAt(0);
      if (c >= 64 && c <= 95) d = String.fromCharCode(c - 64);
      setCtrl(false);
    }
    sendText(d);
  });
}

function sendText(s) { if (ws && ws.readyState === 1) ws.send(enc.encode(s)); }
function setCtrl(on) { ctrl = on; $('ctrl').setAttribute('aria-pressed', String(on)); }

function applyScale() {
  if (!term) return;
  const avail = $('screen').clientWidth - 8;
  let size = 13;
  if (fit) size = Math.max(6, Math.min(15, Math.floor((avail / (cols * 0.602)) * 10) / 10));
  term.options.fontSize = size;
}

function openPane(id, title) {
  paneId = id; view = 'term'; location.hash = 'p=' + id;
  $('list').hidden = true; $('term').hidden = false; $('paneTitle').textContent = title || 'Pane';
  ensureTerm(); term.reset(); retry = 0; wsEverOpen = false; banner('');
  connect();
}

function closePane() {
  view = 'list'; paneId = null; history.replaceState(null, '', location.pathname);
  clearTimeout(retryTimer); if (ws) { ws.onclose = null; ws.close(); ws = null; }
  $('term').hidden = true; $('list').hidden = false; banner(''); loadList();
}

function connect() {
  clearTimeout(retryTimer);
  const proto = location.protocol === 'https:' ? 'wss://' : 'ws://';
  ws = new WebSocket(proto + location.host + '/api/pane/' + paneId);
  ws.binaryType = 'arraybuffer';
  const mine = ws;
  ws.onopen = () => { wsEverOpen = true; retry = 0; banner(''); };
  ws.onmessage = (ev) => {
    if (typeof ev.data === 'string') {
      const m = JSON.parse(ev.data);
      if (m.t === 'snap') { cols = m.cols; rows = m.rows; term.resize(cols, rows); applyScale(); }
      else if (m.t === 'gone') { banner('This pane was closed on the Mac.'); }
    } else { term.write(new Uint8Array(ev.data)); }
  };
  ws.onclose = () => {
    if (mine !== ws || view !== 'term') return;
    retry++;
    banner(retry > 2 ? 'Mac asleep or offline — retrying…' : 'Reconnecting…');
    // A refused upgrade (401/403/404) looks like a plain close; check whether we are still paired.
    fetch('/api/tabs', { credentials: 'same-origin', cache: 'no-store' })
      .then((r) => { if (r.status === 401 || r.status === 403) location.reload(); })
      .catch(() => {});
    retryTimer = setTimeout(connect, Math.min(15000, 1000 * 2 ** Math.min(retry, 4)));
  };
}

// ---------- wiring ----------
$('back').onclick = closePane;
$('fit').onclick = () => { fit = !fit; $('fit').setAttribute('aria-pressed', String(fit)); applyScale(); };
$('ctrl').onclick = () => setCtrl(!ctrl);
document.querySelectorAll('.k[data-k]').forEach((b) => (b.onclick = () => sendText(KEYS[b.dataset.k])));
$('paste').onclick = async () => {
  try {
    const t = await navigator.clipboard.readText();
    if (!t) return;
    const bp = term && term.modes && term.modes.bracketedPasteMode;
    sendText(bp ? '\x1b[200~' + t + '\x1b[201~' : t);
  } catch (e) { banner('Clipboard blocked — long-press the line field to paste.'); setTimeout(() => banner(''), 3000); }
};
$('line').onsubmit = (e) => { e.preventDefault(); const f = $('text'); sendText(f.value + '\r'); f.value = ''; };
window.addEventListener('resize', applyScale);
window.addEventListener('online', () => { if (view === 'term') { retry = 0; connect(); } else loadList(); });
document.addEventListener('visibilitychange', () => {
  if (document.hidden) return;
  if (view === 'term' && (!ws || ws.readyState > 1)) { retry = 0; connect(); } else loadList();
});

setInterval(loadList, 3000);
const m = /p=([0-9a-fA-F-]{36})/.exec(location.hash);
if (m) openPane(m[1], 'Pane'); else loadList();
