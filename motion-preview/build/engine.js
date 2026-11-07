// Qoima motion engine — deterministic canvas renderer (time -> frame).
'use strict';
const W = 1080, H = 1920;
const C = {
  green: '#00A862', greenDeep: '#00713F', greenBright: '#19D27F', greenTint: '#E9FBF2',
  ink: '#0B1512', ink2: '#3D4A45', bg: '#F4F7F6', line: '#E9EFEC', white: '#FFFFFF',
  amber: '#FFA51F', red: '#F23B4F', redInk: '#C01B31', blue: '#2F7DF6', purple: '#7C5CFC',
  navy: '#1d3557', wood: '#C99A6B', woodDark: '#9C7148', wall: '#EDE6DA', floor: '#D9CBB5',
  whWall: '#C9CED6', whFloor: '#9AA1AB'
};
const FONT = '"Inter Display", "Inter", sans-serif';
const font = (w, s) => `${w} ${s}px ${FONT}`;

// ── math ──────────────────────────────────────────────────────────────────
const clamp = (v, a = 0, b = 1) => Math.max(a, Math.min(b, v));
const lerp = (a, b, t) => a + (b - a) * t;
const seg = (t, a, b) => clamp((t - a) / (b - a));
const E = {
  lin: t => t,
  inQ: t => t * t, outQ: t => 1 - (1 - t) * (1 - t),
  ioQ: t => t < .5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2,
  inC: t => t * t * t, outC: t => 1 - Math.pow(1 - t, 3),
  ioC: t => t < .5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2,
  outE: t => t === 1 ? 1 : 1 - Math.pow(2, -10 * t),
  ioE: t => t === 0 ? 0 : t === 1 ? 1 : t < .5 ? Math.pow(2, 20 * t - 10) / 2 : (2 - Math.pow(2, -20 * t + 10)) / 2,
  outBack: (t, s = 1.70158) => 1 + (s + 1) * Math.pow(t - 1, 3) + s * Math.pow(t - 1, 2),
};
// damped spring 0->1 (overshoot), t in seconds since start
function spring(t, freq = 2.2, damp = 5.5) {
  if (t <= 0) return 0;
  return 1 - Math.exp(-damp * t) * Math.cos(2 * Math.PI * freq * t);
}
// keyframed value: keys = [[t, v, ease?], ...]
function kf(t, keys) {
  if (t <= keys[0][0]) return keys[0][1];
  for (let i = 1; i < keys.length; i++) {
    const [t1, v1, e] = keys[i];
    const [t0, v0] = keys[i - 1];
    if (t <= t1) {
      const p = (e || E.ioC)(seg(t, t0, t1));
      if (Array.isArray(v0)) return v0.map((x, j) => lerp(x, v1[j], p));
      return lerp(v0, v1, p);
    }
  }
  return keys[keys.length - 1][1];
}
function rng(seed) { let s = seed >>> 0 || 1; return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296); }
function noise1(x, seed = 0) { // smooth value noise
  const i = Math.floor(x), f = x - i;
  const h = n => { const s = Math.sin((n + seed * 57.13) * 127.1) * 43758.5453; return s - Math.floor(s); };
  const u = f * f * (3 - 2 * f);
  return lerp(h(i), h(i + 1), u) * 2 - 1;
}

// ── drawing helpers ───────────────────────────────────────────────────────
function rr(ctx, x, y, w, h, r) {
  r = Math.min(r, w / 2, h / 2);
  ctx.beginPath();
  ctx.moveTo(x + r, y); ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath();
}
function fillRR(ctx, x, y, w, h, r, fill, stroke, lw = 3) {
  rr(ctx, x, y, w, h, r);
  if (fill) { ctx.fillStyle = fill; ctx.fill(); }
  if (stroke) { ctx.strokeStyle = stroke; ctx.lineWidth = lw; ctx.stroke(); }
}
function circle(ctx, x, y, r, fill, stroke, lw = 3) {
  ctx.beginPath(); ctx.arc(x, y, Math.max(0, r), 0, Math.PI * 2);
  if (fill) { ctx.fillStyle = fill; ctx.fill(); }
  if (stroke) { ctx.strokeStyle = stroke; ctx.lineWidth = lw; ctx.stroke(); }
}
function shadowOn(ctx, blur = 30, y = 12, a = 0.18) { ctx.shadowColor = `rgba(11,21,18,${a})`; ctx.shadowBlur = blur; ctx.shadowOffsetY = y; ctx.shadowOffsetX = 0; }
function shadowOff(ctx) { ctx.shadowColor = 'transparent'; ctx.shadowBlur = 0; ctx.shadowOffsetY = 0; }
function text(ctx, s, x, y, f, color, align = 'center', base = 'middle') {
  if (typeof s === 'string') s = L(s);
  ctx.font = f; ctx.fillStyle = color; ctx.textAlign = align; ctx.textBaseline = base; ctx.fillText(s, x, y);
}
function withT(ctx, fn) { ctx.save(); fn(); ctx.restore(); }

// ── characters ────────────────────────────────────────────────────────────
const SKIN = { a: '#E3B08A', b: '#F1C4A0', c: '#D9A47F', d: '#EDBE98', e: '#F7D0B0', f: '#C98E68' };
const PEOPLE = {
  owner:  { skin: SKIN.a, body: C.navy, body2: '#183050', pants: '#16202c', shoe: C.ink, hair: '#2b2b2e', hairStyle: 'owner', wide: 1.35, legW: 50, outfit: 'suit' },
  yeraly: { skin: SKIN.a, body: '#FFFFFF', pants: '#3b4a56', shoe: '#fff', hair: C.ink, hairStyle: 'short', wide: 1, legW: 36, outfit: 'apron' },
  sly:    { skin: SKIN.d, body: '#7a7f8c', pants: '#2b2f3a', shoe: '#555', hair: '#4b3320', hairStyle: 'side', wide: 1, legW: 36, outfit: 'sweater' },
  seller3:{ skin: SKIN.c, body: '#FFFFFF', pants: '#2b3a4a', shoe: '#fff', hair: '#1b1b1b', hairStyle: 'cap', wide: 1, legW: 36, outfit: 'apron', cap: C.green },
  madina: { skin: SKIN.e, body: C.amber, pants: C.blue, shoe: '#fff', hair: '#8a4b2a', hairStyle: 'buns', wide: 1, legW: 34, outfit: 'jacket' },
  aru:    { skin: SKIN.b, body: C.purple, pants: '#2b2f3a', shoe: '#fff', hair: '#1d1410', hairStyle: 'long', wide: 0.95, legW: 32, outfit: 'jacket' },
  timur:  { skin: SKIN.c, body: C.red, pants: '#2b3a4a', shoe: '#fff', hair: '#1b1b1b', hairStyle: 'short', wide: 1.05, legW: 36, outfit: 'hoodie' },
  c1:     { skin: SKIN.b, body: '#2EC4B6', pants: '#33415c', shoe: '#fff', hair: '#3a2618', hairStyle: 'long', wide: 0.95, legW: 32, outfit: 'jacket' },
  c2:     { skin: SKIN.f, body: '#FF7B54', pants: '#2b2f3a', shoe: '#fff', hair: '#151515', hairStyle: 'short', wide: 1.05, legW: 36, outfit: 'hoodie' },
  c3:     { skin: SKIN.a, body: '#8E7DBE', pants: '#3b4a56', shoe: '#fff', hair: '#5a3a22', hairStyle: 'buns', wide: 0.95, legW: 32, outfit: 'jacket' },
  c4:     { skin: SKIN.d, body: '#4D96FF', pants: '#1f2937', shoe: '#fff', hair: '#2b1d14', hairStyle: 'side', wide: 1, legW: 36, outfit: 'hoodie' },
};

