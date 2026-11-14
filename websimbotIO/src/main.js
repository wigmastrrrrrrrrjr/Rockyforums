import './style.css';
import '@fontsource/caveat/400.css';
import '@fontsource/caveat/700.css';
import '@fontsource/cabin-sketch/400.css';
import '@fontsource/cabin-sketch/700.css';

import { Net } from './net.js';
import { Input } from './input.js';
import { Sfx } from './audio.js';
import { TUNING, ARENA, speedFor } from './config.js';
import { paintDomPaper, paintPaperCanvas, sketchPath } from './render/paper.js';
import {
  buildDecor, drawArena, drawPlayer, drawBullet, drawInkSplat, drawOffscreenMarkers,
} from './render/arena.js';

/* ------------------------------------------------------------------ boot -- */
const canvas = document.getElementById('game');
const ctx = canvas.getContext('2d');
const net = new Net();
const input = new Input(canvas);
const sfx = new Sfx();

paintDomPaper();
let resizeTimer = 0;
addEventListener('resize', () => {
  resize();
  clearTimeout(resizeTimer);
  resizeTimer = setTimeout(paintDomPaper, 220);
});

const state = {
  running: false,
  world: { ...ARENA },
  players: [],
  bullets: [],
  decor: [],
  self: null,
  selfId: null,
  dead: false,
  deathAt: 0,
  respawnIn: 0,
  snapshotAt: 0,
  serverOffset: 0,
  renderPlayers: new Map(),
  splats: [],
  floaters: [],
  shake: 0,
  zoom: 1,
  camX: 0,
  camY: 0,
  lastShot: 0,
  corrections: 0,
  correctionFlash: 0,
  lastSeenKills: 0,
  lastSeenDeaths: 0,
  streak: 0,
  bestStreak: 0,
  myMass: TUNING.baseMass,
};

let view = { w: 0, h: 0, dpr: 1 };

function resize() {
  view.dpr = Math.min(2, devicePixelRatio || 1);
  view.w = innerWidth;
  view.h = innerHeight;
  canvas.width = Math.floor(view.w * view.dpr);
  canvas.height = Math.floor(view.h * view.dpr);
  canvas.style.width = view.w + 'px';
  canvas.style.height = view.h + 'px';
}
resize();

/* ----------------------------------------------------------------- lobby -- */
const lobby = document.getElementById('lobby');
const lobbyNote = document.getElementById('lobby-note');
const inCall = document.getElementById('in-call');
const inRoom = document.getElementById('in-room');

inCall.value = localStorage.getItem('wsb.call') || '';
inRoom.value = new URLSearchParams(location.search).get('room') || localStorage.getItem('wsb.room') || 'main';
setTimeout(() => inCall.focus(), 300);

// Peek at the room before joining: how busy is this page right now?
async function peekRoom() {
  const el = document.getElementById('lobby-ping');
  const room = (inRoom.value || 'main').toLowerCase().trim();
  try {
    const { createClient } = await import('@supabase/supabase-js');
    const { SUPABASE_URL, SUPABASE_KEY } = await import('./config.js');
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    const t0 = performance.now();
    const { data } = await sb.rpc('wsb_room', { p_room: room });
    const ms = Math.round(performance.now() - t0);
    if (!data) { el.textContent = ''; return; }
    el.textContent = data.state === 'live' && data.players
      ? `${data.players} in "${room}" · ${ms} ms`
      : `"${room}" is blank · ${ms} ms`;
  } catch {
    el.textContent = '';
  }
}
let peekTimer = 0;
inRoom.addEventListener('input', () => {
  clearTimeout(peekTimer);
  peekTimer = setTimeout(peekRoom, 500);
});
setTimeout(peekRoom, 600);

document.getElementById('btn-play').addEventListener('click', startGame);
for (const el of [inCall, inRoom]) {
  el.addEventListener('keydown', (e) => { if (e.key === 'Enter') startGame(); });
}

