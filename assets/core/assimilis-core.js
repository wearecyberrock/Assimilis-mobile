/* The Core: the brain depth, fully zoomed out (the UI reference of 2026-11-17, "the core, fully zoomed out").
 *
 * Every memory and object is a point of light inside one core, with the Assimilis eye at the centre. Each group has its
 * own tilted orbit (promises, AI brains, memory, tools, business records, the canvas, the server), and each sub-group
 * inside a group (a server part, a canvas group, a kind of record, a promise's day) has a thinner orbit of its own close
 * to it. Every memory is a point on a spoke from the centre, the links between nodes (a part and what it holds, wires on
 * the canvas, a tool and the service it runs on) are lines through the core, and three rings of dashed arcs show how big
 * everything is: the groups on the outer shell, their sub-groups just inside it, and the memory stores close around the
 * centre. It listens (the rings draw in and ripple toward the centre), thinks (branching filaments run to what it is
 * reading, and on into a store's memories), speaks (the core pulses with the voice) and points (a beam to a node, and
 * the view flies there).
 *
 * Drawn on one canvas with additive blending, so lines add up to bright where they cross, plus a bloom pass (the bright
 * parts drawn again on a canvas a quarter the size, blurred and added back). The reference images set the feel only;
 * the geometry is our own. Idle, it draws ten frames a second or fewer (slower when a frame costs more) and barely
 * moves; with reduced motion it is a still picture that changes only on state; it stops drawing when hidden. The page
 * (assimilis-notes.js) gives it the nodes, the links, the state and the readouts' anchors.
 *
 * window.AssimilisCore.mount(host, opts) -> view; the pure geometry is AssimilisCore.geom (Node tests run it).
 */