// pose: {x,y,s,dir,walk,run,armL,armR,hold,holdL,face,look,lean,bob,squash,blink,t}
function person(ctx, kind, p) {
  const P = PEOPLE[kind];
  const s = p.s || 1, dir = p.dir || 1;
  const ph = p.walk || 0;
  const runAmt = p.run || 0; // 0 walk-ish, 1 run
  const moving = p.moving === undefined ? (p.walk !== undefined && p.walk !== 0) : p.moving;
  const legSw = moving ? Math.sin(ph) * lerp(0.42, 0.75, runAmt) : 0;
  const armSw = moving ? Math.sin(ph) * lerp(0.35, 0.9, runAmt) : 0;
  const bob = (moving ? -Math.abs(Math.cos(ph)) * lerp(8, 22, runAmt) : 0) + (p.bob || 0);
  const wd = P.wide;
  ctx.save();
  ctx.translate(p.x, p.y);
  // ground shadow
  ctx.fillStyle = 'rgba(11,21,18,0.13)';
  ctx.beginPath(); ctx.ellipse(0, 0, 105 * wd * s, 15 * s, 0, 0, Math.PI * 2); ctx.fill();
  ctx.scale(s * dir, s * (p.squash || 1));
  ctx.rotate((p.lean || 0) + runAmt * 0.12 * (moving ? 1 : 0));
  ctx.translate(0, bob);
  const lw = P.legW;
  // legs (back leg first)
  const leg = (sx, a) => {
    ctx.save(); ctx.translate(sx, -135); ctx.rotate(a);
    fillRR(ctx, -lw / 2, -10, lw, 135, lw / 2.6, P.pants);
    // shoe
    fillRR(ctx, -lw / 2 - 6, 112, lw + 22, 22, 11, P.shoe, P.shoe === '#fff' ? C.ink : null, 3);
    ctx.restore();
  };
  leg(-24 * wd, -legSw); leg(24 * wd, legSw);
  // back arm
  const shoulderX = 98 * wd, shoulderY = -385;
  const armLen = 165, armW = P.outfit === 'suit' ? 50 : 38;
  const armColor = P.outfit === 'apron' ? '#FFFFFF' : P.body;
  const armL = p.armL !== undefined ? p.armL : armSw * 0.6 + 0.08;
  const armR = p.armR !== undefined ? p.armR : -armSw * 0.6 - 0.08;
  const drawArm = (sx, a, hold) => {
    ctx.save(); ctx.translate(sx, shoulderY); ctx.rotate(-a);
    fillRR(ctx, -armW / 2, -12, armW, armLen + 12, armW / 2, armColor, P.outfit === 'apron' ? '#DDE5E1' : null, 3);
    circle(ctx, 0, armLen + 6, armW * 0.5, P.skin);
    if (hold) { ctx.translate(0, armLen + 10); ctx.rotate(a); drawHeld(ctx, hold, p); }
    ctx.restore();
  };
  drawArm(-shoulderX, armL, p.holdL);
  // torso
  const sw = 88 * wd, bw = 96 * wd;
  ctx.beginPath();
  ctx.moveTo(-sw, -395); ctx.quadraticCurveTo(-sw, -420, -40 * wd, -425);
  ctx.lineTo(40 * wd, -425); ctx.quadraticCurveTo(sw, -420, sw, -395);
  ctx.lineTo(bw, -118); ctx.lineTo(-bw, -118); ctx.closePath();
  ctx.fillStyle = P.body; ctx.fill();
  if (P.outfit === 'apron' || P.body === '#FFFFFF') { ctx.strokeStyle = '#DDE5E1'; ctx.lineWidth = 3; ctx.stroke(); }
  if (P.outfit === 'suit') {
    ctx.fillStyle = '#fff'; ctx.beginPath(); ctx.moveTo(-30, -425); ctx.lineTo(0, -290); ctx.lineTo(30, -425); ctx.fill();
    ctx.fillStyle = C.green; ctx.beginPath(); ctx.moveTo(-11, -418); ctx.lineTo(11, -418); ctx.lineTo(16, -392); ctx.lineTo(0, -215); ctx.lineTo(-16, -392); ctx.fill();
    ctx.fillStyle = P.body2; ctx.beginPath(); ctx.moveTo(-sw, -395); ctx.lineTo(-58, -425); ctx.lineTo(-30, -425); ctx.lineTo(0, -290); ctx.lineTo(-40, -118); ctx.lineTo(-bw, -118); ctx.fill();
    circle(ctx, 22, -250, 5, '#0f2440'); circle(ctx, 22, -200, 5, '#0f2440');
  } else if (P.outfit === 'apron') {
    ctx.fillStyle = C.green; ctx.beginPath(); ctx.moveTo(-58, -350); ctx.lineTo(58, -350); ctx.lineTo(68, -118); ctx.lineTo(-68, -118); ctx.fill();
    circle(ctx, 0, -270, 20, 'rgba(255,255,255,0.9)'); circle(ctx, 0, -270, 11, C.green); ctx.fillStyle = 'rgba(255,255,255,0.9)'; ctx.fillRect(4, -264, 12, 5);
  } else if (P.outfit === 'hoodie') {
    ctx.strokeStyle = 'rgba(0,0,0,0.18)'; ctx.lineWidth = 4; ctx.beginPath(); ctx.moveTo(-14, -420); ctx.lineTo(-14, -360); ctx.moveTo(14, -420); ctx.lineTo(14, -360); ctx.stroke();
    fillRR(ctx, -50, -220, 100, 50, 12, 'rgba(0,0,0,0.12)');
  } else if (P.outfit === 'jacket') {
    ctx.strokeStyle = 'rgba(0,0,0,0.15)'; ctx.lineWidth = 4; ctx.beginPath(); ctx.moveTo(0, -420); ctx.lineTo(0, -118); ctx.stroke();
  } else if (P.outfit === 'sweater') {
    ctx.strokeStyle = 'rgba(0,0,0,0.12)'; ctx.lineWidth = 6; ctx.beginPath(); ctx.moveTo(-bw + 4, -140); ctx.lineTo(bw - 4, -140); ctx.stroke();
  }
  // neck + head
  ctx.fillStyle = P.skin; ctx.fillRect(-16 * Math.min(wd, 1.2), -470, 32 * Math.min(wd, 1.2), 52);
  const hx = (p.headTilt || 0);
  ctx.save(); ctx.translate(0, -525); ctx.rotate(hx);
  const hr = kind === 'owner' ? 80 : 68;
  head(ctx, kind, P, hr, p);
  ctx.restore();
  // front arm
  drawArm(shoulderX, armR, p.hold);
  ctx.restore();
}

