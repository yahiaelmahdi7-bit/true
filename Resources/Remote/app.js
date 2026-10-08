'use strict';
// True on the web: a thin window onto panes the Mac already has open. The Mac stays authoritative:
// this page never resizes a PTY, it renders at the Mac's cols and scales/scrolls to fit.
const $ = (id) => document.getElementById(id);
const enc = new TextEncoder();
const KEYS = { esc: '\x1b', tab: '\t', up: '\x1b[A', down: '\x1b[B', right: '\x1b[C', left: '\x1b[D', cc: '\x03' };

// Pairing token: localStorage + Authorization header, never a cookie (cookies ignore ports and would also reach
// other services on the same *.ts.net hostname).
const TOKEN_KEY = 'true.token';
const getToken = () => localStorage.getItem(TOKEN_KEY);
function api(path) { return fetch(path, { cache: 'no-store', headers: { Authorization: 'Bearer ' + getToken() } }); }
function unpair() {
  localStorage.removeItem(TOKEN_KEY); view = 'pair'; paneId = null;
  clearTimeout(retryTimer); if (ws) { ws.onclose = null; ws.close(); ws = null; }
  for (const id of ['list', 'term', 'shots', 'send', 'viewer']) $(id).hidden = true;
  $('nav').hidden = true; document.body.classList.remove('hasnav'); $('pair').hidden = false; banner('');
}

let view = 'list', paneId = null, term = null, ws = null, cols = 80, rows = 24;
let fit = true, ctrl = false, retry = 0, retryTimer = null, listFails = 0, wsEverOpen = false;

function banner(msg) { const b = $('banner'); b.textContent = msg || ''; b.hidden = !msg; }