async function startGame() {
  sfx.unlock();
  sfx.ui();
  const call = (inCall.value || '').trim() || randomCall();
  const room = ((inRoom.value || '').trim() || 'main').toLowerCase().replace(/[^a-z0-9-_]/g, '').slice(0, 18) || 'main';
  localStorage.setItem('wsb.call', call);
  localStorage.setItem('wsb.room', room);
  const url = new URL(location.href);
  url.searchParams.set('room', room);
  history.replaceState(null, '', url);

  const btn = document.getElementById('btn-play');
  btn.disabled = true;
  btn.textContent = 'sharpening pencils…';
  lobbyNote.textContent = '';

  try {
    const data = await net.join(room, call);
    state.selfId = data.player_id;
    state.world = { ...ARENA };
    state.decor = buildDecor(room, state.world);
    state.running = true;
    net.onTick = () => pumpNow();
    lobby.classList.add('hidden');
    document.getElementById('hud').classList.remove('hidden');
    document.getElementById('hud-call').textContent = data.call;
    pumpNow();
    requestAnimationFrame(frame);
  } catch (e) {
    btn.disabled = false;
    btn.textContent = 'start scribbling';
    lobbyNote.textContent = e.message;
  }
}

function randomCall() {
  const a = ['sketchy', 'nib', 'blot', 'inky', 'shade', 'smudge', 'doodle'];
  return a[Math.floor(Math.random() * a.length)] + (Math.floor(Math.random() * 90) + 10);
}

/* ------------------------------------------------------------------- net -- */
net.onSnapshot = (snap) => {
  if (state.world.w !== snap.world.w || state.world.h !== snap.world.h) {
    state.world = { w: snap.world.w, h: snap.world.h };
    state.decor = buildDecor(net.room, state.world);
  }
  state.world = { w: snap.world.w, h: snap.world.h };
  state.players = snap.players;
  state.bullets = snap.bullets;
  state.snapshotAt = performance.now();
  state.serverOffset = Date.now() - Number(snap.server_ms);
  state.matchState = snap.state;
  state.winner = snap.winner;

  const me = snap.players.find((p) => p.id === state.selfId);
  if (me) {
    state.self = reconcile(me);
    state.myMass = me.mass;

    if (me.kills > state.lastSeenKills) {
      sfx.kill();
      floater('+' + (me.kills - state.lastSeenKills) + ' kill', '#2f5f43');
      state.lastSeenKills = me.kills;
    }
    if (me.deaths > state.lastSeenDeaths) {
      onDeath(me);
      state.lastSeenDeaths = me.deaths;
    }
    state.respawnIn = me.respawn_ms || 0;
    if (me.alive && state.dead) {
      state.dead = false;
      document.getElementById('respawn').classList.add('hidden');
    }
    if (!me.alive && !state.dead) {
      onDeath(me);
    }
    if (me.alive) {
      state.dead = false;
      state.respawnIn = 0;
    }
  } else if (state.selfId && snap.players.length && !snap.players.some((p) => p.id === state.selfId)) {
    // we were culled: the match ended or we idled out
    showToast('you drifted out of the sketchbook — reloading…');
    setTimeout(() => location.reload(), 2500);
  }

  handleEvents(snap.events || []);
  updateHud(snap, true);
};

function reconcile(me) {
  const prev = state.self;

  // First snapshot, or we just came back to life: take the server's word.
  if (!prev || !me.alive || !prev.alive) return me;

  const dx = me.x - prev.x;
  const dy = me.y - prev.y;
  const err = Math.hypot(dx, dy);

  // Our own walk is simulated locally, so a few px of drift is just tick
  // alignment. A big gap means the server refused something (or we were
  // pushed), and the server wins outright.
  if (err > 70) {
    state.lastSnapAt = performance.now();
    state.corrections++;
    state.correctionFlash = 1;
    net.corrections++;
    floater('snapped back', '#a63a2a', me.x, me.y - 40);
    return me;
  }

  // Otherwise settle toward the server over a few snapshots so walking stays
  // buttery instead of stuttering on every packet.
  const t = err > 3 ? 0.3 : 1;
  me.x = prev.x + dx * t;
  me.y = prev.y + dy * t;
  return me;
}

function handleEvents(events) {
  for (const e of events) {
    if (e.kind === 'kill') {
      if (e.actor !== state.self?.call) {
        addFeed(`${e.actor} scribbled out ${e.target}`);
      } else {
        addFeed(`you scribbled out ${e.target}`);
        const p = state.players.find((q) => q.call === e.target);
        if (p) {
          state.splats.push({ x: e.x, y: e.y, size: p.radius * 1.5, born: performance.now(), seed: p.hue });
        }
      }
      if (e.target === state.self?.call) {
        state.splats.push({ x: e.x, y: e.y, size: 26, born: performance.now(), seed: 1 });
        state.shake = Math.min(1, state.shake + 0.9);
      }
    } else if (e.kind === 'hit') {
      if (e.target === state.self?.call) {
        sfx.hit();
        state.shake = Math.min(1, state.shake + 0.35);
        floater('-' + Math.round(e.amount), '#a63a2a', e.x, e.y - 10);
      } else if (e.actor === state.self?.call) {
        sfx.hit();
        floater('-' + Math.round(e.amount), '#5b564a', e.x, e.y - 10);
      }
    } else if (e.kind === 'join') {
      if (e.actor !== state.self?.call) { addFeed(`${e.actor} wandered in`); sfx.join(); }
    } else if (e.kind === 'respawn') {
      if (e.actor === state.self?.call) {
        state.self.x = e.x;
        state.self.y = e.y;
      }
    }
  }
}