function head(ctx, kind, P, r, p) {
  const st = P.hairStyle;
  // back hair
  if (st === 'long') { ctx.fillStyle = P.hair; rr(ctx, -r - 8, -r * 0.6, 2 * r + 16, r * 1.9, 30); ctx.fill(); }
  if (st === 'buns') { circle(ctx, -r * 1.02, -r * 1.05, r * 0.38, P.hair); circle(ctx, r * 1.02, -r * 1.05, r * 0.38, P.hair); }
  ctx.fillStyle = P.skin; ctx.beginPath(); ctx.ellipse(0, 0, r, r * (kind === 'owner' ? 1.05 : 1), 0, 0, Math.PI * 2); ctx.fill();
  // ears
  circle(ctx, -r + 2, 6, 12, P.skin); circle(ctx, r - 2, 6, 12, P.skin);
  // hair top
  ctx.fillStyle = P.hair; ctx.beginPath();
  if (st === 'owner') {
    ctx.moveTo(-r, -2); ctx.quadraticCurveTo(-r - 4, -r * 1.12, 0, -r * 1.12); ctx.quadraticCurveTo(r + 4, -r * 1.12, r, -2);
    ctx.quadraticCurveTo(r * 0.85, -r * 0.62, 0, -r * 0.7); ctx.quadraticCurveTo(-r * 0.85, -r * 0.62, -r, -2); ctx.fill();
    ctx.fillStyle = '#9aa0a6'; rr(ctx, -r - 3, -r * 0.55, 14, r * 0.5, 6); ctx.fill(); rr(ctx, r - 11, -r * 0.55, 14, r * 0.5, 6); ctx.fill();
    // stubble beard
    ctx.fillStyle = 'rgba(58,58,61,0.45)'; ctx.beginPath(); ctx.moveTo(-r * 0.86, r * 0.35); ctx.quadraticCurveTo(-r * 0.7, r * 1.05, 0, r * 1.08); ctx.quadraticCurveTo(r * 0.7, r * 1.05, r * 0.86, r * 0.35); ctx.quadraticCurveTo(r * 0.6, r * 0.85, 0, r * 0.85); ctx.quadraticCurveTo(-r * 0.6, r * 0.85, -r * 0.86, r * 0.35); ctx.fill();
  } else if (st === 'short') {
    ctx.moveTo(-r, -8); ctx.quadraticCurveTo(-r + 4, -r * 1.05, 0, -r * 1.05); ctx.quadraticCurveTo(r - 4, -r * 1.05, r, -8);
    ctx.quadraticCurveTo(r * 0.6, -r * 0.62, 0, -r * 0.6); ctx.quadraticCurveTo(-r * 0.6, -r * 0.62, -r, -8); ctx.fill();
  } else if (st === 'side') {
    ctx.moveTo(-r, -14); ctx.quadraticCurveTo(-r + 6, -r * 1.2, 0, -r * 1.2); ctx.quadraticCurveTo(r - 6, -r * 1.2, r, -14);
    ctx.quadraticCurveTo(r * 0.3, -r * 0.9, -r, -14); ctx.fill();
  } else if (st === 'cap') {
    ctx.moveTo(-r, -14); ctx.quadraticCurveTo(-r, -r * 1.1, 0, -r * 1.1); ctx.quadraticCurveTo(r, -r * 1.1, r, -14); ctx.closePath();
    ctx.fillStyle = P.cap; ctx.fill(); fillRR(ctx, 0, -30, r + 38, 18, 9, P.cap);
  } else { // buns / long
    ctx.moveTo(-r - 4, 10); ctx.quadraticCurveTo(-r - 6, -r * 1.12, 0, -r * 1.12); ctx.quadraticCurveTo(r + 6, -r * 1.12, r + 4, 10);
    ctx.quadraticCurveTo(r * 0.85, -r * 0.6, 0, -r * 0.62); ctx.quadraticCurveTo(-r * 0.85, -r * 0.6, -r - 4, 10); ctx.fill();
  }
  // face
  const f = p.face || 'smile';
  const lk = (p.look || 0) * 6;
  const blink = p.blink ? 0.15 : 1;
  const ey = kind === 'owner' ? -6 : 2;
  const ex = kind === 'owner' ? 28 : 24;
  ctx.fillStyle = C.ink;
  if (f === 'shock') { circle(ctx, -ex + lk, ey, 10, '#fff', C.ink, 3); circle(ctx, ex + lk, ey, 10, '#fff', C.ink, 3); circle(ctx, -ex + lk, ey, 5, C.ink); circle(ctx, ex + lk, ey, 5, C.ink); }
  else { ctx.beginPath(); ctx.ellipse(-ex + lk, ey, 7, 7 * blink, 0, 0, 7); ctx.ellipse(ex + lk, ey, 7, 7 * blink, 0, 0, 7); ctx.fill(); }
  // brows
  ctx.strokeStyle = kind === 'owner' ? '#2b2b2e' : 'rgba(11,21,18,0.75)'; ctx.lineWidth = kind === 'owner' ? 7 : 5; ctx.lineCap = 'round';
  ctx.beginPath();
  if (f === 'angry' || f === 'sly' || kind === 'owner' && f !== 'happy' && f !== 'shock') { ctx.moveTo(-ex - 14, ey - 24); ctx.lineTo(-ex + 12, ey - 17); ctx.moveTo(ex + 14, ey - 24); ctx.lineTo(ex - 12, ey - 17); }
  else if (f === 'worried' || f === 'shock') { ctx.moveTo(-ex - 12, ey - 18); ctx.lineTo(-ex + 10, ey - 26); ctx.moveTo(ex + 12, ey - 18); ctx.lineTo(ex - 10, ey - 26); }
  else { ctx.moveTo(-ex - 12, ey - 22); ctx.quadraticCurveTo(-ex, ey - 28, -ex + 12, ey - 22); ctx.moveTo(ex - 12, ey - 22); ctx.quadraticCurveTo(ex, ey - 28, ex + 12, ey - 22); }
  ctx.stroke();
  // mustache
  const my = kind === 'owner' ? 34 : 30;
  if (kind === 'owner') { ctx.fillStyle = '#2b2b2e'; ctx.beginPath(); ctx.moveTo(-36, my); ctx.quadraticCurveTo(0, my - 16, 36, my); ctx.quadraticCurveTo(22, my + 10, 0, my + 6); ctx.quadraticCurveTo(-22, my + 10, -36, my); ctx.fill(); }
  const mY = kind === 'owner' ? my + 20 : 30;
  ctx.strokeStyle = kind === 'owner' ? '#8a4b3a' : C.ink; ctx.lineWidth = 5; ctx.beginPath();
  if (f === 'smile') { ctx.moveTo(-18, mY); ctx.quadraticCurveTo(0, mY + 16, 18, mY); ctx.stroke(); }
  else if (f === 'happy') { ctx.fillStyle = '#B03A3A'; ctx.beginPath(); ctx.moveTo(-22, mY - 2); ctx.quadraticCurveTo(0, mY + 28, 22, mY - 2); ctx.closePath(); ctx.fill(); }
  else if (f === 'worried' || f === 'angry') { ctx.moveTo(-18, mY + 8); ctx.quadraticCurveTo(0, mY - 6, 18, mY + 8); ctx.stroke(); }
  else if (f === 'sly') { ctx.moveTo(-18, mY + 4); ctx.quadraticCurveTo(6, mY + 2, 22, mY - 8); ctx.stroke(); }
  else if (f === 'shock') { circle(ctx, 0, mY + 6, 10, '#7a2a2a'); }
  else { ctx.moveTo(-14, mY + 4); ctx.lineTo(14, mY + 4); ctx.stroke(); }
  if (f === 'happy' || f === 'smile') { ctx.fillStyle = 'rgba(242,59,79,0.18)'; circle(ctx, -ex - 14, ey + 26, 12, 'rgba(242,59,79,0.16)'); circle(ctx, ex + 14, ey + 26, 12, 'rgba(242,59,79,0.16)'); }
  if (p.sweat) { ctx.fillStyle = '#8fd3ff'; ctx.beginPath(); ctx.moveTo(r * 0.75, -r * 0.3); ctx.quadraticCurveTo(r * 0.95, -r * 0.02, r * 0.75, r * 0.05); ctx.quadraticCurveTo(r * 0.55, -r * 0.02, r * 0.75, -r * 0.3); ctx.fill(); }
}