// ---------- list ----------
async function loadList() {
  if (view !== 'list') return;
  try {
    const r = await api('/api/tabs');
    if (r.status === 401) { unpair(); return; }
    if (!r.ok) throw new Error(String(r.status));
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
  $('list').hidden = true; showNav(false); $('term').hidden = false; $('paneTitle').textContent = title || 'Pane';
  ensureTerm(); term.reset(); retry = 0; wsEverOpen = false; banner('');
  connect();
}

function closePane() {
  view = 'list'; paneId = null; history.replaceState(null, '', location.pathname);
  clearTimeout(retryTimer); if (ws) { ws.onclose = null; ws.close(); ws = null; }
  $('term').hidden = true; showNav(true); setTab('panes'); banner('');
}

function connect() {
  clearTimeout(retryTimer);
  const proto = location.protocol === 'https:' ? 'wss://' : 'ws://';
  ws = new WebSocket(proto + location.host + '/api/pane/' + paneId);
  ws.binaryType = 'arraybuffer';
  const mine = ws;
  ws.onopen = () => { ws.send(JSON.stringify({ auth: getToken() })); wsEverOpen = true; retry = 0; banner(''); };
  ws.onmessage = (ev) => {
    if (typeof ev.data === 'string') {
      const m = JSON.parse(ev.data);
      if (m.t === 'snap') { cols = m.cols; rows = m.rows; term.resize(cols, rows); applyScale(); }
      else if (m.t === 'gone') { banner('This pane was closed on the Mac.'); }
    } else { term.write(new Uint8Array(ev.data)); }
  };
  ws.onclose = (ev) => {
    if (mine !== ws || view !== 'term') return;
    if (ev.code === 4401) { unpair(); return; }
    retry++;
    banner(retry > 2 ? 'Mac asleep or offline — retrying…' : 'Reconnecting…');
    // A refused upgrade (403/404) looks like a plain close; check whether we are still paired.
    api('/api/tabs').then((r) => { if (r.status === 401) unpair(); }).catch(() => {});
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
  if (view === 'term' && (!ws || ws.readyState > 1)) { retry = 0; connect(); }
  else if (view === 'send') loadInbox(); else if (view === 'shots') loadShots(); else loadList();
});

$('pairForm').onsubmit = async (e) => {
  e.preventDefault();
  const err = $('pairErr'); err.hidden = true;
  try {
    const r = await fetch('/pair', { method: 'POST', cache: 'no-store', headers: { 'Content-Type': 'application/json' },
                                     body: JSON.stringify({ code: $('code').value.trim() }) });
    const data = await r.json().catch(() => ({}));
    if (r.ok && data.token) { localStorage.setItem(TOKEN_KEY, data.token); $('code').value = ''; start(); return; }
    err.textContent = data.error || 'Pairing failed.'; err.hidden = false;
  } catch (x) { err.textContent = 'Could not reach the Mac.'; err.hidden = false; }
};

function start() {
  $('pair').hidden = true;
  view = 'list'; $('list').hidden = false; showNav(true); setTab('panes');
  const m = /p=([0-9a-fA-F-]{36})/.exec(location.hash);
  if (m) openPane(m[1], 'Pane'); else loadList();
}


// ---------- phone <-> Mac drop: tabs, Shots, Send ----------
let tab = 'panes';
const SECTIONS = { panes: 'list', shots: 'shots', send: 'send' };
let inboxTimer = null, seenInbox = new Set(), shotCache = new Map(), viewerShot = null, inboxLoaded = false;

function showNav(on) { $('nav').hidden = !on; document.body.classList.toggle('hasnav', on); }
function setTab(name) {
  tab = name; view = name === 'panes' ? 'list' : name;
  for (const [t, id] of Object.entries(SECTIONS)) $(id).hidden = t !== name;
  document.querySelectorAll('#nav button').forEach((b) => { if (b.dataset.tab === name) b.setAttribute('aria-current', 'page'); else b.removeAttribute('aria-current'); });
  clearInterval(inboxTimer); inboxTimer = null;
  if (name === 'panes') loadList();
  if (name === 'shots') loadShots();
  if (name === 'send') { $('dot').hidden = true; loadInbox(); inboxTimer = setInterval(loadInbox, 5000); }
}
document.querySelectorAll('#nav button').forEach((b) => (b.onclick = () => setTab(b.dataset.tab)));

// Bearer-authenticated blob fetch (an <img src> cannot send the Authorization header).
const blobUrls = new Map();
async function blobFor(path) {
  if (blobUrls.has(path)) return blobUrls.get(path);
  const r = await api(path);
  if (r.status === 401) { unpair(); throw new Error('401'); }
  if (!r.ok) throw new Error(String(r.status));
  const b = await r.blob();
  const e = { blob: b, url: URL.createObjectURL(b) };
  blobUrls.set(path, e);
  return e;
}

async function loadShots() {
  if (view !== 'shots') return;
  try {
    const r = await api('/api/shots');
    if (r.status === 401) { unpair(); return; }
    if (!r.ok) throw new Error(String(r.status));
    const shots = (await r.json()).shots || [];
    $('shotsEmpty').hidden = shots.length > 0;
    const g = $('grid'); g.textContent = '';
    for (const s of shots) {
      const b = document.createElement('button'); b.setAttribute('aria-label', 'Screenshot ' + s.created);
      const img = document.createElement('img'); img.alt = ''; img.loading = 'lazy'; b.appendChild(img);
      blobFor('/api/shots/' + s.id).then((e) => { img.src = e.url; }).catch(() => {});
      b.onclick = () => openViewer(s);
      g.appendChild(b);
    }
    banner('');
  } catch (e) { banner('Mac asleep or offline — retrying…'); }
}

function extFor(type) { return ({ 'image/png': 'png', 'image/jpeg': 'jpg', 'image/gif': 'gif', 'image/webp': 'webp', 'image/heic': 'heic', 'image/heif': 'heif', 'image/tiff': 'tif' })[type] || 'png'; }
async function openViewer(s) {
  const path = '/api/shots/' + s.id;
  try {
    const e = await blobFor(path);
    viewerShot = { blob: e.blob, name: 'True-' + s.id + '.' + extFor(e.blob.type) };
    $('vBody').textContent = '';
    const img = document.createElement('img'); img.src = e.url; img.alt = 'Screenshot'; $('vBody').appendChild(img);
    $('vTitle').textContent = new Date(s.created).toLocaleString();
    $('viewer').hidden = false;
  } catch (x) { banner('Could not load that shot.'); setTimeout(() => banner(''), 3000); }
}
$('vClose').onclick = () => { $('viewer').hidden = true; viewerShot = null; };
async function shareBlob(blob, name) {
  const f = new File([blob], name, { type: blob.type || 'application/octet-stream' });
  if (navigator.canShare && navigator.canShare({ files: [f] })) {
    try { await navigator.share({ files: [f] }); } catch (e) { /* cancelled */ }
  } else saveBlob(blob, name);
}
function saveBlob(blob, name) {
  const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = name;
  document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(a.href), 10000);
}
$('vShare').onclick = () => viewerShot && shareBlob(viewerShot.blob, viewerShot.name);
$('vSave').onclick = () => viewerShot && saveBlob(viewerShot.blob, viewerShot.name);

