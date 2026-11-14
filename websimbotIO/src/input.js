// Keyboard + mouse + touch. Touch uses a left drag-to-walk stick and a right
// aim/fire stick, so you can walk and shoot at the same time with two thumbs.
import { speedFor } from './config.js';

export class Input {
  constructor(canvas) {
    this.canvas = canvas;
    this.keys = new Set();
    this.pointer = { x: 0, y: 0, active: false, down: false };
    this.touch = {
      move: { id: null, ox: 0, oy: 0, x: 0, y: 0, active: false },
      aim: { id: null, ox: 0, oy: 0, x: 0, y: 0, active: false, fire: false },
    };
    this.isTouch = matchMedia('(pointer: coarse)').matches;

    addEventListener('keydown', (e) => {
      if (['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', ' '].includes(e.key)) e.preventDefault();
      this.keys.add(e.key.toLowerCase());
    });
    addEventListener('keyup', (e) => this.keys.delete(e.key.toLowerCase()));
    addEventListener('blur', () => this.keys.clear());

    canvas.addEventListener('mousemove', (e) => {
      this.pointer.x = e.clientX;
      this.pointer.y = e.clientY;
      this.pointer.active = true;
    });
    canvas.addEventListener('mousedown', (e) => {
      if (e.button === 0) {
        this.pointer.down = true;
        this.pointer.x = e.clientX;
        this.pointer.y = e.clientY;
        this.pointer.active = true;
      }
    });
    addEventListener('mouseup', () => { this.pointer.down = false; });
    canvas.addEventListener('contextmenu', (e) => e.preventDefault());

    const zone = document.getElementById('stick-zone');
    const stick = document.getElementById('stick');
    const nub = document.getElementById('stick-nub');
    const fireZone = document.getElementById('fire-zone');
    const fireBtn = document.getElementById('fire');

    if (zone) {
      zone.addEventListener('pointerdown', (e) => {
        if (this.touch.move.id !== null) return;
        e.preventDefault();
        this.touch.move = { id: e.pointerId, ox: e.clientX, oy: e.clientY, x: 0, y: 0, active: true };
        const rect = stick.getBoundingClientRect();
        stick.style.left = e.clientX - rect.width / 2 + 'px';
        stick.style.top = e.clientY - rect.height / 2 + 'px';
        stick.classList.add('visible');
      });
    }
    if (fireZone) {
      fireZone.addEventListener('pointerdown', (e) => {
        if (this.touch.aim.id !== null) return;
        e.preventDefault();
        this.touch.aim = { id: e.pointerId, ox: e.clientX, oy: e.clientY, x: 0, y: 0, active: true, fire: true };
        fireBtn.classList.add('down');
      });
    }
    addEventListener('pointermove', (e) => {
      const m = this.touch.move;
      const a = this.touch.aim;
      if (m.id === e.pointerId) {
        m.x = e.clientX - m.ox;
        m.y = e.clientY - m.oy;
        const len = Math.hypot(m.x, m.y);
        const cap = 46;
        const k = len > cap ? cap / len : 1;
        nub.style.transform = `translate(${m.x * k}px, ${m.y * k}px)`;
      } else if (a.id === e.pointerId) {
        a.x = e.clientX - a.ox;
        a.y = e.clientY - a.oy;
      }
    });
    addEventListener('pointerup', (e) => this.release(e));
    addEventListener('pointercancel', (e) => this.release(e));
  }

  release(e) {
    const m = this.touch.move;
    const a = this.touch.aim;
    if (m.id === e.pointerId) {
      this.touch.move = { id: null, ox: 0, oy: 0, x: 0, y: 0, active: false };
      const stick = document.getElementById('stick');
      const nub = document.getElementById('stick-nub');
      if (stick) { stick.classList.remove('visible'); stick.style.left = '18px'; stick.style.top = 'auto'; }
      if (nub) nub.style.transform = 'translate(0,0)';
    }
    if (a.id === e.pointerId) {
      this.touch.aim = { id: null, ox: 0, oy: 0, x: 0, y: 0, active: false, fire: false };
      document.getElementById('fire')?.classList.remove('down');
    }
  }

  get touchMode() {
    return this.isTouch || this.touch.move.active || this.touch.aim.active;
  }

  /** Normalised intent: dir is a unit-ish vector, aim is world radians. */
  sample(self, now) {
    let fx = 0;
    let fy = 0;
    const k = this.keys;
    if (k.has('w') || k.has('arrowup')) fy -= 1;
    if (k.has('s') || k.has('arrowdown')) fy += 1;
    if (k.has('a') || k.has('arrowleft')) fx -= 1;
    if (k.has('d') || k.has('arrowright')) fx += 1;

    const m = this.touch.move;
    if (m.active) {
      fx += Math.max(-1, Math.min(1, m.x / 40));
      fy += Math.max(-1, Math.min(1, m.y / 40));
    }

    const len = Math.hypot(fx, fy);
    if (len > 1) { fx /= len; fy /= len; }

    let aim = self ? self.aim : 0;
    let shoot = this.pointer.down || k.has(' ') || k.has('e');

    const a = this.touch.aim;
    if (a.active) {
      const al = Math.hypot(a.x, a.y);
      if (al > 8) aim = Math.atan2(a.y, a.x);
      shoot = shoot || a.fire;
    } else if (!this.touchMode && this.pointer.active) {
      aim = null; // main.js projects the cursor into world space instead
    }

    return { fx, fy, aim, shoot, moving: len > 0.05 };
  }

  /** Auto-aim for the touch stick when you aren't holding it. */
  autoAim(self, players) {
    if (!self) return self?.aim ?? 0;
    let best = null;
    let bd = 620 * 620;
    for (const p of players) {
      if (p.id === self.id || !p.alive) continue;
      const d = (p.x - self.x) ** 2 + (p.y - self.y) ** 2;
      if (d < bd) { bd = d; best = p; }
    }
    if (!best) return self.aim;
    return Math.atan2(best.y - self.y, best.x - self.x);
  }
}
