// The arena and everything in it, drawn like it's a page in someone's notebook.
import { sketchBlob, sketchHatch, sketchPath, mulberry32, hashSeed } from './paper.js';
import { inkFor, washFor, TUNING } from '../config.js';

const INK = '#2b2a26';
const INK_SOFT = '#5b564a';

// Static doodles for a room. Seeded by room name so everyone sees the same
// squiggles in the same corners.
export function buildDecor(room, world) {
  const rnd = mulberry32(hashSeed('decor:' + room));
  const items = [];
  const kinds = ['star', 'arrow', 'spiral', 'note', 'cross', 'clip', 'smudge', 'grass', 'blob', 'rule'];
  const count = 120;
  for (let i = 0; i < count; i++) {
    const kind = kinds[Math.floor(rnd() * kinds.length)];
    items.push({
      kind,
      x: 60 + rnd() * (world.w - 120),
      y: 60 + rnd() * (world.h - 120),
      s: 12 + rnd() * 26,
      rot: rnd() * Math.PI * 2,
      seed: Math.floor(rnd() * 1e9),
      tone: rnd(),
    });
  }
  // a few big, pale stains so the paper reads as used
  for (let i = 0; i < 14; i++) {
    items.push({
      kind: 'stain',
      x: rnd() * world.w,
      y: rnd() * world.h,
      s: 70 + rnd() * 160,
      rot: rnd() * Math.PI,
      seed: Math.floor(rnd() * 1e9),
      tone: rnd(),
    });
  }
  return items;
}