function drawHeld(ctx, hold, p) {
  if (typeof hold === 'function') { hold(ctx); return; }
  switch (hold) {
    case 'phone': ctx.save(); ctx.rotate(-0.15); fillRR(ctx, -22, -70, 46, 80, 9, C.ink); fillRR(ctx, -17, -64, 36, 66, 6, p.phoneColor || C.green); ctx.restore(); break;
    case 'box': fillRR(ctx, -70, -60, 140, 85, 8, C.amber); ctx.fillStyle = '#c7810f'; ctx.fillRect(-70, -60, 140, 18); text(ctx, p.boxLabel || '42', 0, -5, font(800, 30), '#6b4508'); break;
    case 'wrongbox': fillRR(ctx, -70, -60, 140, 85, 8, '#b8c0c8'); ctx.fillStyle = '#8f99a3'; ctx.fillRect(-70, -60, 140, 18); text(ctx, p.boxLabel || '39', 0, -5, font(800, 30), '#4a5560'); break;
    case 'notebook': ctx.save(); ctx.rotate(-0.1); fillRR(ctx, -40, -60, 80, 100, 6, '#fff', '#999', 3); ctx.strokeStyle = '#bbb'; ctx.lineWidth = 3; for (let i = 0; i < 4; i++) { ctx.beginPath(); ctx.moveTo(-28, -38 + i * 20); ctx.lineTo(28, -38 + i * 20); ctx.stroke(); } ctx.restore(); break;
    case 'money': ctx.save(); ctx.rotate(0.15); fillRR(ctx, -40, -24, 80, 46, 6, C.green, C.greenDeep, 3); text(ctx, '₸', 0, 0, font(800, 26), '#fff'); ctx.restore(); break;
    case 'bag': ctx.save(); ctx.strokeStyle = C.greenDeep; ctx.lineWidth = 6; ctx.beginPath(); ctx.arc(0, 0, 22, Math.PI, 0); ctx.stroke(); fillRR(ctx, -48, 0, 96, 100, 10, C.green); circle(ctx, 0, 50, 16, '#fff'); circle(ctx, 0, 50, 9, C.green); ctx.restore(); break;
    case 'cup': fillRR(ctx, -22, -50, 44, 56, 8, '#fff', '#c9c9c9', 3); ctx.strokeStyle = '#c9c9c9'; ctx.lineWidth = 5; ctx.beginPath(); ctx.arc(24, -24, 12, -1.2, 1.2); ctx.stroke(); break;
  }
}

