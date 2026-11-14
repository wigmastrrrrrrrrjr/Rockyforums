// Public config only. The anon key is meant to be shipped; every write goes
// through SECURITY DEFINER functions that validate their arguments.
const env = (typeof import.meta !== 'undefined' && import.meta.env) || {};

export const SUPABASE_URL =
  env.VITE_SUPABASE_URL || 'https://trwxpgmkpaddnyktbleg.supabase.co';

export const SUPABASE_KEY =
  env.VITE_SUPABASE_ANON_KEY ||
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRyd3hwZ21rcGFkZG55a3RibGVnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODc2MzE3NjIsImV4cCI6MjEwMzIwNzc2Mn0.nJJUwuhMNq_8-3ShvpEUhkVz_DLPVklIid5BVSO8GDE';

// Client-side mirror of wsb.cfg(). The server values are authoritative; these
// are only used for prediction between packets.
export const ARENA = { w: 2000, h: 1500 };

export const TUNING = {
  tickMs: 100,
  baseMass: 10,
  baseRadius: 17,
  maxRadius: 58,
  hpMax: 100,
  bulletSpeed: 900,
  bulletLife: 1.1,
  respawnMs: 2500,
  killsToWin: 25,
};

export const NET = {
  pumpEveryMs: 100,        // 10 Hz up + down
  maxSnapshotAgeMs: 900,   // past this the connection is called "poor"
};

export function speedFor(radius) {
  return Math.max(150, 270 - radius * 2.1);
}

export function radiusFor(mass) {
  return Math.min(TUNING.maxRadius, TUNING.baseRadius * Math.sqrt(Math.max(mass, 1) / 10));
}

export function inkFor(hue) {
  // Muted, paper-friendly inks: same hue family, hand-drawn saturation.
  return `hsl(${hue} 48% 34%)`;
}

export function washFor(hue) {
  return `hsl(${hue} 52% 88%)`;
}