async function reloadGame() {
  clearInterval(net.timer);
  const room = net.room;
  const call = localStorage.getItem('wsb.call') || '';
  state.overHandled = false;
  state.lastSeenKills = 0;
  state.lastSeenDeaths = 0;
  state.splats = [];
  try {
    const data = await net.join(room, call);
    state.selfId = data.player_id;
    state.self = null;
    state.dead = false;
    state.deathAt = 0;
    state.players = [];
    state.bullets = [];
    document.getElementById('respawn').classList.add('hidden');
    document.getElementById('feed').innerHTML = '';
    net.onTick = () => pumpNow();
    pumpNow();
  } catch {
    showToast('lost the page — reload to keep playing');
  }
}

function onDeath(me) {
  if (state.dead) return;
  state.dead = true;
  state.deathAt = performance.now();
  sfx.death();
  state.shake = 1;
  state.splats.push({ x: me.x, y: me.y, size: me.radius * 1.8, born: performance.now(), seed: me.hue });
  const r = document.getElementById('respawn');
  r.classList.remove('hidden');
  document.getElementById('respawn-sub').textContent = 'tap to respawn';
  state.lastSeenDeaths = Math.max(state.lastSeenDeaths, me.deaths);
}

document.getElementById('respawn').addEventListener('click', async () => {
  sfx.ui();
  if (state.respawnIn > 250) { showToast('hold on — ' + Math.ceil(state.respawnIn / 1000) + 's'); return; }
  const res = await net.respawn();
  if (res?.ok) {
    state.dead = false;
    state.self.x = res.x;
    state.self.y = res.y;
    state.self.hp = TUNING.hpMax;
    document.getElementById('respawn').classList.add('hidden');
  } else if (res?.error === 'wait') {
    showToast('not yet — ' + Math.ceil(res.in_ms / 1000) + 's');
  }
});

/* -------------------------------------------------------------------- fx -- */
function floater(text, color, x = null, y = null) {
  const me = state.self;
  state.floaters.push({
    text, color,
    x: x ?? (me ? me.x : 0),
    y: y ?? (me ? me.y - 40 : 0),
    born: performance.now(),
  });
}

function addFeed(text) {
  const feed = document.getElementById('feed');
  const el = document.createElement('div');
  el.className = 'feed-item';
  el.textContent = text;
  feed.appendChild(el);
  setTimeout(() => el.classList.add('fade'), 3800);
  setTimeout(() => el.remove(), 5200);
  while (feed.children.length > 5) feed.firstChild.remove();
}

let toastTimer = 0;
function showToast(msg) {
  const t = document.getElementById('toast');
  t.textContent = msg;
  t.classList.remove('hidden');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.classList.add('hidden'), 2200);
}

/* -------------------------------------------------------------------- hud -- */
let hudTick = 0;
function updateHud(snap, force = false) {
  const me = state.self;
  if (!me) return;
  const now = performance.now();
  if (now - hudTick < 90 && !force) return;
  hudTick = now;

  document.getElementById('hud-kd').textContent = `${me.kills}k / ${me.deaths}d`;
  if (state.dead) {
    const sub = document.getElementById('respawn-sub');
    const btn = document.getElementById('respawn');
    if (state.respawnIn > 250) {
      sub.textContent = 'wait ' + Math.ceil(state.respawnIn / 1000) + '…';
      btn.classList.add('waiting');
    } else {
      sub.textContent = 'tap to respawn';
      btn.classList.remove('waiting');
    }
  }
  document.getElementById('hud-size').textContent = 'size ' + Math.round(me.radius);

  const hp = Math.max(0, me.hp);
  document.getElementById('hp-bar').style.width = Math.max(2, (hp / TUNING.hpMax) * 100) + '%';
  document.getElementById('hp-num').textContent = Math.round(hp);
  document.getElementById('hp-bar').dataset.tier = hp > 55 ? 'ok' : hp > 28 ? 'low' : 'crit';

  document.getElementById('hud-ping').textContent = net.connected ? net.ping + ' ms' : 'offline';

  const list = document.getElementById('board-list');
  const sorted = [...snap.players].sort((a, b) => b.kills - a.kills || b.mass - a.mass).slice(0, 6);
  list.innerHTML = '';
  for (const p of sorted) {
    const li = document.createElement('li');
    if (p.id === state.selfId) li.className = 'me';
    const name = document.createElement('span');
    name.className = 'nm';
    name.textContent = p.call;
    name.style.color = `hsl(${p.hue} 45% 32%)`;
    const k = document.createElement('span');
    k.className = 'k';
    k.textContent = p.kills + '·' + Math.round(p.radius);
    li.append(name, k);
    list.appendChild(li);
  }
  document.getElementById('board-count').textContent = snap.players.filter((p) => p.alive).length;

  if (snap.state === 'over' && !state.overHandled) {
    state.overHandled = true;
    showToast((snap.winner || 'somebody') + ' won the page — starting a new one…');
    setTimeout(() => { if (state.running) reloadGame(); }, 6500);
  }
}