// ── environment props ─────────────────────────────────────────────────────
const SHIRT_COLORS = ['#00A862', '#FFA51F', '#2F7DF6', '#F23B4F', '#7C5CFC', '#0B1512', '#2EC4B6', '#FF7B54', '#ffffff'];
function rack(ctx, x, y, w, seed = 1, swing = 0) {
  const R = rng(seed);
  ctx.strokeStyle = '#7b8a85'; ctx.lineWidth = 10; ctx.lineCap = 'round';
  ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x + w, y); ctx.stroke();
  ctx.lineWidth = 8; ctx.beginPath(); ctx.moveTo(x + 10, y); ctx.lineTo(x + 10, y + 520); ctx.moveTo(x + w - 10, y); ctx.lineTo(x + w - 10, y + 520); ctx.stroke();
  const n = Math.floor(w / 62);
  for (let i = 0; i < n; i++) {
    const cx = x + 40 + i * (w - 80) / Math.max(1, n - 1);
    const col = SHIRT_COLORS[Math.floor(R() * SHIRT_COLORS.length)];
    const a = Math.sin(swing + i * 0.7) * 0.05;
    ctx.save(); ctx.translate(cx, y); ctx.rotate(a);
    ctx.strokeStyle = '#555'; ctx.lineWidth = 4; ctx.beginPath(); ctx.arc(0, 8, 9, Math.PI, Math.PI * 2.2); ctx.stroke();
    ctx.fillStyle = col; ctx.beginPath(); ctx.moveTo(-40, 26); ctx.lineTo(-60, 70); ctx.lineTo(-44, 80); ctx.lineTo(-38, 64); ctx.lineTo(-38, 210); ctx.lineTo(38, 210); ctx.lineTo(38, 64); ctx.lineTo(44, 80); ctx.lineTo(60, 70); ctx.lineTo(40, 26); ctx.lineTo(14, 18); ctx.quadraticCurveTo(0, 30, -14, 18); ctx.closePath(); ctx.fill();
    if (col === '#ffffff') { ctx.strokeStyle = '#d9dfdc'; ctx.lineWidth = 3; ctx.stroke(); }
    ctx.restore();
  }
}
function shoeShelf(ctx, x, y, w, rows = 3, seed = 3) {
  const R = rng(seed);
  for (let r = 0; r < rows; r++) {
    const yy = y + r * 130;
    fillRR(ctx, x, yy + 70, w, 16, 4, C.wood);
    for (let i = 0; i < Math.floor(w / 120); i++) {
      const sx = x + 30 + i * 120, col = SHIRT_COLORS[Math.floor(R() * 8)];
      sneaker(ctx, sx, yy + 70, 0.9, col);
    }
  }
}
function sneaker(ctx, x, y, s, col) {
  ctx.save(); ctx.translate(x, y); ctx.scale(s, s);
  ctx.fillStyle = col; ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(0, -40); ctx.quadraticCurveTo(8, -52, 26, -46); ctx.lineTo(50, -30); ctx.quadraticCurveTo(84, -24, 90, -8); ctx.lineTo(90, 0); ctx.closePath(); ctx.fill();
  ctx.fillStyle = '#fff'; ctx.fillRect(-2, -8, 94, 8);
  ctx.restore();
}
function whShelf(ctx, x, y, w, h, labels, seed = 5, opt = {}) {
  // metal warehouse shelf with boxes; labels: list of size strings
  const R = rng(seed);
  const rows = opt.rows || 4, rowH = h / rows;
  ctx.fillStyle = '#5c6670';
  ctx.fillRect(x, y, 14, h); ctx.fillRect(x + w - 14, y, 14, h);
  let k = 0;
  for (let r = 0; r < rows; r++) {
    const yy = y + (r + 1) * rowH;
    ctx.fillStyle = '#7d8893'; ctx.fillRect(x, yy - 12, w, 12);
    let bx = x + 22;
    while (bx < x + w - 110) {
      const bw = 90 + Math.floor(R() * 40), bh = rowH * (0.5 + R() * 0.25);
      const hi = opt.highlight && opt.highlight === k;
      const col = hi ? C.green : ['#E0A458', '#D99A4E', '#C98F4A', '#E6B36C'][Math.floor(R() * 4)];
      fillRR(ctx, bx, yy - 12 - bh, bw, bh, 5, col);
      ctx.fillStyle = 'rgba(0,0,0,0.12)'; ctx.fillRect(bx, yy - 12 - bh, bw, 10);
      if (labels) { fillRR(ctx, bx + bw / 2 - 26, yy - 12 - bh / 2 - 15, 52, 30, 5, '#fff'); text(ctx, labels[k % labels.length], bx + bw / 2, yy - 12 - bh / 2, font(800, 20), C.ink); }
      if (hi) { ctx.strokeStyle = C.greenBright; ctx.lineWidth = 6; rr(ctx, bx - 6, yy - 18 - bh, bw + 12, bh + 12, 9); ctx.stroke(); }
      bx += bw + 12; k++;
    }
  }
}
function door(ctx, x, y, w, h, open = 0, label) {
  fillRR(ctx, x - 14, y - 14, w + 28, h + 14, 8, '#6b5541');
  ctx.fillStyle = '#2a2420'; ctx.fillRect(x, y, w, h);
  ctx.save(); ctx.translate(x, y); ctx.scale(1 - open * 0.75, 1);
  fillRR(ctx, 0, 0, w, h, 4, '#8f6d4f'); fillRR(ctx, 18, 22, w - 36, h * 0.38, 6, '#a07c5c'); fillRR(ctx, 18, h * 0.5, w - 36, h * 0.42, 6, '#a07c5c');
  circle(ctx, w - 26, h * 0.5, 9, '#e6c26b');
  ctx.restore();
  if (label) { fillRR(ctx, x + w / 2 - 110, y - 90, 220, 58, 12, C.ink); text(ctx, label, x + w / 2, y - 61, font(800, 30), '#fff'); }
}
function counter(ctx, x, y, w, h = 230) {
  fillRR(ctx, x, y, w, h, 14, '#F7F2EA', '#d8cbb5', 4);
  fillRR(ctx, x - 16, y - 18, w + 32, 30, 10, C.wood);
  ctx.fillStyle = C.green; ctx.fillRect(x + 20, y + 40, w - 40, 10);
}
function box3(ctx, x, y, w, h, label, col = '#E0A458') {
  fillRR(ctx, x - w / 2, y - h, w, h, 6, col); ctx.fillStyle = 'rgba(0,0,0,0.13)'; ctx.fillRect(x - w / 2, y - h, w, h * 0.18);
  if (label) { fillRR(ctx, x - 28, y - h * 0.55 - 16, 56, 32, 5, '#fff'); text(ctx, label, x, y - h * 0.55, font(800, 22), C.ink); }
}
function notebook(ctx, x, y, w, h, opt = {}) {
  ctx.save(); ctx.translate(x, y); ctx.rotate(opt.rot || 0);
  shadowOn(ctx, 24, 10, 0.2);
  fillRR(ctx, -w / 2, -h / 2, w, h, 10, '#fffdf6', '#c9bfa8', 3); shadowOff(ctx);
  ctx.strokeStyle = '#d6e4f0'; ctx.lineWidth = 3;
  for (let yy = -h / 2 + 70; yy < h / 2 - 20; yy += 46) { ctx.beginPath(); ctx.moveTo(-w / 2 + 20, yy); ctx.lineTo(w / 2 - 20, yy); ctx.stroke(); }
  ctx.strokeStyle = '#f2a0a0'; ctx.beginPath(); ctx.moveTo(-w / 2 + 70, -h / 2 + 10); ctx.lineTo(-w / 2 + 70, h / 2 - 10); ctx.stroke();
  // rings
  for (let i = 0; i < 6; i++) circle(ctx, -w / 2 + 8, -h / 2 + 40 + i * (h - 80) / 5, 10, '#fff', '#888', 4);
  (opt.lines || []).forEach((s, i) => { const vis = opt.reveal === undefined ? 1 : clamp(opt.reveal * opt.lines.length - i); if (vis > 0) { ctx.save(); ctx.globalAlpha *= vis; text(ctx, s, -w / 2 + 86, -h / 2 + 52 + i * 46, `italic 600 30px ${FONT}`, '#2e4a8a', 'left', 'middle'); ctx.restore(); } });
  if (opt.title) text(ctx, opt.title, 0, -h / 2 + 30, font(800, 28), '#555');
  ctx.restore();
}
function bill(ctx, x, y, rot = 0, s = 1) {
  ctx.save(); ctx.translate(x, y); ctx.rotate(rot); ctx.scale(s, s);
  fillRR(ctx, -60, -32, 120, 64, 8, '#4caf7a', '#2e7d4f', 3); circle(ctx, 0, 0, 18, '#2e7d4f'); text(ctx, '₸', 0, 1, font(800, 26), '#fff');
  ctx.restore();
}
function qr(ctx, x, y, size, seed = 9, col = C.ink) {
  const R = rng(seed); const n = 21, c = size / n;
  fillRR(ctx, x - 14, y - 14, size + 28, size + 28, 12, '#fff');
  ctx.fillStyle = col;
  for (let i = 0; i < n; i++) for (let j = 0; j < n; j++) {
    const finder = (i < 7 && j < 7) || (i > 13 && j < 7) || (i < 7 && j > 13);
    if (finder) continue;
    if (R() > 0.52) ctx.fillRect(x + i * c, y + j * c, c + 0.5, c + 0.5);
  }
  const fp = (fx, fy) => { ctx.fillStyle = col; ctx.fillRect(x + fx * c, y + fy * c, 7 * c, 7 * c); ctx.fillStyle = '#fff'; ctx.fillRect(x + (fx + 1) * c, y + (fy + 1) * c, 5 * c, 5 * c); ctx.fillStyle = col; ctx.fillRect(x + (fx + 2) * c, y + (fy + 2) * c, 3 * c, 3 * c); };
  fp(0, 0); fp(14, 0); fp(0, 14);
}
function star(ctx, x, y, r, fill, stroke) {
  ctx.beginPath();
  for (let i = 0; i < 10; i++) { const a = -Math.PI / 2 + i * Math.PI / 5, rad = i % 2 ? r * 0.45 : r; ctx.lineTo(x + Math.cos(a) * rad, y + Math.sin(a) * rad); }
  ctx.closePath(); if (fill) { ctx.fillStyle = fill; ctx.fill(); } if (stroke) { ctx.strokeStyle = stroke; ctx.lineWidth = 3; ctx.stroke(); }
}
function check(ctx, x, y, r, p = 1, col = C.green) {
  circle(ctx, x, y, r, col);
  ctx.strokeStyle = '#fff'; ctx.lineWidth = r * 0.22; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
  const pts = [[x - r * 0.42, y + r * 0.02], [x - r * 0.1, y + r * 0.32], [x + r * 0.45, y - r * 0.3]];
  ctx.beginPath(); ctx.moveTo(...pts[0]);
  const a = clamp(p * 2), b = clamp(p * 2 - 1);
  ctx.lineTo(lerp(pts[0][0], pts[1][0], a), lerp(pts[0][1], pts[1][1], a));
  if (b > 0) ctx.lineTo(lerp(pts[1][0], pts[2][0], b), lerp(pts[1][1], pts[2][1], b));
  ctx.stroke();
}
function cross(ctx, x, y, r, p = 1) {
  circle(ctx, x, y, r, C.red);
  ctx.strokeStyle = '#fff'; ctx.lineWidth = r * 0.22; ctx.lineCap = 'round';
  const d = r * 0.38, a = clamp(p * 2), b = clamp(p * 2 - 1);
  ctx.beginPath(); ctx.moveTo(x - d, y - d); ctx.lineTo(x - d + 2 * d * a, y - d + 2 * d * a); ctx.stroke();
  if (b > 0) { ctx.beginPath(); ctx.moveTo(x + d, y - d); ctx.lineTo(x + d - 2 * d * b, y - d + 2 * d * b); ctx.stroke(); }
}
function bubble(ctx, x, y, s, opt = {}) {
  s = L(s);
  const f = font(opt.w || 800, opt.size || 40);
  ctx.font = f; const tw = ctx.measureText(s).width;
  const pw = tw + (opt.pad || 34) * 2, ph = (opt.size || 40) * 1.9;
  const sc = opt.scale === undefined ? 1 : opt.scale;
  ctx.save(); ctx.translate(x, y); ctx.scale(sc, sc);
  shadowOn(ctx, 24, 8, 0.16);
  fillRR(ctx, -pw / 2, -ph, pw, ph, ph / 2.2, opt.bg || '#fff');
  ctx.beginPath(); ctx.moveTo((opt.tail || 0) - 16, -4); ctx.lineTo((opt.tail || 0) + 4, 26); ctx.lineTo((opt.tail || 0) + 20, -4); ctx.fillStyle = opt.bg || '#fff'; ctx.fill();
  shadowOff(ctx);
  text(ctx, s, 0, -ph / 2, f, opt.color || C.ink);
  ctx.restore();
}
function timer(ctx, x, y, r, frac, label, col = C.red) {
  circle(ctx, x, y, r, '#fff'); ctx.strokeStyle = col; ctx.lineWidth = r * 0.18;
  ctx.beginPath(); ctx.arc(x, y, r * 0.78, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * frac); ctx.stroke();
  ctx.strokeStyle = C.ink; ctx.lineWidth = 5; ctx.lineCap = 'round';
  const a = -Math.PI / 2 + Math.PI * 2 * frac * 4;
  ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x + Math.cos(a) * r * 0.55, y + Math.sin(a) * r * 0.55); ctx.stroke();
  if (label) { fillRR(ctx, x - 80, y + r + 12, 160, 50, 25, col); text(ctx, label, x, y + r + 37, font(800, 30), '#fff'); }
}

