// Netcode.
//
// Movement is simulated locally every animation frame and streamed up at 10 Hz
// with the local position. The server owns the truth. When a snapshot comes
// back we compare its position for *us* against what we predicted for that
// tick; any meaningful gap is a snap-back, and the client is told so it can
// flash the correction instead of hiding it.

import { createClient } from '@supabase/supabase-js';
import { SUPABASE_URL, SUPABASE_KEY, NET } from './config.js';

const sb = createClient(SUPABASE_URL, SUPABASE_KEY, {
  auth: { persistSession: false },
  realtime: { params: { eventsPerSecond: 2 } },
});

function clientId() {
  const k = 'wsb.client';
  let v = localStorage.getItem(k);
  if (!v) {
    v = 'c-' + Math.random().toString(36).slice(2, 10) + Date.now().toString(36);
    localStorage.setItem(k, v);
  }
  return v;
}

export class Net {
  constructor() {
    this.client = clientId();
    this.playerId = null;
    this.matchId = null;
    this.room = 'main';
    this.call = 'nobody';
    this.hue = 0;

    this.seq = 0;
    this.sinceEvent = 0;
    this.lastSnap = null;
    this.inflight = false;
    this.ping = 0;
    this.connected = false;
    this.corrections = 0;
    this.lastCorrection = 0;
    this.consecutiveErrors = 0;
    this.onSnapshot = () => {};
    this.onStatus = () => {};
  }

  async join(room, call) {
    this.room = room;
    this.call = call;
    const t0 = performance.now();
    const { data, error } = await sb.rpc('wsb_join', {
      p_room: room,
      p_client: this.client,
      p_call: call,
      p_hue: 0,
    });
    if (error) throw new Error(error.message || 'could not reach the sketchbook');
    if (!data?.ok) throw new Error(data?.error === 'full' ? 'that room is full' : 'could not join');

    this.ping = Math.round(performance.now() - t0);
    this.playerId = data.player_id;
    this.matchId = data.match_id;
    this.hue = data.hue;
    this.call = data.call;
    this.connected = true;

    this.startPump();
    return data;
  }

  /**
   * One frame of upstream state. `st` is {fx, fy, aim, shoot, x, y}.
   * The position is a *claim*; the server is free to reject it.
   */
  async pump(st) {
    if (!this.playerId || this.inflight) return;
    this.inflight = true;
    const t0 = performance.now();
    const payload = {
      p_room: this.room,
      p_player: this.playerId,
      p_seq: ++this.seq,
      p_fx: round(st.fx, 3),
      p_fy: round(st.fy, 3),
      p_aim: round(st.aim, 3),
      p_shoot: !!st.shoot,
      p_x: round(st.x, 1),
      p_y: round(st.y, 1),
      p_since: this.sinceEvent,
    };
    try {
      const { data, error } = await sb.rpc('wsb_pump', payload);
      if (error) throw error;
      if (!data || data.ok === false) {
        if (data?.error === 'no_match') this.connected = false;
        this.onStatus({ connected: this.connected, ping: this.ping });
        return;
      }
      this.ping = Math.round(performance.now() - t0);
      this.connected = true;
      this.consecutiveErrors = 0;

      if (!data.input?.ok) {
        const err = data.input?.error;
        if (err === 'gone') {
          this.connected = false;
          this.onStatus({ connected: false, ping: this.ping, reason: 'gone' });
        } else if (err === 'teleport' || err === 'stale') {
          this.corrections++;
          this.lastCorrection = performance.now();
        }
      }

      this.sinceEvent = Math.max(
        this.sinceEvent,
        ...(data.events || []).map((e) => e.id),
        this.sinceEvent
      );

      this.lastSnap = data;
      this.onSnapshot(data);
      this.onStatus({ connected: true, ping: this.ping, corrections: this.corrections });
    } catch (e) {
      this.consecutiveErrors++;
      if (this.consecutiveErrors > 3) {
        this.connected = false;
        this.onStatus({ connected: false, ping: this.ping, reason: 'offline' });
      }
    } finally {
      this.inflight = false;
    }
  }

  startPump() {
    clearInterval(this.timer);
    // main.js also pumps on its own rAF cadence; this interval is the floor
    this.timer = setInterval(() => this.onTick?.(), NET.pumpEveryMs);
  }


  async respawn() {
    if (!this.playerId) return null;
    const { data, error } = await sb.rpc('wsb_respawn', { p_player: this.playerId });
    if (error) return null;
    return data;
  }

  async leave() {
    clearInterval(this.timer);
    if (this.playerId) {
      try { await sb.rpc('wsb_leave', { p_player: this.playerId }); } catch { /* best effort */ }
    }
    this.playerId = null;
  }
}

function round(v, places) {
  const f = 10 ** places;
  return Math.round((v || 0) * f) / f;
}