/* --------------------------------------------------------------- predict -- */
// The local walk. Called every rAF *and* right before each network pump so the
// claim we send matches what the player sees.
let lastFrame = performance.now();
let lastPump = 0;
let inputState = { fx: 0, fy: 0, aim: 0, shoot: false, moving: false };

function stepPrediction(dt) {
  const me = state.self;
  if (!me) return;

  inputState = input.sample(me, performance.now());
  // If there is no mouse and no aim stick, borrow the nearest target so the
  // game is still playable on a keyboard alone.
  const hasPointer = input.pointer.active && !input.touchMode;
  if (hasPointer) {
    const wx = state.camX + (input.pointer.x - view.w / 2) / state.zoom;
    const wy = state.camY + (input.pointer.y - view.h / 2) / state.zoom;
    inputState.aim = Math.atan2(wy - me.y, wx - me.x);
  } else if (!input.touch.aim.active) {
    inputState.aim = input.autoAim(me, state.players);
  }

  if (!me.alive) return;

  const speed = speedFor(me.radius);
  me.x += inputState.fx * speed * dt;
  me.y += inputState.fy * speed * dt;

  const r = me.radius;
  me.x = Math.min(state.world.w - r, Math.max(r, me.x));
  me.y = Math.min(state.world.h - r, Math.max(r, me.y));
  me.aim = inputState.aim;

  if (inputState.shoot) {
    const now = performance.now();
    const cooldown = (TUNING.tickMs * 6) / 1000;
    if (now - state.lastShot > cooldown) {
      state.lastShot = now;
      sfx.shoot();
    }
  }
}

function pumpNow() {
  if (!state.running) return;
  const now = performance.now();
  if (now - lastPump < 60) return;
  lastPump = now;
  const me = state.self;
  net.pump({
    fx: inputState.fx,
    fy: inputState.fy,
    aim: me ? me.aim : 0,
    shoot: inputState.shoot && !!me?.alive,
    x: me ? me.x : null,
    y: me ? me.y : null,
  });
}

/* ------------------------------------------------------------------- loop -- */
function frame(now) {
  if (!state.running) return;
  const dt = Math.min(0.05, (now - lastFrame) / 1000);
  lastFrame = now;

  stepPrediction(dt);
  if (now - lastPump > 100) pumpNow();

  render(now);
  requestAnimationFrame(frame);
}