// ── phone + app UI ────────────────────────────────────────────────────────
function phone(ctx, x, y, w, rot, drawScreen, opt = {}) {
  const h = w * 2.05;
  ctx.save(); ctx.translate(x, y); ctx.rotate(rot || 0);
  if (opt.scale) ctx.scale(opt.scale, opt.scale);
  shadowOn(ctx, 60, 30, 0.3);
  fillRR(ctx, -w / 2, -h / 2, w, h, w * 0.14, C.ink);
  shadowOff(ctx);
  const bz = w * 0.04;
  ctx.save(); rr(ctx, -w / 2 + bz, -h / 2 + bz, w - 2 * bz, h - 2 * bz, w * 0.11); ctx.clip();
  ctx.fillStyle = opt.screenBg || C.bg; ctx.fillRect(-w / 2, -h / 2, w, h);
  ctx.translate(-w / 2 + bz, -h / 2 + bz);
  if (drawScreen) drawScreen(ctx, w - 2 * bz, h - 2 * bz);
  ctx.restore();
  fillRR(ctx, -w * 0.13, -h / 2 + bz + w * 0.03, w * 0.26, w * 0.06, w * 0.03, C.ink);
  ctx.restore();
}
// unit UI at nominal screen width 400 (scale inside)
function ui(ctx, sw, fn) { ctx.save(); const k = sw / 400; ctx.scale(k, k); fn(ctx, 400, 0); ctx.restore(); }
function appBar(ctx, title, col = C.green) {
  ctx.fillStyle = col; ctx.fillRect(0, 0, 400, 120);
  text(ctx, title, 24, 84, font(800, 30), '#fff', 'left');
}
function appCard(ctx, x, y, w, h) { shadowOn(ctx, 16, 4, 0.08); fillRR(ctx, x, y, w, h, 18, '#fff'); shadowOff(ctx); }
function notif(ctx, x, y, w, title, body, opt = {}) {
  const h = opt.h || 150;
  ctx.save(); ctx.translate(x, y); if (opt.scale !== undefined) ctx.scale(opt.scale, opt.scale);
  ctx.globalAlpha *= opt.alpha === undefined ? 1 : opt.alpha;
  shadowOn(ctx, 40, 16, 0.22);
  fillRR(ctx, -w / 2, -h / 2, w, h, 34, 'rgba(255,255,255,0.97)'); shadowOff(ctx);
  fillRR(ctx, -w / 2 + 26, -h / 2 + 28, 70, 70, 18, opt.iconBg || C.green);
  if (opt.logo) ctx.drawImage(opt.logo, -w / 2 + 26, -h / 2 + 28, 70, 70);
  text(ctx, title, -w / 2 + 116, -h / 2 + 46, font(800, 32), C.ink, 'left');
  text(ctx, body, -w / 2 + 116, -h / 2 + 92, font(600, 30), C.ink2, 'left');
  if (opt.time) text(ctx, opt.time, w / 2 - 26, -h / 2 + 46, font(500, 24), '#8a9590', 'right');
  ctx.restore();
}
function pill(ctx, x, y, s, opt = {}) {
  s = L(s);
  const f = font(opt.w || 800, opt.size || 34);
  ctx.font = f; const tw = ctx.measureText(s).width; const pw = tw + (opt.pad || 30) * 2, ph = (opt.size || 34) * 1.7;
  ctx.save(); ctx.translate(x, y); if (opt.scale !== undefined) ctx.scale(opt.scale, opt.scale);
  if (opt.shadow !== false) shadowOn(ctx, 20, 8, 0.15);
  fillRR(ctx, -pw / 2, -ph / 2, pw, ph, ph / 2, opt.bg || C.green); shadowOff(ctx);
  text(ctx, s, 0, 2, f, opt.color || '#fff');
  ctx.restore();
  return pw;
}

