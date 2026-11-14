// The hand-drawn look is two things: a paper substrate, and every stroke being
// a slightly wrong polyline with a double pass. Nothing in here uses a straight
// line if a wobble will do.

const INK = '#2b2a26';

export function mulberry32(seed) {
  let a = seed >>> 0;
  return function () {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// Deterministic per-id jitter so a dot doesn't shimmer between frames.
export function hashSeed(str) {
  let h = 2166136261;
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}

/**
 * Draw a hand-drawn path. `points` are in canvas space. Each call re-seeds from
 * `seed` so the wobble is stable for one "frame group" (e.g. one redraw of a
 * player at a given size) but re-rolls when the object moves enough.
 */
export function sketchPath(ctx, points, opts = {}) {
  const {
    seed = 1,
    wobble = 1.6,
    passes = 2,
    close = false,
    width = 2,
    color = INK,
    alpha = 0.9,
  } = opts;

  const rnd = mulberry32(seed);
  ctx.save();
  ctx.strokeStyle = color;
  ctx.lineWidth = width;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';

  for (let p = 0; p < passes; p++) {
    ctx.globalAlpha = alpha * (p === 0 ? 1 : 0.45);
    ctx.beginPath();
    const n = points.length;
    const last = close ? n : n - 1;
    for (let i = 0; i <= last; i++) {
      const a = points[i % n];
      const jx = (rnd() - 0.5) * wobble * 2;
      const jy = (rnd() - 0.5) * wobble * 2;
      if (i === 0) ctx.moveTo(a[0] + jx, a[1] + jy);
      else {
        const b = points[(i - 1) % n];
        const cx = (b[0] + a[0]) / 2 + (rnd() - 0.5) * wobble * 2.4;
        const cy = (b[1] + a[1]) / 2 + (rnd() - 0.5) * wobble * 2.4;
        ctx.quadraticCurveTo(cx, cy, a[0] + jx, a[1] + jy);
      }
    }
    ctx.stroke();
  }
  ctx.restore();
}

/** A closed, filled blob that still looks drawn. */
export function sketchBlob(ctx, cx, cy, r, opts = {}) {
  const {
    seed = 1,
    fill = null,
    color = INK,
    width = 2,
    wobble = 2.2,
    squash = 1,        // <1 flattens it (used for the walk bob)
    points = 11,
    rotation = 0,
  } = opts;

  const rnd = mulberry32(seed);
  const pts = [];
  for (let i = 0; i < points; i++) {
    const t = (i / points) * Math.PI * 2;
    const jitter = 1 + (rnd() - 0.5) * 0.16;
    const px = Math.cos(t + rotation) * r * jitter;
    const py = Math.sin(t + rotation) * r * jitter * squash;
    pts.push([cx + px, cy + py]);
  }

  if (fill) {
    ctx.save();
    ctx.fillStyle = fill;
    ctx.beginPath();
    // same wobble pass, filled
    for (let i = 0; i < pts.length; i++) {
      const a = pts[i];
      if (i === 0) ctx.moveTo(a[0], a[1]);
      else {
        const b = pts[i - 1];
        ctx.quadraticCurveTo((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, a[0], a[1]);
      }
    }
    ctx.closePath();
    ctx.fill();
    ctx.restore();
  }

  sketchPath(ctx, pts, { seed, wobble, color, width, close: true, passes: 2 });
}

/** Hatching lines clipped to a circle: the "shaded" look on a paper sketch. */
export function sketchHatch(ctx, cx, cy, r, opts = {}) {
  const { seed = 7, color = INK, gap = 5, alpha = 0.16, angle = -0.7 } = opts;
  const rnd = mulberry32(seed);
  ctx.save();
  ctx.beginPath();
  ctx.arc(cx, cy, r, 0, Math.PI * 2);
  ctx.clip();
  ctx.strokeStyle = color;
  ctx.globalAlpha = alpha;
  ctx.lineWidth = 1.1;
  const span = r * 2.4;
  const dx = Math.cos(angle);
  const dy = Math.sin(angle);
  for (let i = -span; i < span; i += gap) {
    const ox = cx - dy * i;
    const oy = cy + dx * i;
    ctx.beginPath();
    ctx.moveTo(ox - dx * span + (rnd() - 0.5) * 3, oy - dy * span + (rnd() - 0.5) * 3);
    ctx.lineTo(ox + dx * span + (rnd() - 0.5) * 3, oy + dy * span + (rnd() - 0.5) * 3);
    ctx.stroke();
  }
  ctx.restore();
}

/** Loose ruled paper with a marginal line and a coffee-ish stain. */
export function paintPaperCanvas(w, h) {
  const c = document.createElement('canvas');
  c.width = Math.max(1, Math.floor(w));
  c.height = Math.max(1, Math.floor(h));
  const ctx = c.getContext('2d');
  const rnd = mulberry32(20261113);

  ctx.fillStyle = '#f4f0e6';
  ctx.fillRect(0, 0, c.width, c.height);

  // faint mottling, so it isn't a dead flat fill
  for (let i = 0; i < 900; i++) {
    const x = rnd() * c.width;
    const y = rnd() * c.height;
    const r = 8 + rnd() * 40;
    ctx.globalAlpha = 0.012 + rnd() * 0.016;
    ctx.fillStyle = rnd() > 0.5 ? '#b9a98b' : '#ffffff';
    ctx.beginPath();
    ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.globalAlpha = 1;

  // faint grid, drawn with a wobble like everything else
  ctx.strokeStyle = '#c9d3da';
  ctx.globalAlpha = 0.5;
  ctx.lineWidth = 1;
  const step = 46;
  for (let x = 0; x < c.width; x += step) {
    ctx.beginPath();
    for (let y = 0; y <= c.height; y += 40) {
      const jx = x + (rnd() - 0.5) * 1.4;
      if (y === 0) ctx.moveTo(jx, y);
      else ctx.lineTo(jx, y);
    }
    ctx.stroke();
  }
  ctx.globalAlpha = 1;
  ctx.globalAlpha = 1;

  // vignette
  const g = ctx.createRadialGradient(
    c.width / 2, c.height / 2, Math.min(c.width, c.height) * 0.25,
    c.width / 2, c.height / 2, Math.max(c.width, c.height) * 0.75
  );
  g.addColorStop(0, 'rgba(0,0,0,0)');
  g.addColorStop(1, 'rgba(120,104,74,0.16)');
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, c.width, c.height);

  return c;
}

/** Ruled paper for the DOM shell. */
export function paintDomPaper() {
  const el = document.getElementById('paper');
  if (!el) return;
  const c = paintPaperCanvas(window.innerWidth, window.innerHeight);
  el.style.backgroundImage = `url(${c.toDataURL('image/jpeg', 0.72)})`;
  el.style.backgroundSize = 'cover';
}

export { INK };