function drawDecorItem(ctx, d) {
  const { kind, x, y, s, rot, seed } = d;
  ctx.save();
  ctx.translate(x, y);
  ctx.rotate(rot);

  if (kind === 'stain') {
    ctx.globalAlpha = 0.05;
    ctx.fillStyle = '#a89674';
    ctx.beginPath();
    const rnd = mulberry32(seed);
    for (let i = 0; i < 9; i++) {
      const a = (i / 9) * Math.PI * 2;
      const r = s * (0.55 + rnd() * 0.5);
      const px = Math.cos(a) * r;
      const py = Math.sin(a) * r * 0.8;
      if (i === 0) ctx.moveTo(px, py);
      else ctx.arcTo(px, py, px * 0.7, py * 0.7, r * 0.6);
    }
    ctx.closePath();
    ctx.fill();
    ctx.restore();
    return;
  }

  ctx.globalAlpha = 0.32;
  ctx.strokeStyle = d.tone > 0.86 ? '#8d5f3c' : INK_SOFT;

  if (kind === 'star') {
    const pts = [];
    for (let i = 0; i < 5; i++) {
      const a1 = (i / 5) * Math.PI * 2 - Math.PI / 2;
      const a2 = a1 + Math.PI / 5;
      pts.push([Math.cos(a1) * s, Math.sin(a1) * s]);
      pts.push([Math.cos(a2) * s * 0.42, Math.sin(a2) * s * 0.42]);
    }
    sketchPath(ctx, pts, { seed, close: true, width: 1.6, wobble: 1.4, passes: 1 });
  } else if (kind === 'arrow') {
    sketchPath(ctx, [[-s, 0], [s, 0]], { seed, width: 2, wobble: 1.2, passes: 1 });
    sketchPath(ctx, [[s * 0.5, -s * 0.4], [s, 0], [s * 0.5, s * 0.4]], { seed: seed + 1, width: 2, wobble: 1.2, passes: 1 });
  } else if (kind === 'spiral') {
    const pts = [];
    for (let i = 0; i < 34; i++) {
      const a = i * 0.42;
      const r = (i / 34) * s;
      pts.push([Math.cos(a) * r, Math.sin(a) * r]);
    }
    sketchPath(ctx, pts, { seed, width: 1.4, wobble: 0.9, passes: 1 });
  } else if (kind === 'cross') {
    sketchPath(ctx, [[-s * 0.6, -s * 0.6], [s * 0.6, s * 0.6]], { seed, width: 1.8, wobble: 1.3, passes: 1 });
    sketchPath(ctx, [[s * 0.6, -s * 0.6], [-s * 0.6, s * 0.6]], { seed: seed + 2, width: 1.8, wobble: 1.3, passes: 1 });
  } else if (kind === 'clip') {
    ctx.beginPath();
    ctx.ellipse(0, 0, s * 0.55, s * 0.28, 0.4, 0, Math.PI * 1.7);
    ctx.lineWidth = 1.6;
    ctx.stroke();
  } else if (kind === 'note') {
    const pts = [[-s * 0.7, -s * 0.5], [s * 0.7, -s * 0.5], [s * 0.7, s * 0.5], [-s * 0.7, s * 0.5]];
    sketchPath(ctx, pts, { seed, close: true, width: 1.3, wobble: 1.1, passes: 1 });
    sketchPath(ctx, [[-s * 0.5, -s * 0.12], [s * 0.5, -s * 0.12]], { seed: seed + 3, width: 1, wobble: 1, passes: 1 });
    sketchPath(ctx, [[-s * 0.5, s * 0.16], [s * 0.2, s * 0.16]], { seed: seed + 4, width: 1, wobble: 1, passes: 1 });
  } else if (kind === 'grass') {
    for (let i = -1; i <= 1; i++) {
      sketchPath(ctx, [[i * s * 0.32, 0], [i * s * 0.42 + s * 0.12, -s * 0.7]], { seed: seed + i, width: 1.4, wobble: 1.1, passes: 1 });
    }
  } else if (kind === 'blob') {
    const pts = [];
    const rr = mulberry32(seed);
    for (let i = 0; i < 7; i++) {
      const a = (i / 7) * Math.PI * 2;
      const q = s * (0.4 + rr() * 0.5);
      pts.push([Math.cos(a) * q, Math.sin(a) * q]);
    }
    sketchPath(ctx, pts, { seed, close: true, width: 1.5, wobble: 2.2, passes: 1 });
  } else if (kind === 'rule') {
    for (let i = 0; i < 3; i++) {
      sketchPath(ctx, [[-s, i * 5 - 5], [s, i * 5 - 5 + (mulberry32(seed + i)() - 0.5) * 2]], {
        seed: seed + i, width: 1.2, wobble: 1.1, passes: 1,
      });
    }
  } else if (kind === 'smudge') {
    ctx.globalAlpha = 0.1;
    ctx.fillStyle = INK_SOFT;
    ctx.beginPath();
    ctx.ellipse(0, 0, s * 0.9, s * 0.4, 0.3, 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.restore();
}

/** One player, drawn as a wobbly blob with a face and a pencil barrel. */
export function drawPlayer(ctx, p, opts) {
  const {
    isSelf = false,
    time = 0,
    flash = 0,
    shake = 0,
    spawnGhost = 0,
  } = opts;

  const r = p.radius;
  const seed = hashSeed(p.id) + Math.floor(r) * 7;
  const bob = Math.sin(time * 0.008 + seed % 100) * (r * 0.02);
  const squash = 1 + Math.sin(time * 0.008 + seed % 100) * 0.03;
  const ink = inkFor(p.hue);
  const wash = washFor(p.hue);

  ctx.save();
  ctx.translate(p.x + shake, p.y + shake);

  // ground shadow: a scribbled ellipse
  ctx.save();
  ctx.globalAlpha = 0.16;
  ctx.fillStyle = INK;
  ctx.beginPath();
  ctx.ellipse(r * 0.06, r * 0.62, r * 0.98, r * 0.42, 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();

  // muzzle flash
  if (flash > 0) {
    ctx.save();
    ctx.globalAlpha = Math.min(1, flash);
    ctx.translate(Math.cos(p.aim) * (r + 12), Math.sin(p.aim) * (r + 12));
    ctx.rotate(p.aim);
    sketchPath(ctx, [[0, 0], [18 + flash * 16, -8], [12, 0], [19 + flash * 14, 8]], {
      seed: Math.floor(time / 40), color: '#b6542f', width: 2.4, wobble: 2, passes: 1,
    });
    ctx.restore();
  }

  // barrel
  ctx.save();
  ctx.translate(Math.cos(p.aim) * r * 0.5, Math.sin(p.aim) * r * 0.5);
  ctx.rotate(p.aim);
  ctx.globalAlpha = 1;
  sketchPath(ctx, [
    [0, -r * 0.26], [r * 0.95, -r * 0.2], [r * 1.05, r * 0.2], [0, r * 0.26],
  ], {
    seed: seed + 5, close: true, color: INK, width: Math.max(1.8, r * 0.09), wobble: 1.2,
  });
  ctx.restore();

  // body
  sketchBlob(ctx, 0, bob, r, {
    seed, fill: wash, color: ink, width: Math.max(1.8, r * 0.11), wobble: r * 0.09, squash,
  });
  sketchHatch(ctx, 0, bob, r * 0.98, {
    seed: seed + 11,
    gap: Math.max(5, r * 0.24),
    alpha: 0.2,
    angle: 0.9 + (p.hue % 30) / 100,
  });
  // a second, crossed hatch pass on the belly gives them volume
  ctx.save();
  ctx.beginPath();
  ctx.arc(0, bob, r * 0.95, 0.15, Math.PI - 0.15);
  ctx.clip();
  sketchHatch(ctx, 0, bob + r * 0.35, r * 0.85, {
    seed: seed + 13, gap: Math.max(6, r * 0.3), alpha: 0.12, angle: -0.5,
  });
  ctx.restore();

  // eyes look toward the aim
  const ex = Math.cos(p.aim) * r * 0.16;
  const ey = Math.sin(p.aim) * r * 0.16;
  const eyeR = Math.max(1.5, r * 0.13);
  for (const side of [-1, 1]) {
    const ox = Math.cos(p.aim + Math.PI / 2) * r * 0.3 * side;
    const oy = Math.sin(p.aim + Math.PI / 2) * r * 0.3 * side;
    ctx.save();
    ctx.globalAlpha = 0.92;
    ctx.fillStyle = INK;
    ctx.beginPath();
    ctx.arc(ox + ex, oy + ey + bob, eyeR, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
  }

  // hit flash + low hp: red ring
  if (flash > 0 || p.hp < 35) {
    ctx.save();
    ctx.globalAlpha = flash > 0 ? 0.75 * flash : 0.28 + 0.14 * Math.sin(time * 0.012);
    sketchBlob(ctx, 0, bob, r + 5, {
      seed: seed + 21, color: '#a63a2a', width: 2, wobble: 2.6,
    });
    ctx.restore();
  }

  // health arc above the head
  const w = Math.max(26, r * 2);
  const hp = Math.max(0, Math.min(1, p.hp / TUNING.hpMax));
  ctx.save();
  ctx.globalAlpha = 0.9;
  ctx.strokeStyle = hp > 0.55 ? '#4e7a45' : hp > 0.28 ? '#a5761f' : '#a63a2a';
  ctx.lineWidth = 3;
  ctx.beginPath();
  ctx.moveTo(-w / 2, -r - 15);
  ctx.lineTo(-w / 2 + w * hp, -r - 15 + Math.sin(time * 0.01) * 0.8);
  ctx.stroke();
  ctx.globalAlpha = 0.35;
  ctx.strokeStyle = INK;
  ctx.lineWidth = 1.2;
  ctx.beginPath();
  ctx.moveTo(-w / 2 - 2, -r - 12);
  ctx.lineTo(w / 2 + 2, -r - 12);
  ctx.stroke();
  ctx.restore();

  // name tag
  ctx.save();
  ctx.globalAlpha = isSelf ? 1 : 0.9;
  ctx.font = `${Math.max(13, Math.min(22, 11 + r * 0.26))}px Caveat, "Segoe Print", cursive`;
  ctx.textAlign = 'center';
  ctx.fillStyle = isSelf ? '#1f1d1a' : INK_SOFT;
  ctx.fillText(p.call, 0, -r - 22);
  if (isSelf) {
    // a small tick under your own name, so you can find yourself instantly
    ctx.globalAlpha = 0.8;
    ctx.strokeStyle = '#a63a2a';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(-8, -r - 16);
    ctx.lineTo(8, -r - 16.6);
    ctx.stroke();
  }
  ctx.restore();

  ctx.restore();
}

export function drawBullet(ctx, b) {
  const ang = Math.atan2(b.vy, b.vx);
  const len = 26;
  ctx.save();
  ctx.translate(b.x, b.y);
  ctx.rotate(ang);

  // the ink streak behind the round
  ctx.globalAlpha = 0.22;
  ctx.strokeStyle = '#2b2a26';
  ctx.lineWidth = 5;
  ctx.beginPath();
  ctx.moveTo(-len * 0.6, 0);
  ctx.lineTo(-len * 1.9, 0);
  ctx.stroke();

  // the round itself: a short, solid stroke with a taper
  ctx.globalAlpha = 0.95;
  ctx.strokeStyle = '#1f1d1a';
  ctx.lineWidth = 3;
  ctx.lineCap = 'round';
  ctx.beginPath();
  ctx.moveTo(-len * 0.55, 0);
  ctx.lineTo(len * 0.25, 0);
  ctx.stroke();

  ctx.globalAlpha = 0.9;
  ctx.fillStyle = '#1f1d1a';
  ctx.beginPath();
  ctx.arc(len * 0.3, 0, 1.9, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();
}

export function drawInkSplat(ctx, x, y, size, age, hueSeed = 0) {
  const life = Math.min(1, age);
  if (life >= 1) return;
  const rnd = mulberry32(hashSeed('splat' + x + y));
  ctx.save();
  ctx.globalAlpha = (1 - life) * 0.32;
  ctx.fillStyle = ['#2b2a26', '#7a4a30', '#3a4a5a'][Math.abs(hueSeed) % 3];
  ctx.translate(x, y);
  const s = size * (0.6 + life * 0.7);
  for (let i = 0; i < 7; i++) {
    const a = rnd() * Math.PI * 2;
    const d = rnd() * s * 1.6;
    ctx.beginPath();
    ctx.arc(Math.cos(a) * d, Math.sin(a) * d, s * (0.12 + rnd() * 0.3), 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.restore();
}

export function drawArena(ctx, cam, world, decor, t) {
  const { x: cx, y: cy, w, h, zoom } = cam;

  // paper ground already behind everything; here we draw the arena border
  ctx.save();
  ctx.translate(-cx * zoom + w / 2, -cy * zoom + h / 2);
  ctx.scale(zoom, zoom);

  // decor is culled to the viewport
  const pad = 140;
  const vx0 = cx - w / 2 / zoom - pad;
  const vx1 = cx + w / 2 / zoom + pad;
  const vy0 = cy - h / 2 / zoom - pad;
  const vy1 = cy + h / 2 / zoom + pad;

  for (const d of decor) {
    if (d.x < vx0 || d.x > vx1 || d.y < vy0 || d.y > vy1) continue;
    drawDecorItem(ctx, d);
  }

  // arena wall: double sketch line with tick marks
  const wall = [[0, 0], [world.w, 0], [world.w, world.h], [0, world.h]];
  sketchPath(ctx, wall, { seed: 4242, close: true, width: 3.4, wobble: 2.6, color: INK, passes: 2 });
  sketchPath(ctx, wall.map(([x, y]) => [x * 0.997 + 3, y * 0.997 + 3]), {
    seed: 99, close: true, width: 1.2, wobble: 3.2, color: INK_SOFT, passes: 1,
  });

  ctx.globalAlpha = 0.5;
  ctx.strokeStyle = INK_SOFT;
  ctx.lineWidth = 1.2;
  const tick = 80;
  for (let x = 0; x < world.w; x += tick) {
    ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x + 8, 14); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(x, world.h); ctx.lineTo(x + 8, world.h - 14); ctx.stroke();
  }
  for (let y = 0; y < world.h; y += tick) {
    ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(14, y + 8); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(world.w, y); ctx.lineTo(world.w - 14, y + 8); ctx.stroke();
  }
  ctx.restore();
}

export function drawOffscreenMarkers(ctx, cam, players, selfId, world) {
  const { x: cx, y: cy, w, h, zoom } = cam;
  const halfW = w / 2 / zoom;
  const halfH = h / 2 / zoom;
  const insetX = halfW - 30 / zoom;
  const insetY = halfH - 30 / zoom;

  for (const p of players) {
    if (p.id === selfId || !p.alive) continue;
    const dx = p.x - cx;
    const dy = p.y - cy;
    if (Math.abs(dx) < insetX && Math.abs(dy) < insetY) continue;

    // project the direction onto the edge of the viewport box
    const scale = Math.min(
      Math.abs(dx) > 1e-6 ? insetX / Math.abs(dx) : Infinity,
      Math.abs(dy) > 1e-6 ? insetY / Math.abs(dy) : Infinity
    );
    const ex = dx * scale;
    const ey = dy * scale;

    ctx.save();
    ctx.translate(w / 2 + ex * zoom, h / 2 + ey * zoom);
    ctx.rotate(Math.atan2(dy, dx));
    ctx.globalAlpha = 0.55;
    sketchPath(ctx, [[2, -8], [16, 0], [2, 8]], {
      seed: hashSeed(p.id), color: inkFor(p.hue), width: 2.4, wobble: 1, passes: 1,
    });
    ctx.restore();
  }
}