// ── kinetic type ──────────────────────────────────────────────────────────
// headline: lines of words; words wrapped in * are highlighted. t0 start, t1 exit
function headline(ctx, t, t0, t1, lines, opt = {}) {
  if (t < t0 - 0.01 || t > t1 + 0.6) return;
  lines = lines.map(L);
  let size = opt.size || 92;
  { // auto-fit widest line into maxW
    ctx.font = font(opt.weight || 900, size);
    const maxW = opt.maxW || 940;
    const widest = Math.max(...lines.map(ln => { const ws = ln.split(' '); return ws.reduce((a, w) => a + ctx.measureText(w.replace(/\*/g, '')).width + (w.startsWith('*') ? size * 0.36 : 0), 0) + size * 0.28 * (ws.length - 1); }));
    if (widest > maxW) size = size * maxW / widest;
  }
  const lh = size * 1.12, y0 = opt.y || 330, cx = opt.x || W / 2;
  const col = opt.color || C.ink, hcol = opt.hcolor || C.green, htext = opt.htext || '#fff';
  let wi = 0;
  const exitP = E.inC(seg(t, t1, t1 + 0.45));
  lines.forEach((ln, li) => {
    const words = ln.split(' ');
    ctx.font = font(opt.weight || 900, size);
    const ws = words.map(w => ctx.measureText(w.replace(/\*/g, '')).width);
    const gap = size * 0.28;
    let _o = false; const hls = words.map(w => { if (w.startsWith('*')) _o = true; const h = _o; if (w.endsWith('*') && w.length > 1) _o = false; return h; });
    const total = ws.reduce((a, b) => a + b, 0) + gap * (words.length - 1) + hls.filter(Boolean).length * size * 0.36;
    let x = cx - total / 2;
    words.forEach((w, i) => {
      const hl = hls[i];
      const word = w.replace(/\*/g, '');
      const pad = hl ? size * 0.18 : 0;
      const d = t - (t0 + wi * (opt.stagger || 0.075));
      const sp = spring(d, 1.6, 6.5);
      const a = clamp(d * 6);
      const yy = y0 + li * lh + (1 - sp) * size * 0.9 - exitP * size * 1.2;
      const rot = (1 - sp) * (opt.rot === undefined ? 0.18 : opt.rot) * (i % 2 ? -1 : 1);
      ctx.save();
      ctx.globalAlpha *= a * (1 - exitP);
      ctx.translate(x + pad + ws[i] / 2, yy); ctx.rotate(rot); ctx.scale(lerp(0.6, 1, clamp(sp)), lerp(0.6, 1, clamp(sp)));
      if (hl) {
        const hp = E.outC(seg(d, 0.12, 0.5));
        ctx.save(); ctx.rotate(-0.025);
        fillRR(ctx, -ws[i] / 2 - pad, -size * 0.62, (ws[i] + pad * 2) * hp, size * 1.2, size * 0.22, hcol);
        ctx.restore();
      }
      if (opt.outline) { ctx.lineWidth = 14; ctx.strokeStyle = opt.outline; ctx.lineJoin = 'round'; ctx.font = font(opt.weight || 900, size); ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.strokeText(word, 0, 4); }
      text(ctx, word, 0, 4, font(opt.weight || 900, size), hl ? htext : col);
      ctx.restore();
      x += ws[i] + gap + pad * 2;
      wi++;
    });
  });
}
// subtitles (caption) synced to VO chunks [{t0,t1,s}]
function captions(ctx, t, chunks, opt = {}) {
  const y = opt.y || 1470;
  for (const c of chunks) {
    if (t < c.t0 || t > c.t1) continue;
    const a = E.outC(seg(t, c.t0, c.t0 + 0.14)) * (1 - seg(t, c.t1 - 0.1, c.t1));
    const sc = lerp(0.92, 1, E.outBack(seg(t, c.t0, c.t0 + 0.22)));
    ctx.save(); ctx.globalAlpha *= a;
    const f = font(800, 46);
    ctx.font = f;
    const lines = wrap(ctx, c.s, 820);
    const lh = 60, bw = Math.max(...lines.map(l => ctx.measureText(l).width)) + 56, bh = lines.length * lh + 30;
    ctx.translate(W / 2 - 40, y); ctx.scale(sc, sc);
    fillRR(ctx, -bw / 2, -bh / 2, bw, bh, 22, 'rgba(11,21,18,0.82)');
    lines.forEach((l, i) => text(ctx, l, 0, -bh / 2 + 15 + lh / 2 + i * lh + 2, f, '#fff'));
    ctx.restore();
  }
}
function wrap(ctx, s, maxW) {
  const words = s.split(' '); const out = []; let cur = '';
  for (const w of words) { const t = cur ? cur + ' ' + w : w; if (ctx.measureText(t).width > maxW && cur) { out.push(cur); cur = w; } else cur = t; }
  if (cur) out.push(cur); return out;
}
// split VO into caption chunks by punctuation, timed by char length
function chunkVO(s, t0, dur) {
  const parts = s.replace(/\s+—\s+/g, ' — ').split(/(?<=[,.!?:])\s+/).filter(Boolean);
  // merge very short parts
  const merged = [];
  parts.forEach(p => { if (merged.length && (p.length < 14 || merged[merged.length - 1].length < 12)) merged[merged.length - 1] += ' ' + p; else merged.push(p); });
  const total = merged.reduce((a, p) => a + p.length + 6, 0);
  let tt = t0 + 0.05; const out = [];
  merged.forEach(p => { const d = dur * (p.length + 6) / total; out.push({ t0: tt, t1: tt + d, s: p }); tt += d; });
  return out;
}

