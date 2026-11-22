/* The Assimilis eye: the desktop's floating character and the World's voice orb (owner, 2026-11-15: "keep it as
   eyes and variations"). One file for both (DAOP 6.3 and 8.3): the desktop copies it with `npm run sync-brand`.
   The logo's square magenta eye in its white frame, with the green pixel cloud around it (brand rules, AGENTS.md 6).
   It watches the cursor, blinks, and its pixels show what it is doing:
     idle: a slow orbit · thinking: faster, wider drift · listening: pulsing in · speaking: the iris beats
     working: the pixels pull into a tight ring · happy: a burst out and back · surprised: wide open
     concerned: a magenta glow · sleepy: half-closed lids, slow.
   Looks (Tray > Look): classic (framed eye), orb (a glowing iris, no frame), pixel (a chunky 8-bit eye).
   opts.idleStill (the World's voice orb): when nothing is happening it draws once and schedules no frames, so an
   idle orb costs nothing; any change of state wakes it.
   Own code. Plain script; CSP "script-src 'self'" safe; respects prefers-reduced-motion; no frames while hidden. */
(function () {
  'use strict';
  const NS = 'http://www.w3.org/2000/svg';
  const GREEN = ['#3d8c6e', '#52b58f', '#3d8c6e', '#6fd3a8'];
  const MAGENTA = '#e61478', HI = '#ff6fb3', NAVY = '#171b26';

  function el(name, attrs, parent) {
    const e = document.createElementNS(NS, name);
    for (const k in attrs) e.setAttribute(k, attrs[k]);
    if (parent) parent.appendChild(e);
    return e;
  }

  function mount(host, opts) {
    opts = opts || {};
    const visible = () => !document.hidden && host.isConnected && (!opts.isVisible || opts.isVisible());
    const reduced = () => { try { return matchMedia('(prefers-reduced-motion: reduce)').matches; } catch (_) { return false; } };
    host.classList.add('assimilis-eye');
    const svg = el('svg', { viewBox: '0 0 100 100', role: 'img', 'aria-label': 'Assimilis', 'shape-rendering': 'geometricPrecision' }, host);
    const defs = el('defs', {}, svg);
    const grad = el('radialGradient', { id: 'eyeAura' }, defs);
    el('stop', { offset: '0%', 'stop-color': MAGENTA, 'stop-opacity': '0.55' }, grad);
    el('stop', { offset: '60%', 'stop-color': MAGENTA, 'stop-opacity': '0.12' }, grad);
    el('stop', { offset: '100%', 'stop-color': MAGENTA, 'stop-opacity': '0' }, grad);
    // Jarvis HUD (opts.hud: the welcome and Settings screens): rotating segmented rings, ticks and a scanning arc.
    const hud = opts.hud ? el('g', { fill: 'none', 'stroke-linecap': 'round' }, svg) : null;
    let ringOuter = null, ringMid = null, ringScan = null, ringTicks = null;
    if (hud) {
      svg.setAttribute('viewBox', '-6 -6 112 112');
      ringOuter = el('circle', { cx: 50, cy: 50, r: 52, stroke: '#52b58f', 'stroke-width': 1.6, 'stroke-dasharray': '18 6 4 6', opacity: 0.75 }, hud);
      ringMid = el('circle', { cx: 50, cy: 50, r: 45, stroke: '#3d8c6e', 'stroke-width': 0.8, 'stroke-dasharray': '1.2 4.6', opacity: 0.9 }, hud);
      ringTicks = el('g', { stroke: '#6fd3a8', 'stroke-width': 1.2, opacity: 0.85 }, hud);
      for (let i = 0; i < 12; i++) { const a = (i / 12) * Math.PI * 2; el('line', { x1: 50 + Math.cos(a) * 38, y1: 50 + Math.sin(a) * 38, x2: 50 + Math.cos(a) * (i % 3 ? 40 : 42), y2: 50 + Math.sin(a) * (i % 3 ? 40 : 42) }, ringTicks); }
      ringScan = el('path', { d: 'M 50 2 A 48 48 0 0 1 91.6 26', stroke: MAGENTA, 'stroke-width': 2.2, opacity: 0.85 }, hud);
    }
    let boot = opts.boot ? 0 : 1;                      // 0 -> 1: rings draw in, pixels assemble, the eye opens
    const aura = el('circle', { cx: 50, cy: 50, r: 30, fill: 'url(#eyeAura)' }, svg);
    const cloud = el('g', {}, svg);
    const eye = el('g', {}, svg);
    const frame = el('rect', { x: 34, y: 34, width: 32, height: 32, rx: 7, fill: '#f4f6f8' }, eye);
    const socket = el('rect', { x: 38, y: 38, width: 24, height: 24, rx: 5, fill: NAVY }, eye);
    const iris = el('rect', { x: 43, y: 43, width: 14, height: 14, rx: 3, fill: MAGENTA }, eye);
    const shine = el('rect', { x: 44.5, y: 44.5, width: 4.5, height: 4.5, rx: 1, fill: HI }, eye);
    const lidTop = el('rect', { x: 33, y: 33, width: 34, height: 0, rx: 6, fill: NAVY }, eye);
    const lidBot = el('rect', { x: 33, y: 67, width: 34, height: 0, rx: 6, fill: NAVY }, eye);

    // The pixel cloud: 16 pixels on their own orbits.
    const pixels = [];
    for (let i = 0; i < 16; i++) {
      const size = i % 5 === 0 ? 4 : 3;
      const p = el('rect', { width: size, height: size, rx: 0.6, fill: i % 7 === 3 ? MAGENTA : GREEN[i % GREEN.length] }, cloud);
      pixels.push({ el: p, size, a: (i / 16) * Math.PI * 2, r: 24 + (i % 4) * 4, speed: 0.35 + (i % 5) * 0.08, wobble: (i * 1.7) % 3 });
    }

    let style = 'classic', mood = '', thinking = false, lookX = 0, lookY = 0, gazeX = 0, gazeY = 0;
    let last = 0, raf = 0, t = 0, blinkAt = 2 + Math.random() * 3, blink = 0, burst = 0;

    function setStyle(s) {
      style = ['classic', 'orb', 'pixel'].includes(s) ? s : 'classic';
      host.dataset.look = style;
      svg.setAttribute('shape-rendering', style === 'pixel' ? 'crispEdges' : 'geometricPrecision');
      frame.setAttribute('display', style === 'orb' ? 'none' : 'inline');
      socket.setAttribute('display', style === 'orb' ? 'none' : 'inline');
      const r = style === 'pixel' ? 0 : style === 'orb' ? 7 : 3;
      iris.setAttribute('rx', r);
      frame.setAttribute('rx', style === 'pixel' ? 0 : 7); socket.setAttribute('rx', style === 'pixel' ? 0 : 5);
      for (const p of pixels) {
        const sz = style === 'pixel' ? p.size + 2 : p.size;
        p.el.setAttribute('rx', style === 'pixel' ? 0 : 0.6); p.el.setAttribute('width', sz); p.el.setAttribute('height', sz);
      }
      draw(0);
    }

    function draw(dt) {
      t += dt;
      if (boot < 1) boot = Math.min(1, boot + dt / 1.6);
      const b = 1 - Math.pow(1 - boot, 3);               // ease out
      if (hud) {
        const spin = (el2, deg) => el2.setAttribute('transform', `rotate(${deg.toFixed(2)} 50 50)`);
        spin(ringOuter, t * 14); spin(ringMid, -t * 22); spin(ringTicks, t * 6);
        spin(ringScan, (thinking ? t * 260 : t * 90) % 360);
        hud.setAttribute('opacity', b.toFixed(3));
        const sc = 0.6 + 0.4 * b;
        hud.setAttribute('transform', `translate(50 50) scale(${sc.toFixed(3)}) translate(-50 -50)`);
        ringOuter.setAttribute('stroke', mood === 'listening' || mood === 'speaking' ? MAGENTA : '#52b58f');
      }
      const busy = thinking || mood === 'determined';
      const sleepy = mood === 'sleepy';
      // Gaze eases towards the cursor (or drifts when there is none).
      gazeX += (lookX - gazeX) * Math.min(1, dt * 8);
      gazeY += (lookY - gazeY) * Math.min(1, dt * 8);
      // Blinks: every few seconds, quick; sleepy keeps the lids half down.
      blinkAt -= dt;
      if (blinkAt <= 0) { blink = 1; blinkAt = 2.5 + Math.random() * 4; }
      blink = Math.max(0, blink - dt * 7);
      let lid = sleepy ? 0.45 + 0.05 * Math.sin(t * 1.2) : (blink > 0 ? Math.sin(blink * Math.PI) : 0);
      if (boot < 1) lid = Math.max(lid, 1 - Math.min(1, Math.max(0, (boot - 0.45) / 0.4)));   // opens late in the boot
      lidTop.setAttribute('height', (17 * lid).toFixed(2));
      lidBot.setAttribute('y', (67 - 17 * lid).toFixed(2));
      lidBot.setAttribute('height', (17 * lid).toFixed(2));
      // The eye: size by mood; the iris follows the gaze; speaking beats.
      let scale = mood === 'surprised' ? 1.22 : mood === 'listening' ? 1.06 + 0.04 * Math.sin(t * 6) : busy ? 0.94 : 1;
      if (mood === 'speaking') scale = 1.02 + 0.05 * Math.abs(Math.sin(t * 9));
      if (style === 'orb') scale *= 1.15;
      eye.setAttribute('transform', `translate(50 50) scale(${scale.toFixed(3)}) translate(-50 -50)`);
      const ix = 43 + gazeX * 4.2, iy = 43 + gazeY * 4.2;
      iris.setAttribute('x', ix.toFixed(2)); iris.setAttribute('y', iy.toFixed(2));
      shine.setAttribute('x', (ix + 1.5).toFixed(2)); shine.setAttribute('y', (iy + 1.5).toFixed(2));
      iris.setAttribute('fill', mood === 'concerned' ? '#ff3c7a' : busy ? '#ff3ca0' : MAGENTA);
      // Aura: brighter while busy, listening, speaking or concerned.
      const glow = mood === 'concerned' ? 1 : mood === 'listening' || mood === 'speaking' ? 0.8 : busy ? 0.7 : sleepy ? 0.15 : 0.4;
      aura.setAttribute('r', (24 + glow * 14 + (mood === 'listening' ? 3 * Math.sin(t * 6) : 0)).toFixed(2));
      aura.setAttribute('opacity', (0.35 + glow * 0.6).toFixed(3));
      // Pixels: orbit speed, radius and spread by state; happy bursts out and back.
      if (mood === 'happy' && burst <= 0) burst = 1;
      if (mood !== 'happy') burst = Math.max(0, burst - dt * 2);
      else burst = Math.max(0.0001, burst - dt * 0.9);
      const speedK = sleepy ? 0.25 : busy ? 2.6 : mood === 'listening' ? 1.6 : 1;
      for (const p of pixels) {
        p.a += dt * p.speed * speedK;
        let r = p.r;
        if (busy) r = 21 + Math.sin(t * 3 + p.a) * 1.5;                          // a tight ring: working
        else if (thinking) r = p.r + 4 * Math.sin(t * 2 + p.wobble);
        else if (mood === 'listening') r = p.r - 3 + 3 * Math.sin(t * 6 + p.wobble);
        r += burst * 14 * Math.sin(Math.PI * burst);
        if (sleepy) r = p.r - 4;
        if (boot < 1) { r *= b; p.a += dt * 6 * (1 - b); }   // the pixels spiral in from the centre (loading)
        const x = 50 + Math.cos(p.a) * r + gazeX * 1.5 - p.size / 2;
        const y = 50 + Math.sin(p.a) * r * 0.92 + gazeY * 1.5 - p.size / 2;
        p.el.setAttribute('x', x.toFixed(2)); p.el.setAttribute('y', y.toFixed(2));
        p.el.setAttribute('opacity', sleepy ? '0.35' : '1');
      }
    }
    // Nothing to animate: the boot is over, no mood, not thinking, no blink or burst still running.
    const still = () => opts.idleStill && boot >= 1 && !thinking && !mood && blink <= 0 && burst <= 0;
    function frame_(now) {
      raf = 0;
      if (!visible()) { last = 0; return; }
      const dt = last ? Math.min(0.05, (now - last) / 1000) : 0.016;
      last = now;
      draw(dt);
      if (still()) { last = 0; return; }
      if (!reduced()) raf = requestAnimationFrame(frame_);
    }
    function wake() { if (!raf && visible()) raf = requestAnimationFrame(frame_); }
    document.addEventListener('visibilitychange', wake);
    setStyle(opts.look);
    draw(0.016);
    wake();
    return {
      mode: 'eye',
      setMode() { wake(); },                             // older callers: the character is always the eye now
      setThinking(b) { thinking = !!b; wake(); },
      setMood(name) { mood = String(name || ''); if (mood === 'happy') burst = 0; wake(); },
      look(dx, dy) { const d = Math.hypot(dx, dy) || 1; const k = Math.min(1, d / 220); lookX = (dx / d) * k; lookY = (dy / d) * k; wake(); },
      setStyle(s) { setStyle(s); wake(); },
      get style() { return style; },
      get thinking() { return thinking; },
      get mood() { return mood; },
      get running() { return !!raf; },
      wake,
      reboot() { boot = 0; wake(); }
    };
  }

  window.AssimilisEye = { mount };
})();