(function (root) {
  'use strict';

  const TAU = Math.PI * 2;
  // Inner to outer. r: radius (core radii); tilt: how far the orbit leans back; node: which way it leans; speed: rad/s.
  const RINGS = [
    { id: 'promises', label: 'Promises', r: 0.30, tilt: 1.12, node: 0.35, speed: 0.022 },
    { id: 'brains', label: 'AI brains', r: 0.42, tilt: 1.02, node: 1.45, speed: -0.017 },
    { id: 'memory', label: 'Memory', r: 0.54, tilt: 1.24, node: 2.55, speed: 0.013 },
    { id: 'tools', label: 'Tools', r: 0.65, tilt: 0.94, node: 3.70, speed: -0.011 },
    { id: 'records', label: 'Business records', r: 0.75, tilt: 1.18, node: 4.60, speed: 0.009 },
    { id: 'canvas', label: 'On this canvas', r: 0.85, tilt: 1.08, node: 5.45, speed: -0.007 },
    { id: 'server', label: 'This server', r: 0.95, tilt: 1.30, node: 0.95, speed: 0.005 }
  ];
  RINGS.forEach((g, i) => { g.i = i; g.ct = Math.cos(g.tilt); g.st = Math.sin(g.tilt); g.cn = Math.cos(g.node); g.sn = Math.sin(g.node); });
  const RING_BY = new Map(RINGS.map((g) => [g.id, g]));
  const MAX_PER_RING = 160;          // more on one orbit than this: the first 160 are drawn, the readouts keep the count
  const MAX_MEMORY_POINTS = 4000;    // one point per memory up to this, shared out between the stores
  const SPOKE_POINTS = 16;           // memories on one spoke
  const MAX_SUBS = 8;                // sub-group orbits per group; any more share the group's own orbit
  const SUB_STEP = 0.013;            // between neighbouring sub-orbits: a group's band stays clear of the next group's
  const MAX_LINKS = 600;
  const SHELL_R = 1.1;               // the outer shell: one arc per group
  const INNER_R = 1.0;               // just inside it: one arc per sub-group, under its group's arc
  const STORE_R = 0.315;             // close around the centre: one arc per memory store
  const CAM_F = 2.6;                 // the camera's distance, in core radii
  const ZOOM_MIN = 1, ZOOM_MAX = 3.2, LABEL_ZOOM = 1.25;
  const IDLE_MS = 100;               // idle: ten frames a second at most
  const SEGS = 96;
  const BLOOM_DIV = 4;               // the bloom is drawn at a quarter of the size

  // ---- geometry (pure) ----------------------------------------------------------------------------------------------
  function ringPoint(g, theta, scale) {
    const r = g.r * (scale || 1), c = Math.cos(theta), s = Math.sin(theta);
    const x = r * c, y = r * s * g.ct, z = r * s * g.st;
    return [x * g.cn - y * g.sn, x * g.sn + y * g.cn, z];
  }
  // The camera turns the core (yaw about the vertical, then pitch), then perspective.
  function camera(p, cam) {
    const cy = Math.cos(cam.yaw), sy = Math.sin(cam.yaw), cp = Math.cos(cam.pitch), sp = Math.sin(cam.pitch);
    const x1 = p[0] * cy + p[2] * sy, z1 = -p[0] * sy + p[2] * cy, y1 = p[1];
    return [x1, y1 * cp - z1 * sp, y1 * sp + z1 * cp];
  }
  function perspective(z) { return CAM_F / (CAM_F + z); }
  // The yaw and pitch that bring a point to the front, facing the viewer.
  function facing(p) {
    const rho = Math.hypot(p[0], p[2]);
    return { yaw: Math.atan2(p[0], -p[2]), pitch: Math.atan2(-p[1], rho) };
  }
  // Evenly spread directions on a sphere (the golden spiral): the memory spokes.
  function spokeDirs(n) {
    const out = [];
    const ga = Math.PI * (3 - Math.sqrt(5));
    for (let i = 0; i < n; i += 1) {
      const y = 1 - (2 * (i + 0.5)) / n, r = Math.sqrt(Math.max(0, 1 - y * y)), a = ga * i;
      out.push([Math.cos(a) * r, y, Math.sin(a) * r]);
    }
    return out;
  }
  // Points for each store: one per memory while they fit under the cap, otherwise shared out by size (every store
  // with memories keeps at least one point).
  function shareOut(stores, cap) {
    const counts = stores.map((s) => Math.max(0, Math.floor(Number(s.count) || 0)));
    const total = counts.reduce((a, b) => a + b, 0);
    if (total <= cap) return counts;
    const out = counts.map((c) => (c ? Math.max(1, Math.floor((c / total) * cap)) : 0));
    let over = out.reduce((a, b) => a + b, 0) - cap;
    for (let i = 0; over > 0 && i < out.length * 4; i += 1) {
      const k = out.indexOf(Math.max(...out));
      if (out[k] <= 1) break;
      out[k] -= 1; over -= 1;
    }
    return out;
  }
  // The j-th of k sub-group orbits of a group: a little in or out from the group's radius, leaning and turned a little
  // differently, so a group with sub-groups reads as a bundle of orbits.
  function orbitOf(g, j, k, sub) {
    const o = { id: g.id + '/' + j, ring: g.id, sub, j, r: g.r + (j - (k - 1) / 2) * SUB_STEP,
      tilt: g.tilt + 0.16 * Math.sin(j * 2.4 + g.i), node: g.node + 0.62 * (j + 1), speed: g.speed * (1 + 0.15 * ((j % 3) - 1)) };
    o.ct = Math.cos(o.tilt); o.st = Math.sin(o.tilt); o.cn = Math.cos(o.node); o.sn = Math.sin(o.node);
    return o;
  }
  // The nodes and memory points, placed: each node on its sub-group's orbit (or its group's), evenly spaced; memories
  // along spokes, a little spread across each spoke.
  function layout(graph) {
    const rings = (graph && graph.rings) || {};
    const nodes = [], orbits = [], subs = {};
    RINGS.forEach((g) => {
      const all = (Array.isArray(rings[g.id]) ? rings[g.id] : []).filter((n) => n && n.id);
      // How many in each sub-group (all of them, for the arcs), in the order they first come.
      const counts = new Map();
      all.forEach((n) => { const s = n.sub ? String(n.sub) : ''; counts.set(s, (counts.get(s) || 0) + 1); });
      if (all.length) subs[g.id] = [...counts].map(([s, count]) => ({ id: s, label: s || g.label, count }));
      const list = all.slice(0, MAX_PER_RING);
      const named = [];
      list.forEach((n) => { const s = n.sub ? String(n.sub) : ''; if (s && !named.includes(s) && named.length < MAX_SUBS) named.push(s); });
      // One sub-group alone: its nodes stay on the group's own orbit.
      const own = named.length > 1 ? named.map((s, j) => orbitOf(g, j, named.length, s)) : [];
      orbits.push(...own);
      const bySub = new Map(own.map((o) => [o.sub, o]));
      const members = new Map();
      list.forEach((n) => {
        const o = bySub.get(n.sub ? String(n.sub) : '') || null, key = o ? o.id : g.id;
        if (!members.has(key)) members.set(key, { o, list: [] });
        members.get(key).list.push(n);
      });
      members.forEach(({ o, list: m }, key) => m.forEach((n, i) => nodes.push(Object.assign({}, n,
        { ring: g.id, orbit: key, theta0: (i / m.length) * TAU + g.i * 0.7 + (o ? o.j * 0.9 : 0) }))));
    });
    const stores = Array.isArray(graph && graph.memories) ? graph.memories.filter((s) => s && s.count > 0) : [];
    const share = shareOut(stores, MAX_MEMORY_POINTS);
    const per = share.map((k) => Math.ceil(k / SPOKE_POINTS));
    const dirs = spokeDirs(Math.max(1, per.reduce((a, b) => a + b, 0)));
    const points = [], spokes = [];
    let d = 0;
    stores.forEach((s, si) => {
      let left = share[si];
      const store = s.store || s.id || '';
      for (let k = 0; k < per[si]; k += 1, d += 1) {
        const dir = dirs[d], here = Math.min(SPOKE_POINTS, left);
        left -= here;
        // Two directions across the spoke, for the spread.
        const ax = Math.abs(dir[1]) < 0.9 ? [0, 1, 0] : [1, 0, 0];
        let u = [dir[1] * ax[2] - dir[2] * ax[1], dir[2] * ax[0] - dir[0] * ax[2], dir[0] * ax[1] - dir[1] * ax[0]];
        const ul = Math.hypot(u[0], u[1], u[2]) || 1;
        u = u.map((x) => x / ul);
        const w = [dir[1] * u[2] - dir[2] * u[1], dir[2] * u[0] - dir[0] * u[2], dir[0] * u[1] - dir[1] * u[0]];
        let tip = 0;
        for (let j = 0; j < here; j += 1) {
          const h1 = ((j * 7919 + d * 104729) % 97) / 97, h2 = ((j * 6271 + d * 3571) % 89) / 89;
          const r = 0.16 + (0.86 * (j + 0.5)) / SPOKE_POINTS + h1 * 0.015;
          const lat = 0.018 * r * h1, a = h2 * TAU, ca = Math.cos(a) * lat, sa = Math.sin(a) * lat;
          points.push({ store, si, x: dir[0] * r + u[0] * ca + w[0] * sa, y: dir[1] * r + u[1] * ca + w[1] * sa, z: dir[2] * r + u[2] * ca + w[2] * sa });
          tip = Math.max(tip, r);
        }
        if (here) spokes.push({ store, si, x: dir[0], y: dir[1], z: dir[2], len: tip });
      }
    });
    const ids = new Set(nodes.map((n) => n.id));
    const links = (Array.isArray(graph && graph.links) ? graph.links : [])
      .filter((l) => l && l.a !== l.b && ids.has(l.a) && ids.has(l.b)).slice(0, MAX_LINKS)
      .map((l) => ({ a: l.a, b: l.b, kind: String(l.kind || '') }));
    return { nodes, points, stores, orbits, spokes, links, subs };
  }
  // Arcs between two angles, one per item, each as long as the item is big (at least a sliver), with a gap after each.
  function splitArcs(items, from, to, gap, min) {
    const live = (items || []).filter((it) => (it.count || 0) > 0);
    const total = live.reduce((a, it) => a + it.count, 0);
    const free = (to - from) - gap * live.length;
    if (!total || free <= 0) return [];
    const raw = live.map((it) => Math.max(min, (it.count / total) * free));
    const scale = free / raw.reduce((a, b) => a + b, 0);
    let a = from;
    return live.map((it, i) => {
      const len = raw[i] * scale, arc = { id: it.id, label: it.label, count: it.count, from: a, to: a + len };
      a += len + gap;
      return arc;
    });
  }
  // The outer shell: one dashed arc per group, each as long as the group is big.
  function shellArcs(counts) {
    return splitArcs(RINGS.map((g) => ({ id: g.id, label: g.label, count: counts[g.id] || 0 })), -Math.PI / 2, 1.5 * Math.PI, 0.05, 0.12);
  }
  // Just inside the shell: each group's arc split between its sub-groups (inside the group's own arc).
  function subArcs(arcs, subs) {
    const out = [];
    (arcs || []).forEach((a) => {
      const list = (subs && subs[a.id]) || [];
      const parts = list.length ? list : [{ id: '', label: a.label, count: a.count }];
      const split = splitArcs(parts, a.from, a.to, parts.length > 1 ? 0.012 : 0, 0.015);
      (split.length ? split : [{ id: parts[0].id, label: parts[0].label, count: a.count, from: a.from, to: a.to }])
        .forEach((s) => out.push(Object.assign(s, { ring: a.id })));
    });
    return out;
  }
  // Close around the centre: one arc per memory store, as long as it has memories.
  function storeArcs(stores) {
    return splitArcs((stores || []).map((s) => ({ id: s.store || s.id || '', label: s.label || s.store || '', count: Number(s.count) || 0 })),
      -Math.PI / 2, 1.5 * Math.PI, 0.04, 0.05);
  }
  // Where the core sits in a w×h stage: the outer shell about 80% of the height, as wide as a phone allows.
  function frame(w, h) { return { cx: w / 2, cy: h * 0.46, R: Math.min(w * 0.42, h * 0.375) }; }
  function clampZoom(z) { return Math.min(ZOOM_MAX, Math.max(ZOOM_MIN, z)); }
  function ease(t) { return t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2; }

  // ---- colours (from the tokens) ---------------------------------------------------------------------------------
  const THEMES = {
    violet: ['--as-core-violet', '--as-core-magenta', '--as-core-hot', ['#9051e1', '#e61478', '#fff3fb']],
    amber: ['--as-core-amber', '--as-core-amber-glow', '--as-core-amber-hot', ['#e8892a', '#ffb347', '#fff4e0']],
    cyan: ['--as-core-cyan', '--as-core-cyan-glow', '--as-core-cyan-hot', ['#1aa7c9', '#5ee7ff', '#effcff']]
  };
  function hexRgb(hex) {
    const m = /^#?([0-9a-f]{6})$/i.exec(String(hex || '').trim());
    if (!m) return null;
    const n = parseInt(m[1], 16);
    return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
  }
  function mixRgb(a, b, t) { return [0, 1, 2].map((i) => Math.round(a[i] + (b[i] - a[i]) * t)); }
  function themeColors(name, read) {
    const t = THEMES[name] || THEMES.violet;
    const get = (v, i) => hexRgb(read ? read(v) : '') || hexRgb(t[3][i]);
    const line = get(t[0], 0), glow = get(t[1], 1), hot = get(t[2], 2);
    const magenta = hexRgb(read ? read('--as-brand-magenta') : '') || [230, 20, 120];
    const warn = hexRgb(read ? read('--as-warn') : '') || [224, 164, 58];
    const danger = hexRgb(read ? read('--as-danger') : '') || [229, 95, 88];
    const bg = hexRgb(read ? read('--as-core-bg') : '') || [5, 4, 10];
    const rings = RINGS.map((g, i) => mixRgb(glow, line, i / (RINGS.length - 1)));
    // Memories, one tint per store in turn.
    const mem = [mixRgb(glow, hot, 0.3), rings[2], mixRgb(line, hot, 0.25)];
    return { name: THEMES[name] ? name : 'violet', bg, line, glow, hot, magenta, warn, danger, rings, mem };
  }
  const rgba = (c, a) => `rgba(${c[0]},${c[1]},${c[2]},${a})`;

  const geom = { RINGS, MAX_PER_RING, MAX_MEMORY_POINTS, SPOKE_POINTS, MAX_SUBS, SUB_STEP, SHELL_R, INNER_R, STORE_R, ZOOM_MIN,
    ZOOM_MAX, LABEL_ZOOM, ringPoint, camera, perspective, facing, spokeDirs, shareOut, orbitOf, layout, splitArcs, shellArcs,
    subArcs, storeArcs, frame, clampZoom, themeColors, hexRgb };

  // ---- the view ------------------------------------------------------------------------------------------------------
  function mount(host, opts) {
    opts = opts || {};
    const doc = host.ownerDocument || document;
    const win = doc.defaultView || root;
    const cv = doc.createElement('canvas');
    cv.className = 'core-canvas';
    cv.tabIndex = 0;
    cv.setAttribute('role', 'img');
    cv.setAttribute('aria-label', opts.label || 'The Core: every memory and object around the eye');
    host.appendChild(cv);
    const eyeHost = doc.createElement('div');
    eyeHost.className = 'core-eye';
    eyeHost.setAttribute('aria-hidden', 'true');
    eyeHost.style.visibility = 'hidden';           // shown once the first frame has placed it on the centre
    host.appendChild(eyeHost);
    let eye = null;
    if (win.AssimilisEye && opts.eye !== false) {
      try { eye = win.AssimilisEye.mount(eyeHost, { look: 'orb', hud: true, idleStill: true }); } catch (_) { eye = null; }
      const svg = eyeHost.querySelector && eyeHost.querySelector('svg');
      if (svg) svg.setAttribute('aria-hidden', 'true');
    }
    const reduced = () => { try { return win.matchMedia('(prefers-reduced-motion: reduce)').matches; } catch (_) { return false; } };
    const readVar = (v) => { try { return win.getComputedStyle(doc.documentElement).getPropertyValue(v).trim(); } catch (_) { return ''; } };
    const Path = win.Path2D;

    const S = {
      graph: { nodes: [], points: [], stores: [], orbits: [], spokes: [], links: [], subs: {} }, byId: new Map(),
      orbitBy: new Map(RINGS.map((g) => [g.id, g])), storePts: new Map(), counts: {}, arcs: [], subArcs: [], storeArcs: [],
      cam: { yaw: 0.35, pitch: -0.28, zoom: 1, panX: 0, panY: 0 }, fly: null,
      state: 'idle', level: 0, beats: [], ripples: [], reading: [], lit: null, beams: [], pulses: [], hover: null,
      anchors: [], theme: themeColors(opts.theme || 'violet', readVar), t0: now(), lastFrame: 0, raf: 0, timer: 0,
      running: false, hidden: false, w: 0, h: 0, dpr: 1, floor: null, floorKey: '', sprites: new Map(), bloom: null,
      stats: { frames: 0, total: 0, max: 0, last: 0, recent: 0, points: 0 }, proj: new Float32Array(0), tmp: new Float32Array(4),
      trig: null, ctx: null, drawnAt: 0
    };
    function now() { return (win.performance && win.performance.now) ? win.performance.now() : Date.now(); }

    // A soft round glow, drawn once per colour and size and reused (drawImage is far cheaper than a gradient a dot).
    function sprite(c, hot) {
      const key = c.join(',') + (hot ? 'h' : '');
      let sp = S.sprites.get(key);
      if (sp) return sp;
      sp = doc.createElement('canvas');
      sp.width = sp.height = 64;
      const g = sp.getContext('2d');
      const gr = g.createRadialGradient(32, 32, 0, 32, 32, 32);
      gr.addColorStop(0, hot ? 'rgba(255,255,255,1)' : rgba(c, 0.95));
      gr.addColorStop(0.18, rgba(c, 0.75));
      gr.addColorStop(0.5, rgba(c, 0.18));
      gr.addColorStop(1, rgba(c, 0));
      g.fillStyle = gr;
      g.fillRect(0, 0, 64, 64);
      S.sprites.set(key, sp);
      return sp;
    }

    function size() {
      const w = host.clientWidth || 0, h = host.clientHeight || 0;
      const raw = Math.min(2, win.devicePixelRatio || 1);
      const dpr = Math.max(1, Math.min(raw, Math.sqrt(4.2e6 / Math.max(1, w * h))));    // at most ~4 million pixels
      if (w !== S.w || h !== S.h || dpr !== S.dpr) {
        S.w = w; S.h = h; S.dpr = dpr;
        cv.width = Math.round(w * dpr); cv.height = Math.round(h * dpr);
        S.floor = null;
      }
      return w > 0 && h > 0;
    }
    function view() {
      const f = frame(S.w, S.h);
      return { cx: f.cx + S.cam.panX, cy: f.cy + S.cam.panY, R: f.R * S.cam.zoom, base: f.R };
    }
    function trig() {
      const c = S.cam;
      return { cy: Math.cos(c.yaw), sy: Math.sin(c.yaw), cp: Math.cos(c.pitch), sp: Math.sin(c.pitch) };
    }
    // camera() and perspective() in one, with the turn's sines worked out once a frame.
    function proj(x, y, z, v, T, out, o) {
      const x1 = x * T.cy + z * T.sy, z1 = -x * T.sy + z * T.cy;
      const y2 = y * T.cp - z1 * T.sp, z2 = y * T.sp + z1 * T.cp, s = CAM_F / (CAM_F + z2);
      out[o] = v.cx + x1 * s * v.R; out[o + 1] = v.cy + y2 * s * v.R; out[o + 2] = s; out[o + 3] = z2;
    }
    function project(p, v, out, o) { proj(p[0], p[1], p[2], v, trig(), out, o); }
    function stroke(g, path, c, a, lw) {
      g.strokeStyle = rgba(c, a);
      g.lineWidth = lw;
      g.stroke(path);
    }

    // The grid floor: a faint perspective grid under the core, drawn once per size and theme.
    function floor() {
      const key = S.w + 'x' + S.h + ':' + S.theme.name;
      if (S.floor && S.floorKey === key) return S.floor;
      const f = doc.createElement('canvas');
      f.width = cv.width; f.height = cv.height;
      const g = f.getContext('2d');
      g.setTransform(S.dpr, 0, 0, S.dpr, 0, 0);
      const horizon = S.h * 0.7, vx = S.w / 2;
      g.strokeStyle = rgba(S.theme.line, 0.09);
      g.lineWidth = 1;
      g.beginPath();
      for (let i = 1; i <= 9; i += 1) {
        const y = horizon + (S.h - horizon) * Math.pow(i / 9, 1.9);
        g.moveTo(0, y); g.lineTo(S.w, y);
      }
      for (let i = -14; i <= 14; i += 1) { g.moveTo(vx + i * 8, horizon); g.lineTo(vx + i * S.w * 0.16, S.h); }
      g.stroke();
      const fade = g.createLinearGradient(0, horizon, 0, horizon + 60);
      fade.addColorStop(0, 'rgba(0,0,0,1)'); fade.addColorStop(1, 'rgba(0,0,0,0)');
      g.globalCompositeOperation = 'destination-out';
      g.fillStyle = fade;
      g.fillRect(0, horizon - 1, S.w, 62);
      S.floor = f; S.floorKey = key;
      return f;
    }

    // The bloom: the bright parts are drawn again, a quarter the size, on their own canvas (bloomBegin hands it out),
    // then blurred and added back over the picture (bloomEnd).
    function bloomBegin() {
      if (!Path) return null;
      const bw = Math.max(1, Math.ceil(S.w / BLOOM_DIV)), bh = Math.max(1, Math.ceil(S.h / BLOOM_DIV));
      let B = S.bloom;
      if (!B || B.a.width !== bw || B.a.height !== bh) {
        const mk = () => { const c = doc.createElement('canvas'); c.width = bw; c.height = bh; return c; };
        const a = mk(), b = mk(), bctx = b.getContext('2d');
        B = S.bloom = { a, b, actx: a.getContext('2d'), bctx, blur: typeof bctx.filter === 'string' };
      }
      const g = B.actx;
      g.setTransform(1, 0, 0, 1, 0, 0);
      g.globalCompositeOperation = 'source-over';
      g.globalAlpha = 1;
      g.clearRect(0, 0, bw, bh);
      g.setTransform(bw / S.w, 0, 0, bh / S.h, 0, 0);
      g.globalCompositeOperation = 'lighter';
      return g;
    }
    function bloomEnd(ctx) {
      const B = S.bloom;
      if (!B) return;
      const g = B.bctx, w = B.b.width, h = B.b.height;
      g.setTransform(1, 0, 0, 1, 0, 0);
      g.globalCompositeOperation = 'source-over';
      g.globalAlpha = 1;
      g.clearRect(0, 0, w, h);
      if (B.blur) { g.filter = 'blur(2.5px)'; g.drawImage(B.a, 0, 0); g.filter = 'none'; }
      else {                                                       // no canvas filter (older Safari): a soft cross instead
        g.globalCompositeOperation = 'lighter';
        g.globalAlpha = 0.3;
        [[0, 0], [-1.5, 0], [1.5, 0], [0, -1.5], [0, 1.5]].forEach(([x, y]) => g.drawImage(B.a, x, y));
      }
      g.globalCompositeOperation = 'lighter';                      // and the unblurred layer on top: a tighter glow
      g.globalAlpha = 0.55;
      g.drawImage(B.a, 0, 0);
      g.globalAlpha = 1;
      ctx.globalCompositeOperation = 'lighter';
      ctx.drawImage(B.b, 0, 0, S.w, S.h);                          // one full-size layer, added over the picture
    }

    function ringScale() {
      let k = 1;
      if (S.state === 'listening') k *= 0.92;                       // the rings draw in
      if (S.level > 0.01) k *= 1 + 0.05 * S.level;                  // and pulse out with the voice
      return k;
    }

    function nodePos(n, t, k) {
      const o = S.orbitBy.get(n.orbit) || RING_BY.get(n.ring);
      return ringPoint(o, n.theta0 + o.speed * t, k);
    }

    function draw() {
      const t0 = now();
      if (!size()) return false;
      const ctx = S.ctx || (S.ctx = cv.getContext('2d'));
      const still = reduced();
      const tw = (Date.now() - S.startWall) / 1000;               // the clock for beats and pulses
      const t = still ? 0 : tw;                                   // the clock for motion: stopped with reduced motion
      const v = view(), C = S.theme;
      const k = ringScale();
      S.trig = trig();
      ctx.setTransform(S.dpr, 0, 0, S.dpr, 0, 0);
      ctx.globalCompositeOperation = 'source-over';
      ctx.globalAlpha = 1;
      ctx.fillStyle = rgba(C.bg, 1);
      ctx.fillRect(0, 0, S.w, S.h);
      ctx.drawImage(floor(), 0, 0, S.w, S.h);
      traces(ctx, v, C);

      const bl = bloomBegin();
      ctx.globalCompositeOperation = 'lighter';
      const spin = t * 0.01;
      shells(ctx, bl, v, C, spin);
      const P = memories(ctx, bl, v, C, t, k);
      const N = S.graph.nodes;
      const where = new Map();
      const tmp = S.tmp;
      for (const n of N) {
        const q = nodePos(n, t, k);
        proj(q[0], q[1], q[2], v, S.trig, tmp, 0);
        where.set(n.id, [tmp[0], tmp[1], tmp[2], tmp[3]]);
      }
      S.where = where;
      orbits(ctx, bl, v, C, k);
      links(ctx, bl, v, C, where);

      // Listening: ripples moving in toward the centre.
      if (S.state === 'listening') {
        const phases = still ? [0.45] : [0, 1 / 3, 2 / 3].map((o) => ((t * 0.55 + o) % 1));
        phases.forEach((ph) => {
          ctx.strokeStyle = rgba(C.glow, (0.4 * (1 - ph) + 0.06).toFixed(3));
          ctx.lineWidth = 1.4;
          ctx.beginPath();
          ctx.arc(v.cx, v.cy, v.R * (1.02 - ph * 0.86), 0, TAU);
          ctx.stroke();
        });
      }
      // Speaking: a ripple outward on each word.
      S.beats = S.beats.filter((b) => tw - b.at < 1.4);
      S.beats.forEach((b) => {
        const ph = (tw - b.at) / 1.4;
        ctx.strokeStyle = rgba(C.hot, (0.35 * (1 - ph) * b.level).toFixed(3));
        ctx.lineWidth = 1.8;
        ctx.beginPath();
        ctx.arc(v.cx, v.cy, v.R * (0.12 + ph * 0.95), 0, TAU);
        ctx.stroke();
      });

      if (S.state === 'thinking') thinking(ctx, bl, v, C, t, where, P);
      // Beams: the core pointing at a node.
      const wall = Date.now();
      S.beams = S.beams.filter((b) => b.until > wall);
      S.beams.forEach((b) => {
        const p = where.get(b.id);
        if (!p) return;
        const fade = Math.min(1, (b.until - wall) / 1200);
        [[6, 0.08], [2.5, 0.22], [1, 0.75]].forEach(([lw, a]) => {
          ctx.strokeStyle = rgba(C.magenta, (a * fade).toFixed(3));
          ctx.lineWidth = lw;
          ctx.beginPath(); ctx.moveTo(v.cx, v.cy); ctx.lineTo(p[0], p[1]); ctx.stroke();
        });
        if (bl) { bl.strokeStyle = rgba(C.magenta, (0.6 * fade).toFixed(3)); bl.lineWidth = 6; bl.beginPath(); bl.moveTo(v.cx, v.cy); bl.lineTo(p[0], p[1]); bl.stroke(); }
        if (!still) {
          const f = ((wall - b.from) / 900) % 1;
          ctx.drawImage(sprite(C.hot, true), v.cx + (p[0] - v.cx) * f - 6, v.cy + (p[1] - v.cy) * f - 6, 12, 12);
        }
      });

      // Each node: a point of light, bigger and brighter on the near side; lit ones in the eye's magenta.
      const lit = S.lit && S.lit.until > wall ? S.lit.ids : null;
      if (S.lit && S.lit.until <= wall) S.lit = null;
      for (const n of N) {
        const p = where.get(n.id), g = RING_BY.get(n.ring);
        const near = Math.max(0, Math.min(1, 0.55 - p[3] * 0.7));
        let col = C.rings[g.i], sz = (6 + 8 * near) * p[2];
        if (n.state === 'down') col = C.danger;
        else if (n.state === 'warning') col = C.warn;
        if (n.state === 'active' || n.busy) sz *= 1.35;
        if (n.done) sz *= 0.6;
        const isLit = lit && lit.has(n.id);
        if (isLit) { col = C.magenta; sz = Math.max(sz, 14) * (1 + 0.12 * Math.sin(t * 4)); }
        if (n.id === S.hover || (S.fly && S.fly.id === n.id)) sz *= 1.6;
        const a = isLit ? 1 : 0.5 + 0.5 * near;
        ctx.globalAlpha = a;
        ctx.drawImage(sprite(col, isLit || near > 0.7), p[0] - sz / 2, p[1] - sz / 2, sz, sz);
        if (bl) { bl.globalAlpha = a * 0.8; bl.drawImage(sprite(col), p[0] - sz * 1.5, p[1] - sz * 1.5, sz * 3, sz * 3); }
      }
      ctx.globalAlpha = 1;
      if (bl) bl.globalAlpha = 1;
      // Reminders: a node pulses once.
      S.pulses = S.pulses.filter((q) => wall - q.at < 1600);
      S.pulses.forEach((q) => {
        const p = where.get(q.id);
        if (!p) return;
        const ph = (wall - q.at) / 1600;
        ctx.strokeStyle = rgba(C.magenta, (0.9 * (1 - ph)).toFixed(3));
        ctx.lineWidth = 2;
        ctx.beginPath(); ctx.arc(p[0], p[1], 6 + ph * 34, 0, TAU); ctx.stroke();
      });

      centre(ctx, bl, v, C, t, still);
      bloomEnd(ctx);
      words(ctx, v, C, spin, where, N);

      // The eye sits on the centre.
      placeEye(v);
      const ms = now() - t0;
      const st = S.stats;
      st.frames += 1; st.total += ms; st.last = ms; st.max = Math.max(st.max, ms);
      st.recent = st.recent ? st.recent * 0.8 + ms * 0.2 : ms;
      st.points = S.graph.points.length + N.length;
      S.drawnAt = Date.now();
      return true;
    }

    // Traces: smart elbow hairlines joining every movable HUD overlay to the Core's orbital ring.
    function traces(ctx, v, C) {
      if (!S.anchors.length) return;
      const rr = v.R * SHELL_R * 1.02;
      const pts = [];
      ctx.strokeStyle = rgba(C.line, 0.36);
      ctx.lineWidth = 1.15;
      ctx.beginPath();
      S.anchors.forEach((a) => {
        if (!a || a.skip) return;
        let ax = a.x, ay = a.y, vert = false;
        if (a.box && a.box.width > 0 && a.box.height > 0) {
          const b = a.box;
          const bcx = b.left + b.width / 2, bcy = b.top + b.height / 2;
          const dx = v.cx - bcx, dy = v.cy - bcy;
          if (Math.abs(dy) > Math.abs(dx) * 1.18) {
            vert = true;
            ax = Math.max(b.left + 18, Math.min(b.left + b.width - 18, v.cx * 0.35 + bcx * 0.65));
            ay = dy >= 0 ? b.top + b.height : b.top;
          } else {
            ax = dx >= 0 ? b.left + b.width : b.left;
            ay = Math.max(b.top + 16, Math.min(b.top + b.height - 16, v.cy * 0.25 + bcy * 0.75));
          }
        }
        if (!Number.isFinite(ax) || !Number.isFinite(ay)) return;
        const ang = Math.atan2(ay - v.cy, ax - v.cx);
        const ex = v.cx + Math.cos(ang) * rr, ey = v.cy + Math.sin(ang) * rr;
        if (Math.hypot(ax - ex, ay - ey) < 16) return;
        if (a.box && ex >= a.box.left - 4 && ex <= a.box.left + a.box.width + 4 && ey >= a.box.top - 4 && ey <= a.box.top + a.box.height + 4) return;
        ctx.moveTo(ax, ay);
        if (vert) {
          const my = ay + (ey - ay) * 0.45;
          ctx.lineTo(ax, my);
        } else {
          const mx = ax + (ex - ax) * 0.45;
          ctx.lineTo(mx, ay);
        }
        ctx.lineTo(ex, ey);
        pts.push([ax, ay], [ex, ey]);
      });
      ctx.stroke();
      ctx.fillStyle = rgba(C.glow, 0.78);
      pts.forEach(([x, y]) => ctx.fillRect(x - 1.5, y - 1.5, 3, 3));
    }

    // The three rings of dashed arcs: the groups on the shell, their sub-groups just inside, the stores near the centre.
    function shells(ctx, bl, v, C, spin) {
      ctx.lineWidth = Math.max(2, v.R * 0.018);
      ctx.setLineDash([2, 3]);
      S.arcs.forEach((a) => {
        ctx.strokeStyle = rgba(C.rings[RING_BY.get(a.id).i], 0.6);
        ctx.beginPath();
        ctx.arc(v.cx, v.cy, v.R * SHELL_R, a.from + spin, a.to + spin);
        ctx.stroke();
      });
      ctx.lineWidth = Math.max(1.5, v.R * 0.009);
      ctx.setLineDash([1, 3]);
      S.subArcs.forEach((a) => {
        ctx.strokeStyle = rgba(C.rings[RING_BY.get(a.ring).i], 0.5);
        ctx.beginPath();
        ctx.arc(v.cx, v.cy, v.R * INNER_R, a.from + spin, a.to + spin);
        ctx.stroke();
      });
      ctx.lineWidth = Math.max(2, v.R * 0.012);
      ctx.setLineDash([3, 2]);
      S.storeArcs.forEach((a, i) => {
        ctx.strokeStyle = rgba(C.mem[i % 3], 0.65);
        ctx.beginPath();
        ctx.arc(v.cx, v.cy, v.R * STORE_R, a.from - spin * 0.8, a.to - spin * 0.8);
        ctx.stroke();
      });
      ctx.setLineDash([]);
      if (!bl) return;
      bl.lineWidth = Math.max(4, v.R * 0.035);
      S.arcs.forEach((a) => {
        bl.strokeStyle = rgba(C.rings[RING_BY.get(a.id).i], 0.22);
        bl.beginPath();
        bl.arc(v.cx, v.cy, v.R * SHELL_R, a.from + spin, a.to + spin);
        bl.stroke();
      });
    }

    // Memories: every one a point on its store's spoke, with the spoke itself a faint line from the centre.
    function memories(ctx, bl, v, C, t, k) {
      const pts = S.graph.points, n = pts.length, T = S.trig, tmp = S.tmp;
      if (S.proj.length < n * 4) S.proj = new Float32Array(n * 4);
      const P = S.proj;
      const turn = t * 0.006, cs = Math.cos(turn), sn = Math.sin(turn);
      for (let i = 0; i < n; i += 1) {
        const p = pts[i];
        proj((p.x * cs + p.z * sn) * k, p.y * k, (-p.x * sn + p.z * cs) * k, v, T, P, i * 4);
      }
      if (Path && S.graph.spokes.length) {
        const near = new Path(), far = new Path();
        S.graph.spokes.forEach((s) => {
          const rx = s.x * cs + s.z * sn, rz = -s.x * sn + s.z * cs, a = 0.1 * k, b = s.len * k;
          proj(rx * a, s.y * a, rz * a, v, T, tmp, 0);
          const x0 = tmp[0], y0 = tmp[1];
          proj(rx * b, s.y * b, rz * b, v, T, tmp, 0);
          const path = tmp[3] < 0 ? near : far;
          path.moveTo(x0, y0); path.lineTo(tmp[0], tmp[1]);
        });
        stroke(ctx, far, C.rings[2], 0.1, 0.8);
        stroke(ctx, near, C.rings[2], 0.22, 1);
        if (bl) stroke(bl, near, C.rings[2], 0.14, 3);
      }
      // By store tint and four steps of depth: one fill colour each (not one per point).
      if (!S.bucket || S.bucket.length < n) S.bucket = new Uint8Array(n);
      const B = S.bucket;
      for (let i = 0; i < n; i += 1) B[i] = (pts[i].si % 3) * 4 + Math.round(3 * Math.max(0, Math.min(1, 0.5 - P[i * 4 + 3] * 0.6)));
      for (let b = 0; b < 12; b += 1) {
        const d = b % 4, f = 1.1 + 0.5 * d;
        ctx.fillStyle = rgba(C.mem[(b / 4) | 0], (0.32 + 0.2 * d).toFixed(2));
        for (let i = 0; i < n; i += 1) {
          if (B[i] !== b) continue;
          const o = i * 4, s = P[o + 2] * f;
          ctx.fillRect(P[o] - s / 2, P[o + 1] - s / 2, s, s);
        }
      }
      // A glint on one in five of the nearest.
      ctx.globalAlpha = 0.55;
      for (let i = 0, glints = 0; i < n && glints < 240; i += 5) {
        if ((B[i] & 3) < 3) continue;
        const o = i * 4, s = P[o + 2] * 7;
        ctx.drawImage(sprite(C.mem[pts[i].si % 3]), P[o] - s / 2, P[o + 1] - s / 2, s, s);
        glints += 1;
      }
      ctx.globalAlpha = 1;
      if (bl) {
        bl.fillStyle = rgba(C.glow, 0.2);
        for (let i = 0; i < n; i += 1) bl.fillRect(P[i * 4] - 2, P[i * 4 + 1] - 2, 4, 4);
      }
      return P;
    }

    // The orbits: each group's thick and soft (as bright as the group is big), each sub-group's a thin line.
    function orbits(ctx, bl, v, C, k) {
      if (!Path) return;
      const live = new Set(S.graph.nodes.map((n) => n.ring));
      const max = Math.max(1, ...RINGS.map((g) => S.counts[g.id] || 0));
      const tmp = S.tmp, T = S.trig;
      RINGS.filter((g) => live.has(g.id)).concat(S.graph.orbits).forEach((o) => {
        const near = new Path(), far = new Path();
        let px = 0, py = 0, pz = 0;
        for (let i = 0; i <= SEGS; i += 1) {
          const q = ringPoint(o, (i / SEGS) * TAU, k);
          proj(q[0], q[1], q[2], v, T, tmp, 0);
          if (i) { const path = pz + tmp[3] < 0 ? near : far; path.moveTo(px, py); path.lineTo(tmp[0], tmp[1]); }
          px = tmp[0]; py = tmp[1]; pz = tmp[3];
        }
        if (!o.ring) {
          const col = C.rings[o.i], w = 0.35 + 0.65 * Math.sqrt((S.counts[o.id] || 0) / max);
          stroke(ctx, far, col, 0.1 + 0.12 * w, 0.8 + 0.6 * w);
          stroke(ctx, near, col, 0.05 + 0.06 * w, 4 + 6 * w);           // the soft falloff
          stroke(ctx, near, col, 0.4 + 0.45 * w, 1.1 + 1.5 * w);
          if (bl) stroke(bl, near, col, 0.3 + 0.45 * w, 6 + 10 * w);
        } else {
          const col = C.rings[RING_BY.get(o.ring).i];
          stroke(ctx, far, col, 0.14, 0.7);
          stroke(ctx, near, col, 0.5, 1);
          if (bl) stroke(bl, near, col, 0.2, 3);
        }
      });
    }

    // Links between nodes (a part and what it holds, a wire, a tool and the service it runs on): lines bowed through the
    // core, so they cross near the centre and add up to bright there.
    function links(ctx, bl, v, C, where) {
      const L = S.graph.links;
      if (!Path || !L.length) return;
      const hold = new Path(), flow = new Path(), wire = new Path();
      L.forEach((l) => {
        const a = where.get(l.a), b = where.get(l.b);
        if (!a || !b) return;
        const path = l.kind === 'wire' ? wire : l.kind === 'contains' ? hold : flow;
        const mx = (a[0] + b[0]) / 2, my = (a[1] + b[1]) / 2;
        path.moveTo(a[0], a[1]);
        path.quadraticCurveTo(mx + (v.cx - mx) * 0.4, my + (v.cy - my) * 0.4, b[0], b[1]);
      });
      stroke(ctx, hold, C.line, 0.2, 0.8);
      stroke(ctx, flow, C.glow, 0.3, 1);
      stroke(ctx, wire, C.hot, 0.32, 1);
      if (bl) { stroke(bl, flow, C.glow, 0.18, 3); stroke(bl, wire, C.hot, 0.14, 3); }
    }

    // A jagged line of light from (x0,y0) to (x1,y1), added to a path; returns its points.
    function bolt(path, x0, y0, x1, y1, t, seed, segs, amp) {
      const dx = x1 - x0, dy = y1 - y0, len = Math.hypot(dx, dy) || 1, nx = -dy / len, ny = dx / len;
      const pts = [[x0, y0]];
      path.moveTo(x0, y0);
      for (let s = 1; s < segs; s += 1) {
        const f = s / segs, j = Math.sin(t * 3.1 + seed * 1.7 + s * 2.3) * Math.min(amp, len * 0.07) * Math.sin(Math.PI * f);
        const x = x0 + dx * f + nx * j, y = y0 + dy * f + ny * j;
        path.lineTo(x, y);
        pts.push([x, y]);
      }
      path.lineTo(x1, y1);
      pts.push([x1, y1]);
      return pts;
    }
    // Two side branches off a bolt, each with a twig.
    function branch(path, pts, t, seed) {
      const a0 = pts[0], a1 = pts[pts.length - 1];
      const len = Math.hypot(a1[0] - a0[0], a1[1] - a0[1]), dir = Math.atan2(a1[1] - a0[1], a1[0] - a0[0]);
      [[2, 0.55, 0.32], [4, -0.5, 0.24]].forEach(([at, turn, frac], bi) => {
        const p = pts[Math.min(at, pts.length - 2)];
        const ang = dir + turn * (1 + 0.2 * Math.sin(t * 0.7 + seed + bi)), L = len * frac;
        const sub = bolt(path, p[0], p[1], p[0] + Math.cos(ang) * L, p[1] + Math.sin(ang) * L, t, seed * 3 + bi + 1, 4, 6);
        const tw = sub[2], a2 = ang - turn * 0.9;
        bolt(path, tw[0], tw[1], tw[0] + Math.cos(a2) * L * 0.45, tw[1] + Math.sin(a2) * L * 0.45, t, seed * 7 + bi, 3, 4);
      });
    }
    // Thinking: branching filaments from the centre to what it is reading, and on into a store's memories.
    function thinking(ctx, bl, v, C, t, where, P) {
      if (!Path) return;
      const main = new Path(), side = new Path(), sparks = [];
      const targets = S.reading.map((id) => [id, where.get(id)]).filter((x) => x[1]).slice(0, 24);
      targets.forEach(([id, p], i) => {
        branch(side, bolt(main, v.cx, v.cy, p[0], p[1], t, i, 7, 14), t, i);
        sparks.push([p[0], p[1], i]);
        const n = S.byId.get(id), idx = n && n.store ? S.storePts.get(n.store) : null;
        if (idx && idx.length) {
          const step = Math.max(1, Math.floor(idx.length / 6)), off = Math.floor(t * 0.7) * 3;
          for (let j = 0; j < Math.min(6, idx.length); j += 1) {
            const q = idx[(off + j * step) % idx.length] * 4;
            bolt(side, p[0], p[1], P[q], P[q + 1], t, i * 11 + j, 3, 5);
          }
        }
      });
      if (!targets.length) {                                        // nothing named yet: branching light in the core
        for (let i = 0; i < 9; i += 1) {
          const a = (i / 9) * TAU + t * 0.4, r1 = v.R * 0.14, r2 = v.R * (0.42 + 0.08 * Math.sin(t * 2 + i));
          const pts = bolt(main, v.cx + Math.cos(a) * r1, v.cy + Math.sin(a) * r1, v.cx + Math.cos(a) * r2, v.cy + Math.sin(a) * r2, t, i, 6, 10);
          branch(side, pts, t, i);
        }
      }
      stroke(ctx, side, C.glow, 0.34, 0.8);
      stroke(ctx, main, C.glow, 0.22, 3.2);
      stroke(ctx, main, C.hot, 0.7, 1.1);
      if (bl) { stroke(bl, main, C.glow, 0.6, 7); stroke(bl, side, C.glow, 0.28, 3); }
      sparks.forEach(([x1, y1, i]) => {
        const f = (t * 0.8 + i * 0.13) % 1;
        ctx.drawImage(sprite(C.hot, true), v.cx + (x1 - v.cx) * f - 4, v.cy + (y1 - v.cy) * f - 4, 8, 8);
      });
    }

    // The centre: a large white-hot core inside three segmented rings close around it, turning slowly.
    function centre(ctx, bl, v, C, t, still) {
      const pulse = 1 + 0.25 * S.level + (S.state === 'thinking' && !still ? 0.06 * Math.sin(t * 5) : 0);
      const hotR = v.R * 0.4 * pulse;
      const core = ctx.createRadialGradient(v.cx, v.cy, 0, v.cx, v.cy, hotR);
      core.addColorStop(0, rgba(C.hot, 1)); core.addColorStop(0.2, rgba(C.hot, 1)); core.addColorStop(0.34, rgba(C.hot, 0.7));
      core.addColorStop(0.5, rgba(C.glow, 0.5)); core.addColorStop(0.75, rgba(C.line, 0.16)); core.addColorStop(1, rgba(C.line, 0));
      ctx.fillStyle = core;
      ctx.fillRect(v.cx - hotR, v.cy - hotR, hotR * 2, hotR * 2);
      if (bl) {
        const g = bl.createRadialGradient(v.cx, v.cy, 0, v.cx, v.cy, v.R * 0.62 * pulse);
        g.addColorStop(0, rgba(C.hot, 0.9)); g.addColorStop(0.3, rgba(C.glow, 0.45)); g.addColorStop(1, rgba(C.line, 0));
        bl.fillStyle = g;
        bl.fillRect(v.cx - v.R * 0.62 * pulse, v.cy - v.R * 0.62 * pulse, v.R * 1.24 * pulse, v.R * 1.24 * pulse);
      }
      // radius, segments, turn, width, colour, alpha
      [[0.19, 24, 1, 3.2, C.glow, 0.6], [0.226, 60, -1, 1.4, C.hot, 0.5], [0.265, 12, 1, 4.6, C.glow, 0.45]].forEach(([rr, n, dir, lw, col, a]) => {
        const r = v.R * rr * pulse, a0 = t * 0.15 * dir;
        const path = Path ? new Path() : null;
        if (!path) return;
        for (let s = 0; s < n; s += 1) {
          const from = a0 + (s / n) * TAU;
          path.moveTo(v.cx + Math.cos(from) * r, v.cy + Math.sin(from) * r);
          path.arc(v.cx, v.cy, r, from, from + (TAU / n) * 0.58);
        }
        stroke(ctx, path, col, a * 0.3, lw * 2.6);
        stroke(ctx, path, col, a, lw);
        if (bl) stroke(bl, path, col, a * 0.8, lw * 3);
      });
      if ((S.state === 'speaking' || S.level > 0.08) && Path) {
        const spokes = 28, lvl = Math.max(0.2, S.level), bars = new Path();
        for (let s = 0; s < spokes; s += 1) {
          const ang = (s / spokes) * TAU + t * 0.28;
          const amp = (0.015 + 0.045 * lvl * (0.5 + 0.5 * Math.sin(t * 9 + s * 1.7)));
          const r0 = v.R * 0.275 * pulse, r1 = v.R * (0.275 + amp) * pulse;
          bars.moveTo(v.cx + Math.cos(ang) * r0, v.cy + Math.sin(ang) * r0);
          bars.lineTo(v.cx + Math.cos(ang) * r1, v.cy + Math.sin(ang) * r1);
        }
        stroke(ctx, bars, C.magenta, 0.72, 2);
        if (bl) stroke(bl, bars, C.glow, 0.55, 4);
      }
    }

    // Words: the arcs' labels and the near nodes' names when you come closer (the one under the pointer at any zoom).
    function words(ctx, v, C, spin, where, N) {
      ctx.globalCompositeOperation = 'source-over';
      ctx.textBaseline = 'middle';
      if (S.cam.zoom >= LABEL_ZOOM) {
        ctx.font = '600 11px ui-sans-serif, system-ui, sans-serif';
        S.arcs.forEach((a) => {
          arcText(ctx, `${a.label.toUpperCase()} · ${a.count}`, v.cx, v.cy, v.R * SHELL_R + 14, (a.from + a.to) / 2 + spin, rgba(C.hot, 0.75));
        });
        ctx.font = '10px ui-sans-serif, system-ui, sans-serif';
        const inner = v.R * INNER_R - 11, close = v.R * STORE_R + 12;
        if (S.subArcs.length > S.arcs.length) {
          S.subArcs.slice(0, 48).forEach((a) => {
            const text = `${String(a.label).toUpperCase()} · ${a.count}`;
            if (ctx.measureText(text).width / inner < a.to - a.from) arcText(ctx, text, v.cx, v.cy, inner, (a.from + a.to) / 2 + spin, rgba(C.hot, 0.6));
          });
        }
        S.storeArcs.slice(0, 24).forEach((a) => {
          const text = `${String(a.label)} · ${a.count.toLocaleString()}`;
          if (ctx.measureText(text).width / close < a.to - a.from) arcText(ctx, text, v.cx, v.cy, close, (a.from + a.to) / 2 - spin * 0.8, rgba(C.hot, 0.7));
        });
        ctx.font = '11px ui-sans-serif, system-ui, sans-serif';
        const near = N.map((n) => [n, where.get(n.id)]).filter(([, p]) => p[3] < 0.05).sort((a, b) => a[1][3] - b[1][3]).slice(0, 40);
        near.forEach(([n, p]) => label(ctx, n.label, p[0] + 8, p[1], rgba(C.hot, 0.8)));
      }
      const hov = S.hover && where.get(S.hover);
      const hn = S.hover && S.byId.get(S.hover);
      if (hov && hn) {
        ctx.font = '600 12px ui-sans-serif, system-ui, sans-serif';
        label(ctx, hn.label, hov[0] + 10, hov[1] - 7, '#fff');
        if (hn.info) { ctx.font = '11px ui-sans-serif, system-ui, sans-serif'; label(ctx, String(hn.info).slice(0, 80), hov[0] + 10, hov[1] + 8, rgba(C.hot, 0.7)); }
      }
    }
    function label(ctx, text, x, y, colour) {
      const s = String(text || '').slice(0, 48);
      if (!s) return;
      const w = ctx.measureText(s).width;
      ctx.fillStyle = 'rgba(5,4,10,0.72)';
      ctx.fillRect(x - 3, y - 8, w + 6, 16);
      ctx.fillStyle = colour;
      ctx.fillText(s, x, y);
    }
    // Text along a circle, centred on an angle.
    function arcText(ctx, text, cx, cy, r, mid, colour) {
      const widths = Array.from(text).map((ch) => ctx.measureText(ch).width);
      const total = widths.reduce((a, b) => a + b, 0);
      let a = mid - total / r / 2;
      const flip = Math.sin(mid) > 0.2;                          // on the lower half, read left to right the other way
      const chars = Array.from(text);
      if (flip) { chars.reverse(); widths.reverse(); a = mid - total / r / 2; }
      ctx.fillStyle = colour;
      chars.forEach((ch, i) => {
        const ca = a + widths[i] / 2 / r;
        ctx.save();
        ctx.translate(cx + Math.cos(ca) * r, cy + Math.sin(ca) * r);
        ctx.rotate(ca + (flip ? -Math.PI / 2 : Math.PI / 2));
        ctx.fillText(ch, -widths[i] / 2, 0);
        ctx.restore();
        a += widths[i] / r;
      });
    }
    let eyeBox = '';
    function placeEye(v) {
      const sz = Math.round(Math.max(48, Math.min(150, v.R * 0.3)));
      const box = Math.round(v.cx - sz / 2) + ',' + Math.round(v.cy - sz / 2) + ',' + sz;
      if (box === eyeBox) return;
      eyeBox = box;
      eyeHost.style.width = eyeHost.style.height = sz + 'px';
      eyeHost.style.transform = `translate(${Math.round(v.cx - sz / 2)}px,${Math.round(v.cy - sz / 2)}px)`;
      eyeHost.style.visibility = '';
    }

    // ---- motion -----------------------------------------------------------------------------------------------------
    function busy() {
      const wall = Date.now();
      return S.state !== 'idle' || S.level > 0.01 || S.fly || S.drag || S.beams.length || S.pulses.length || S.beats.length ||
        (S.lit && S.lit.until > wall);
    }
    // Idle frames come at most ten a second, and further apart when a frame costs more (at most ~8% of one core).
    function idleMs() { return Math.min(400, Math.max(IDLE_MS, Math.round(S.stats.recent * 12))); }
    function step() {
      S.raf = 0; S.timer = 0;
      if (!S.running || S.hidden) return;
      if (S.fly) {
        const f = Math.min(1, (Date.now() - S.fly.at) / S.fly.ms), e = ease(f);
        ['yaw', 'pitch', 'zoom', 'panX', 'panY'].forEach((key) => { S.cam[key] = S.fly.from[key] + (S.fly.to[key] - S.fly.from[key]) * e; });
        if (f >= 1) { const done = S.fly.then; S.fly = null; emitView(); if (done) done(); }
      }
      S.level *= 0.9;
      draw();
      schedule();
    }
    function schedule() {
      if (!S.running || S.hidden || S.raf || S.timer) return;
      if (reduced()) return;                                     // a still picture; state changes redraw it
      if (busy()) S.raf = win.requestAnimationFrame(step);
      else S.timer = win.setTimeout(step, idleMs());
    }
    function kick() {
      if (reduced() || !S.running) { if (S.running && !S.hidden) draw(); return; }
      if (S.timer) { win.clearTimeout(S.timer); S.timer = 0; }
      if (!S.raf) S.raf = win.requestAnimationFrame(step);
    }
    function stop() {
      if (S.raf) win.cancelAnimationFrame(S.raf);
      if (S.timer) win.clearTimeout(S.timer);
      S.raf = 0; S.timer = 0;
    }
    S.startWall = Date.now();
    const onVis = () => { S.hidden = !!doc.hidden; if (S.hidden) stop(); else kick(); };
    doc.addEventListener('visibilitychange', onVis);
    let ro = null;
    if (win.ResizeObserver) { ro = new win.ResizeObserver(() => { S.floor = null; kick(); }); ro.observe(host); }

    function emitView() { if (opts.onView) { try { opts.onView({ zoom: S.cam.zoom }); } catch (_) {} } }
    function flyTo(id, zoom, then) {
      const n = S.byId.get(id);
      if (!n) return false;
      const t = reduced() ? 0 : (Date.now() - S.startWall) / 1000;
      const p = nodePos(n, t, 1);
      const face = facing(p);
      const to = { yaw: face.yaw, pitch: Math.max(-1.1, Math.min(1.1, face.pitch * 0.5)), zoom: clampZoom(zoom || 1.7), panX: 0, panY: 0 };
      // Centre the node: where it lands after the turn, at the new zoom.
      const keep = S.cam;
      S.cam = Object.assign({}, keep, to, { panX: 0, panY: 0 });
      const v = view(), out = new Float32Array(4);
      project(p, v, out, 0);
      S.cam = keep;
      to.panX = Math.max(-S.w * 0.35, Math.min(S.w * 0.35, v.cx - out[0]));
      to.panY = Math.max(-S.h * 0.3, Math.min(S.h * 0.3, v.cy - out[1]));
      const from = { yaw: S.cam.yaw, pitch: S.cam.pitch, zoom: S.cam.zoom, panX: S.cam.panX, panY: S.cam.panY };
      // The shorter way round.
      while (to.yaw - from.yaw > Math.PI) to.yaw -= TAU;
      while (from.yaw - to.yaw > Math.PI) to.yaw += TAU;
      if (reduced()) { Object.assign(S.cam, to); emitView(); draw(); if (then) then(); return true; }
      S.fly = { id, from, to, at: Date.now(), ms: 900, then };
      kick();
      return true;
    }

    // ---- pointer, wheel, keys ---------------------------------------------------------------------------------------
    function local(e) { const r = cv.getBoundingClientRect(); return [e.clientX - r.left, e.clientY - r.top]; }
    function hit(x, y) {
      if (!S.where) return null;
      let best = null, bestScore = Infinity;
      S.where.forEach((p, id) => {
        const d2 = (p[0] - x) * (p[0] - x) + (p[1] - y) * (p[1] - y);
        if (d2 > 18 * 18) return;
        const score = d2 + p[3] * 60;                            // the nearer of two close nodes wins
        if (score < bestScore) { best = id; bestScore = score; }
      });
      return best;
    }
    const pointers = new Map();
    let down = null, pinch = null;
    cv.addEventListener('pointerdown', (e) => {
      e.preventDefault(); e.stopPropagation();
      pointers.set(e.pointerId, local(e));
      try { cv.setPointerCapture(e.pointerId); } catch (_) {}
      if (pointers.size === 2) {
        const [a, b] = [...pointers.values()];
        pinch = { d: Math.hypot(a[0] - b[0], a[1] - b[1]) || 1, zoom: S.cam.zoom };
        down = null;
        return;
      }
      const [x, y] = local(e);
      down = { x, y, yaw: S.cam.yaw, pitch: S.cam.pitch, id: hit(x, y), moved: false };
      S.fly = null;
    });
    cv.addEventListener('pointermove', (e) => {
      const [x, y] = local(e);
      if (pointers.has(e.pointerId)) pointers.set(e.pointerId, [x, y]);
      if (pinch && pointers.size === 2) {
        const [a, b] = [...pointers.values()];
        zoomTo(pinch.zoom * (Math.hypot(a[0] - b[0], a[1] - b[1]) / pinch.d));
        return;
      }
      if (!down) {
        const id = hit(x, y);
        if (id !== S.hover) { S.hover = id; cv.style.cursor = id ? 'pointer' : 'grab'; kick(); }
        return;
      }
      if (Math.hypot(x - down.x, y - down.y) > 4) down.moved = true;
      if (down.moved) {
        S.drag = true;
        S.cam.yaw = down.yaw + (x - down.x) * 0.006;
        S.cam.pitch = Math.max(-1.2, Math.min(1.2, down.pitch + (y - down.y) * 0.006));
        kick();
      }
    });
    const up = (e) => {
      pointers.delete(e.pointerId);
      if (pointers.size < 2) pinch = null;
      if (!down) return;
      const d = down; down = null; S.drag = false;
      if (!d.moved && opts.onPick) opts.onPick(d.id ? S.byId.get(d.id) || null : null);
      kick();
    };
    cv.addEventListener('pointerup', up);
    cv.addEventListener('pointercancel', up);
    cv.addEventListener('pointerleave', () => { if (S.hover && !down) { S.hover = null; kick(); } });
    cv.addEventListener('dblclick', (e) => { e.preventDefault(); reset(); });
    function zoomTo(z) {
      const next = clampZoom(z);
      if (next === S.cam.zoom) return;
      S.cam.zoom = next;
      if (next === ZOOM_MIN) { S.cam.panX *= 0.5; S.cam.panY *= 0.5; }
      emitView();
      kick();
    }
    cv.addEventListener('wheel', (e) => {
      e.preventDefault(); e.stopPropagation();
      S.fly = null;
      if (e.deltaY < 0 && S.cam.zoom >= ZOOM_MAX - 1e-6) { if (opts.onZoomPast) opts.onZoomPast(); return; }
      zoomTo(S.cam.zoom * (e.deltaY < 0 ? 1.12 : 1 / 1.12));
    }, { passive: false });
    cv.addEventListener('keydown', (e) => {
      const turn = { ArrowLeft: [-0.12, 0], ArrowRight: [0.12, 0], ArrowUp: [0, -0.1], ArrowDown: [0, 0.1] }[e.key];
      if (turn && !e.altKey) { e.preventDefault(); S.cam.yaw += turn[0]; S.cam.pitch = Math.max(-1.2, Math.min(1.2, S.cam.pitch + turn[1])); kick(); }
      else if (e.key === '+' || e.key === '=') { e.preventDefault(); zoomTo(S.cam.zoom * 1.15); }
      else if (e.key === '-') { e.preventDefault(); zoomTo(S.cam.zoom / 1.15); }
      else if (e.key === '0') { e.preventDefault(); reset(); }
    });
    function reset() {
      S.fly = null;
      const from = Object.assign({}, S.cam), to = { yaw: 0.35, pitch: -0.28, zoom: 1, panX: 0, panY: 0 };
      if (reduced()) { Object.assign(S.cam, to); emitView(); draw(); return; }
      while (to.yaw - from.yaw > Math.PI) to.yaw -= TAU;
      while (from.yaw - to.yaw > Math.PI) to.yaw += TAU;
      S.fly = { id: '', from, to, at: Date.now(), ms: 700 };
      kick();
    }

    // ---- what the page tells it -------------------------------------------------------------------------------------
    const api = {
      setGraph(graph) {
        S.graph = layout(graph);
        S.byId = new Map(S.graph.nodes.map((n) => [n.id, n]));
        S.orbitBy = new Map(RINGS.map((g) => [g.id, g]).concat(S.graph.orbits.map((o) => [o.id, o])));
        const counts = {};
        RINGS.forEach((g) => { counts[g.id] = (graph && graph.rings && Array.isArray(graph.rings[g.id])) ? graph.rings[g.id].length : 0; });
        S.counts = counts;
        S.arcs = shellArcs(counts);
        S.subArcs = subArcs(S.arcs, S.graph.subs);
        S.storeArcs = storeArcs(S.graph.stores);
        S.storePts = new Map();
        S.graph.points.forEach((p, i) => { if (!S.storePts.has(p.store)) S.storePts.set(p.store, []); S.storePts.get(p.store).push(i); });
        if (S.hover && !S.byId.has(S.hover)) S.hover = null;
        kick();
      },
      setState(name) {
        const st = ['listening', 'thinking', 'speaking'].includes(name) ? name : 'idle';
        if (st === S.state) return;
        S.state = st;
        if (eye) { try { eye.setThinking(st === 'thinking'); eye.setMood(st === 'listening' || st === 'speaking' ? st : ''); } catch (_) {} }
        kick();
      },
      // A word was spoken: the core pulses out with it (browser speech gives no audio level, so each word is a beat).
      beat(level) {
        const l = Math.max(0.2, Math.min(1, Number(level) || 0.7));
        S.level = Math.max(S.level, l);
        S.beats.push({ at: (Date.now() - S.startWall) / 1000, level: l });
        if (S.beats.length > 8) S.beats.shift();
        kick();
      },
      reading(ids) { S.reading = (ids || []).filter((id) => S.byId.has(id)); kick(); },
      light(ids, ms) {
        const set = new Set((ids || []).filter((id) => S.byId.has(id)));
        S.lit = set.size ? { ids: set, until: Date.now() + (ms || 12000) } : null;
        kick();
        return set.size;
      },
      point(id, ms) {
        if (!S.byId.has(id)) return false;
        S.beams = S.beams.filter((b) => b.id !== id).concat({ id, from: Date.now(), until: Date.now() + (ms || 6000) });
        kick();
        return true;
      },
      pulse(id) { if (!S.byId.has(id)) return false; S.pulses.push({ id, at: Date.now() }); kick(); return true; },
      flyTo,
      // Pull a node forward, then open it.
      pull(id, then) { api.point(id, 2500); return flyTo(id, 2, then); },
      reset,
      zoom() { return S.cam.zoom; },
      setZoom(z) { zoomTo(z); },
      node(id) { return S.byId.get(id) || null; },
      nodes() { return S.graph.nodes.slice(); },
      setAnchors(list) { S.anchors = (list || []).filter((a) => a && isFinite(a.x) && isFinite(a.y)); kick(); },
      setTheme(name) { S.theme = themeColors(name, readVar); S.sprites.clear(); S.floor = null; kick(); return S.theme.name; },
      theme() { return S.theme.name; },
      start() { if (S.running) return; S.running = true; S.hidden = !!doc.hidden; kick(); },
      pause() { S.running = false; stop(); },
      redraw() { return draw(); },
      stats() {
        const st = S.stats, f = st.frames || 1, G = S.graph;
        return { frames: st.frames, avgMs: +(st.total / f).toFixed(2), maxMs: +st.max.toFixed(2), lastMs: +st.last.toFixed(2),
          recentMs: +st.recent.toFixed(2), idleMs: idleMs(), points: st.points, memoryPoints: G.points.length, nodes: G.nodes.length,
          orbits: RINGS.filter((g) => G.nodes.some((n) => n.ring === g.id)).length + G.orbits.length, spokes: G.spokes.length,
          links: G.links.length, bloom: S.bloom ? (S.bloom.blur ? 'blur' : 'soft') : 'off', width: S.w, height: S.h,
          dpr: +S.dpr.toFixed(2), running: S.running && !!(S.raf || S.timer), mode: S.raf ? 'frames' : S.timer ? 'idle' : 'still' };
      },
      resetStats() { S.stats = { frames: 0, total: 0, max: 0, last: 0, recent: S.stats.recent, points: S.stats.points }; },
      canvas: cv,
      destroy() {
        api.pause();
        doc.removeEventListener('visibilitychange', onVis);
        if (ro) ro.disconnect();
        host.removeChild(cv);
        host.removeChild(eyeHost);
      }
    };
    return api;
  }

  const AssimilisCore = { mount, geom };
  if (typeof module !== 'undefined' && module.exports) module.exports = AssimilisCore;
  if (root) root.AssimilisCore = AssimilisCore;
})(typeof window !== 'undefined' ? window : (typeof globalThis !== 'undefined' ? globalThis : this));