// ── particles / fx ────────────────────────────────────────────────────────
function burst(ctx, x, y, t, n = 14, col = C.green, seed = 1, spread = 220) {
  if (t < 0 || t > 1.2) return;
  const R = rng(seed);
  for (let i = 0; i < n; i++) {
    const a = R() * Math.PI * 2, sp = (0.5 + R() * 0.8) * spread;
    const p = E.outC(clamp(t / 0.9));
    const px = x + Math.cos(a) * sp * p, py = y + Math.sin(a) * sp * p + t * t * 120;
    ctx.save(); ctx.globalAlpha *= 1 - clamp(t / 1.1);
    if (i % 3 === 0) star(ctx, px, py, 12, col); else circle(ctx, px, py, 7 + R() * 6, i % 2 ? col : C.amber);
    ctx.restore();
  }
}
function vignette(ctx, a = 0.35) {
  const g = ctx.createRadialGradient(W / 2, H / 2, H * 0.25, W / 2, H / 2, H * 0.75);
  g.addColorStop(0, 'rgba(0,0,0,0)'); g.addColorStop(1, `rgba(0,0,0,${a})`);
  ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
}
function grain(ctx, t, a = 0.04) {
  const R = rng(Math.floor(t * 60) + 7);
  ctx.save(); ctx.globalAlpha = a;
  for (let i = 0; i < 900; i++) { ctx.fillStyle = R() > 0.5 ? '#fff' : '#000'; ctx.fillRect(R() * W, R() * H, 2, 2); }
  ctx.restore();
}

// ── camera / layers ───────────────────────────────────────────────────────
// cam: {x,y,z,r} world point at screen centre. depth d: 1 = main plane.
function layer(ctx, cam, d, fn, blur = 0) {
  ctx.save();
  if (blur > 0.3) ctx.filter = `blur(${blur.toFixed(1)}px)`;
  ctx.translate(W / 2, H / 2);
  ctx.rotate((cam.r || 0) * d);
  const s = Math.pow(cam.z || 1, d) * (cam.zs || 1);
  ctx.scale(s, s);
  ctx.translate(-cam.x * d, -cam.y * d);
  fn(ctx);
  ctx.restore();
}
// layer rendered into offscreen buffer so filter blur applies to the group
const _buf = {};
function blurLayer(ctx, cam, d, fn, blur) {
  if (!blur || blur < 0.5) return layer(ctx, cam, d, fn, 0);
  const key = 'b';
  if (!_buf[key]) { _buf[key] = document.createElement('canvas'); _buf[key].width = W; _buf[key].height = H; }
  const b = _buf[key], bx = b.getContext('2d');
  bx.setTransform(1, 0, 0, 1, 0, 0); bx.clearRect(0, 0, W, H);
  layer(bx, cam, d, fn, 0);
  ctx.save(); ctx.filter = `blur(${blur.toFixed(1)}px)`; ctx.drawImage(b, 0, 0); ctx.restore();
}
// screen-space radial zoom blur from a group: draws buffer multiple times scaled
function radialBlurDraw(ctx, fn, amt, cx = W / 2, cy = H / 2) {
  if (!_buf.r) { _buf.r = document.createElement('canvas'); _buf.r.width = W; _buf.r.height = H; }
  const b = _buf.r, bx = b.getContext('2d');
  bx.setTransform(1, 0, 0, 1, 0, 0); bx.clearRect(0, 0, W, H); fn(bx);
  if (amt < 0.004) { ctx.drawImage(b, 0, 0); return; }
  const n = 6;
  for (let i = 0; i < n; i++) {
    const s = 1 + amt * i / (n - 1);
    ctx.save(); ctx.globalAlpha = 1 / (i + 1);
    ctx.translate(cx, cy); ctx.scale(s, s); ctx.translate(-cx, -cy); ctx.drawImage(b, 0, 0); ctx.restore();
  }
}

// ── frame renderer with shutter motion blur ───────────────────────────────
function makeRenderer(canvas, drawScene, opt = {}) {
  const ctx = canvas.getContext('2d');
  const acc = document.createElement('canvas'); acc.width = W; acc.height = H;
  const ax = acc.getContext('2d');
  const sub = opt.sub || 4, shutter = opt.shutter === undefined ? 0.5 / 60 : opt.shutter;
  return function render(t, nSub) {
    const n = nSub || sub;
    if (n <= 1) { ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.globalAlpha = 1; drawScene(ctx, t); return; }
    for (let i = 0; i < n; i++) {
      const tt = t + (i / (n - 1) - 0.5) * shutter;
      ax.setTransform(1, 0, 0, 1, 0, 0); ax.globalAlpha = 1; ax.filter = 'none';
      drawScene(ax, tt);
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.globalAlpha = 1 / (i + 1);
      ctx.drawImage(acc, 0, 0);
    }
    ctx.globalAlpha = 1;
  };
}