// ----- inbox (Mac pushed to the phone) -----
async function loadInbox() {
  if (view !== 'send' || document.hidden) return;
  try {
    const r = await api('/api/inbox');
    if (r.status === 401) { unpair(); return; }
    if (!r.ok) throw new Error(String(r.status));
    const items = (await r.json()).items || [];
    seenInbox = new Set(items.map((i) => i.id));
    renderInbox(items); banner('');
  } catch (e) { /* next poll */ }
}
function btn(label, fn) { const b = document.createElement('button'); b.className = 'btn'; b.textContent = label; b.onclick = fn; return b; }
function renderInbox(items) {
  $('inboxBox').hidden = items.length === 0;
  const host = $('inbox'); host.textContent = '';
  for (const i of items) {
    const row = document.createElement('div'); row.className = 'item';
    const t = document.createElement('span'); t.className = 't';
    const n = document.createElement('span'); n.className = 'n'; n.textContent = i.kind === 'text' ? 'Clipboard' : i.name;
    const c = document.createElement('span'); c.className = 'c';
    c.textContent = i.kind === 'text' ? (i.preview || '') : fmtSize(i.size);
    t.append(n, c); row.appendChild(t);
    if (i.kind === 'text') {
      row.appendChild(btn('Copy', async () => {
        try { const e = await api('/api/inbox/' + i.id); await navigator.clipboard.writeText(await e.text()); flash(row, 'Copied'); }
        catch (x) { flash(row, 'Blocked'); }
      }));
    } else {
      row.appendChild(btn('Save', async () => {
        try { const e = await blobFor('/api/inbox/' + i.id); await shareBlob(e.blob, i.name); } catch (x) { flash(row, 'Failed'); }
      }));
    }
    row.appendChild(btn('✕', async () => {
      await api2('/api/inbox/' + i.id, 'DELETE'); blobUrls.delete('/api/inbox/' + i.id); loadInbox();
    }));
    row.lastChild.setAttribute('aria-label', 'Remove');
    host.appendChild(row);
  }
}
function flash(row, text) { const c = row.querySelector('.c'); if (c) c.textContent = text; }
function fmtSize(n) { return n > 1048576 ? (n / 1048576).toFixed(1) + ' MB' : Math.max(1, Math.round(n / 1024)) + ' KB'; }
function api2(path, method, body, headers) {
  return fetch(path, { method, cache: 'no-store', body, headers: Object.assign({ Authorization: 'Bearer ' + getToken() }, headers || {}) });
}
// A quiet dot on the Send tab when the Mac pushes something while we are elsewhere.
async function peekInbox() {
  if (view === 'send' || document.hidden || !getToken()) return;
  try {
    const r = await api('/api/inbox'); if (!r.ok) return;
    const items = (await r.json()).items || [];
    if (inboxLoaded && items.some((i) => !seenInbox.has(i.id))) $('dot').hidden = false;
    items.forEach((i) => seenInbox.add(i.id)); inboxLoaded = true;
  } catch (e) { /* offline */ }
}
setInterval(peekInbox, 15000);

// ----- upload (phone -> Mac) -----
$('pick').onclick = () => $('files').click();
$('files').onchange = () => { const fs = Array.from($('files').files); $('files').value = ''; fs.forEach(upload); };
function upload(file) {
  const row = document.createElement('div'); row.className = 'up';
  const n = document.createElement('div'); n.className = 'n';
  const nm = document.createElement('span'); nm.textContent = file.name || 'file';
  const st = document.createElement('span'); st.className = 'st'; st.textContent = '0%';
  n.append(nm, st);
  const pr = document.createElement('progress'); pr.max = 100; pr.value = 0;
  row.append(n, pr); $('uploads').prepend(row);
  const x = new XMLHttpRequest();
  x.open('POST', '/api/drop');
  x.setRequestHeader('Authorization', 'Bearer ' + getToken());
  x.setRequestHeader('X-Filename', encodeURIComponent(file.name || 'iPhone-upload'));
  x.upload.onprogress = (e) => { if (e.lengthComputable) { const p = Math.round((e.loaded / e.total) * 100); pr.value = p; st.textContent = p + '%'; } };
  const fail = (m) => { row.classList.add('bad'); st.textContent = m; pr.hidden = true; };
  x.onload = () => {
    if (x.status === 401) { unpair(); return; }
    if (x.status >= 200 && x.status < 300) { pr.value = 100; st.textContent = 'Sent ✓'; setTimeout(() => row.remove(), 6000); }
    else fail(({ 413: 'Too big (200 MB max)', 507: 'Mac disk is full', 408: 'Timed out' })[x.status] || 'Failed (' + x.status + ')');
  };
  x.onerror = () => fail('Mac unreachable');
  x.send(file);
}

$('clipSend').onclick = async () => {
  const t = $('clipText').value; if (!t) return;
  const note = $('clipNote'); note.textContent = 'Sending…';
  try {
    const r = await api2('/api/clip', 'POST', JSON.stringify({ text: t }), { 'Content-Type': 'application/json' });
    if (r.status === 401) { unpair(); return; }
    if (r.ok) { note.textContent = 'On the Mac clipboard ✓'; $('clipText').value = ''; }
    else note.textContent = r.status === 413 ? 'Too long (256 KB max).' : 'Failed (' + r.status + ')';
  } catch (e) { note.textContent = 'Mac unreachable.'; }
};

setInterval(loadList, 3000);
if (getToken()) start(); else unpair();