function render(now) {
  const me = state.self;
  const dpr = view.dpr;
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

  // camera
  const targetZoom = me
    ? Math.max(0.66, Math.min(1.12, 1.08 - (me.radius - TUNING.baseRadius) * 0.010))
    : 1;
  state.zoom += (targetZoom - state.zoom) * 0.06;
  const tx = me ? me.x : state.world.w / 2;
  const ty = me ? me.y : state.world.h / 2;
  state.camX += (tx - state.camX) * 0.16;
  state.camY += (ty - state.camY) * 0.16;

  const shake = state.shake * 9;
  state.shake = Math.max(0, state.shake - 0.045);
  const sx = (Math.random() - 0.5) * shake;
  const sy = (Math.random() - 0.5) * shake;

  const cam = { x: state.camX, y: state.camY, w: view.w, h: view.h, zoom: state.zoom };

  // paper for the world (cached per size)
  if (!state.paper || state.paperW !== view.w || state.paperH !== view.h) {
    state.paper = paintPaperCanvas(view.w + 40, view.h + 40);
    state.paperW = view.w;
    state.paperH = view.h;
  }
  ctx.drawImage(state.paper, -20, -20);
  ctx.save();
  if (state.dead) ctx.filter = 'grayscale(0.75) contrast(0.92)';

  drawArena(ctx, cam, state.world, state.decor, now);

  ctx.save();
  ctx.translate(view.w / 2 + sx, view.h / 2 + sy);
  ctx.scale(state.zoom, state.zoom);
  ctx.translate(-cam.x, -cam.y);

  // splats under everything
  for (const s of state.splats) {
    const age = (now - s.born) / 2600;
    if (age > 1) continue;
    drawInkSplat(ctx, s.x, s.y, s.size, age, s.seed);
  }
  state.splats = state.splats.filter((s) => now - s.born < 2600);

  // bullets: extrapolate from the last snapshot so 10 Hz looks like 60 fps
  const bAge = Math.min(0.14, (now - state.snapshotAt) / 1000);
  for (const b of state.bullets) {
    drawBullet(ctx, {
      x: b.x + b.vx * bAge,
      y: b.y + b.vy * bAge,
      vx: b.vx,
      vy: b.vy,
    });
  }

  // players, ours on top, dead ones as ghosts
  const list = [...state.players];
  if (me && !list.some((p) => p.id === state.selfId)) list.push(me);

  for (const p of list) {
    if (p.id === state.selfId) continue;
    if (!p.alive) continue;
    const rp = state.renderPlayers.get(p.id) || { x: p.x, y: p.y, hp: p.hp, flash: 0 };
    const k = 0.35;
    rp.x += (p.x - rp.x) * k;
    rp.y += (p.y - rp.y) * k;
    rp.hp = p.hp;
    rp.flash = Math.max(0, rp.flash - 0.06);
    state.renderPlayers.set(p.id, rp);
    if (state.renderPlayers.size > 60) state.renderPlayers.clear();

    drawPlayer(ctx, {
      ...p,
      call: p.bot ? p.call + ' ·bot' : p.call,
      x: rp.x,
      y: rp.y,
    }, { isSelf: false, time: now, flash: rp.flash, shake: 0 });
  }

  // local player drawn from the *predicted* position
  if (me && me.alive) {
    drawPlayer(ctx, me, {
      isSelf: true,
      time: now,
      flash: Math.max(0, 1 - (now - state.lastShot) / 120),
      shake: 0,
    });
  }

  // floating numbers
  for (const f of state.floaters) {
    const t = (now - f.born) / 900;
    if (t > 1) continue;
    ctx.save();
    ctx.globalAlpha = 1 - t;
    ctx.font = '700 22px Caveat, cursive';
    ctx.textAlign = 'center';
    ctx.fillStyle = f.color;
    ctx.fillText(f.text, f.x, f.y - t * 34);
    ctx.restore();
  }
  state.floaters = state.floaters.filter((f) => now - f.born < 900);

  ctx.restore();

  // off-screen markers + correction vignette
  drawOffscreenMarkers(ctx, cam, state.players, state.selfId, state.world);

  if (state.correctionFlash > 0) {
    ctx.save();
    ctx.globalAlpha = state.correctionFlash * 0.35;
    ctx.strokeStyle = '#a63a2a';
    ctx.lineWidth = 8;
    ctx.strokeRect(4, 4, view.w - 8, view.h - 8);
    ctx.restore();
    state.correctionFlash = Math.max(0, state.correctionFlash - 0.02);
  }

  ctx.restore();

  drawFrameOutline(ctx, view, now);
}

// A hand-drawn border on the page, so the UI feels like it belongs on paper.
function drawFrameOutline(ctx, v, now) {
  ctx.save();
  ctx.globalAlpha = 0.5;
  sketchPath(ctx, [[8, 8], [v.w - 8, 8], [v.w - 8, v.h - 8], [8, v.h - 8]], {
    seed: Math.floor(now / 700), close: true, width: 1.4, wobble: 2.4, color: '#5b564a', passes: 1,
  });
  ctx.restore();
}

/* ------------------------------------------------------------------- ui --- */
document.getElementById('btn-help').addEventListener('click', () => {
  document.getElementById('help').classList.remove('hidden');
});
document.getElementById('help-close').addEventListener('click', () => {
  document.getElementById('help').classList.add('hidden');
});
addEventListener('keydown', (e) => {
  if (e.key === 'Escape') document.getElementById('help').classList.add('hidden');
});
addEventListener('beforeunload', () => { net.leave(); });

// HUD class for touch layout
if (matchMedia('(pointer: coarse)').matches) document.body.classList.add('touch');
