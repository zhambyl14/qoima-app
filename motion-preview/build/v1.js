// ВИДЕО 1 — «Qoima қосылса, дүкенде не өзгереді?»
'use strict';
const VO1 = [ // [key, start, dur, caption]
  ['intro', 0.6, 4.66, 'Qoima қосылса, дүкеніңізде не өзгереді? Көрейік.'],
  ['run', 6.25, 5.16, 'Клиент күтіп тұр, ал сатушы керекті размерді іздеп, қоймаға жүгіреді.'],
  ['pocket', 12.25, 7.42, 'Кейбір сатушы сатқанын дәптерге жазбай, ақшаны қалтасына салады. Ревизияда тауар жетпейді.'],
  ['crowd', 20.25, 7.94, 'Сатушы көп болса, бәрі қоймаға топырлап кіреді. Клиент көбейгенде жазу ұмытылады, дәптер жоғалады.'],
  ['turn', 29.1, 1.94, 'Енді — Qoima.'],
  ['stock', 32.25, 4.78, 'Әр сатушы керекті размердің қай сөреде тұрғанын телефоннан көреді.'],
  ['push', 38.25, 4.75, 'Әр сатылым жүйеге жазылады, ал сізге сол сәтте хабарлама келеді.'],
  ['revision', 43.75, 4.92, 'Ревизия бірнеше минутта бітеді. Дәптер жоғалмайды.'],
  ['analytics', 49.3, 4.34, 'Сатушылар, қоймалар, аналитика — бәрі бір телефонда.'],
  ['end', 55.6, 2.9, 'Qoima-ны тегін қолданып көріңіз!'],
];
const CAPS1 = VO1.flatMap(([k, s, d, c]) => chunkVO(c, s, d));
const CUES1 = [];
const cue = (t, s, g = 1) => CUES1.push({ t: +t.toFixed(3), s, g });

// ── 0 · INTRO (0–6) ───────────────────────────────────────────────────────
const INTRO_WORDS = [
  { w: 'Qoima', rail: 0, x: -255 }, { w: 'қосылса', rail: 0, x: 215 },
  { w: 'дүкенде', rail: 1, x: -110 }, { w: 'не', rail: 1, x: 300 },
  { w: 'өзгереді?', rail: 2, x: 0, hl: true },
];
const RAIL_Y = [560, 880, 1200];
INTRO_WORDS.forEach((o, i) => { o.t = 1.15 + i * 0.32; cue(o.t + 0.32, 'clink', 0.7); });
cue(0.25, 'pop', 0.9); cue(0.6, 'swish', 0.6); cue(5.35, 'whoosh', 0.9);
function sIntro(ctx, u) {
  const g = ctx.createLinearGradient(0, 0, 0, H); g.addColorStop(0, '#0B1512'); g.addColorStop(1, '#0f2c22');
  ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
  const exit = E.inC(seg(u, 5.3, 6.0));
  const cam = { x: 540 + Math.sin(u * 0.5) * 30, y: 960 - exit * 120, z: 1 + u * 0.025 + exit * 0.35, r: lerp(-0.035, 0.02, E.ioQ(seg(u, 0, 6))) };
  // far bokeh hangers
  blurLayer(ctx, cam, 0.45, c => {
    for (let i = 0; i < 12; i++) {
      const R = rng(i + 3); const x = R() * 1600 - 260, y = R() * 2000 - 40;
      c.globalAlpha = 0.18; c.strokeStyle = i % 3 ? '#1f5c45' : C.green; c.lineWidth = 10;
      c.beginPath(); c.arc(x, y, 40, Math.PI, 0); c.moveTo(x - 90, y + 80); c.lineTo(x, y + 20); c.lineTo(x + 90, y + 80); c.closePath(); c.stroke();
    }
    c.globalAlpha = 1;
  }, 10);
  layer(ctx, cam, 1, c => {
    // dot -> rails
    const dot = spring(u - 0.15, 1.6, 6);
    const railP = E.outE(seg(u, 0.55, 1.2));
    if (railP <= 0) { circle(c, 540, 560, 26 * dot, C.green); }
    RAIL_Y.forEach((ry, i) => {
      const rp = E.outE(seg(u, 0.55 + i * 0.12, 1.25 + i * 0.12));
      if (rp <= 0) return;
      const fall = i === 0 ? 0 : E.inQ(seg(u, 5.2, 5.9)) * 1400;
      c.strokeStyle = i === 2 ? C.green : '#cfd8d4'; c.lineWidth = 12; c.lineCap = 'round';
      c.beginPath(); c.moveTo(540 - 460 * rp, ry + fall); c.lineTo(540 + 460 * rp, ry + fall); c.stroke();
      circle(c, 540 - 460 * rp, ry + fall, 14, c.strokeStyle); circle(c, 540 + 460 * rp, ry + fall, 14, c.strokeStyle);
    });
    INTRO_WORDS.forEach((o, i) => {
      const d = u - o.t; if (d < 0) return;
      const slide = spring(d, 1.2, 4.5);
      const x = 540 + o.x + (1 - slide) * 700;
      const swing = Math.sin(d * 7.5) * Math.exp(-d * 2.4) * 0.45;
      const drop = E.inQ(seg(u, 5.15 + i * 0.03, 5.85)) * 1500;
      c.save(); c.translate(x, RAIL_Y[o.rail] + drop); c.rotate(swing + drop * 0.0004 * (i % 2 ? 1 : -1));
      // hanger
      c.strokeStyle = '#e5ece9'; c.lineWidth = 7; c.lineCap = 'round'; c.lineJoin = 'round';
      c.beginPath(); c.arc(0, 4, 18, Math.PI * 1.05, Math.PI * 2.1); c.stroke();
      c.beginPath(); c.moveTo(0, 24); c.lineTo(-120, 92); c.lineTo(120, 92); c.closePath(); c.stroke();
      // tag
      const sz = o.hl ? 112 : 92;
      c.font = font(900, sz); const tw = c.measureText(o.w).width;
      const tagW = tw + 56, tagH = sz * 1.3;
      fillRR(c, -tagW / 2, 100, tagW, tagH, 24, o.hl ? C.green : '#fff');
      circle(c, 0, 118, 8, o.hl ? C.greenDeep : '#c9d2ce');
      text(c, o.w, 0, 100 + tagH / 2 + 6, font(900, sz), o.hl ? '#fff' : C.ink);
      c.restore();
    });
  });
  // foreground passing shirts (depth)
  blurLayer(ctx, cam, 1.5, c => {
    const x = lerp(1500, -700, seg(u, 2.2, 4.8));
    c.save(); c.translate(x, 1880); c.scale(2.0, 2.0); rack(c, 0, 0, 420, 7, u * 2); c.restore();
  }, 22);
  vignette(ctx, 0.45);
}

// ── 1 · RUN (6–12) ────────────────────────────────────────────────────────
// seller x(u) piecewise
function runSellerX(u) {
  return kf(u, [[0, 640], [0.8, 640], [2.1, 1960, E.ioQ], [3.2, 1960], [4.3, 700, E.ioQ], [4.7, 700], [6.2, 2100, E.inQ]]);
}
cue(6.0, 'whoosh', 0.6); cue(6.35, 'pop', 0.8); cue(6.9, 'steps', 0.8); cue(8.25, 'door', 0.7);
cue(8.45, 'thud', 0.7); cue(8.75, 'thud', 0.6); cue(9.0, 'thud', 0.7); cue(9.3, 'steps', 0.8); cue(10.45, 'buzz', 0.8); cue(10.9, 'steps', 0.8);
cue(11.8, 'whoosh', 1.0);
function sRun(ctx, u) {
  const sx = runSellerX(u);
  const vx = (runSellerX(u + 0.02) - runSellerX(u - 0.02)) / 0.04;
  const moving = Math.abs(vx) > 30;
  const camTarget = runSellerX(u - 0.18);
  const startP = E.outC(seg(u, 0, 0.6));
  let cx = lerp(560, clamp(camTarget, 520, 2100), startP);
  const exitP = E.inC(seg(u, 5.6, 6.0));
  cx += exitP * 1400;
  const cam = { x: cx, y: lerp(820, 990, startP), z: lerp(1.45, 1.0, startP) + exitP * 0.1, r: clamp(-vx * 0.000018, -0.05, 0.05) - exitP * 0.06 };
  // background wall decor (depth 0.85)
  layer(ctx, cam, 1, c => {
    storeRoom(c, -1200, 1500);
    warehouseRoom(c, 1500, 3400);
  });
  layer(ctx, cam, 0.92, c => {
    rack(c, -260, 700, 560, 11, u * 2);
    shoeShelf(c, 330, 520, 480, 3, 4);
    lamp(c, 120, 300); lamp(c, 900, 300);
    whShelf(c, 1760, 560, 520, 760, ['39', '40', '41', '43', '44', '38'], 21);
    whShelf(c, 2340, 560, 520, 760, ['36', '37', '45', '39', '40'], 22);
  });
  layer(ctx, cam, 1, c => {
    door(c, 1460, 830, 230, 520, (sx > 1380 && sx < 1760) ? 1 : 0.0, 'ҚОЙМА');
    counter(c, 120, 1120, 420);
    // flying boxes in warehouse search
    for (let i = 0; i < 4; i++) {
      const tt = u - (2.3 + i * 0.25);
      if (tt < 0 || tt > 1.2) continue;
      const bx = 1980 + (i % 2 ? -1 : 1) * (60 + tt * 320), by = 1050 - Math.sin(clamp(tt / 0.9) * Math.PI) * 300 + Math.max(0, tt - 0.9) * 0;
      c.save(); c.translate(bx, Math.min(by + tt * tt * 200, FLOOR - 10)); c.rotate(tt * 4 * (i % 2 ? -1 : 1)); box3(c, 0, 40, 110, 80, ['39', '41', '44', '38'][i]); c.restore();
    }
    // client
    const wait = seg(u, 0.5, 6);
    person(c, 'madina', { x: 330, y: FLOOR, s: 0.88, dir: 1, face: u < 4.4 ? (u > 2.5 ? 'worried' : 'neutral') : 'angry', armL: u > 3 ? -0.15 + Math.sin(u * 9) * 0.05 : -0.1, armR: 0.1, look: clamp((sx - 330) / 600, -1, 1), bob: u > 2.5 ? Math.abs(Math.sin(u * 7)) * -6 : 0, blink: (u % 2.7) < 0.1 });
    // seller (Yeraly) running
    const hold = u > 2.9 && u < 4.75 ? 'wrongbox' : null;
    person(c, 'yeraly', { x: sx, y: FLOOR, s: 0.88, dir: vx < -30 ? -1 : 1, walk: moving ? u * 15 : 0, run: 1, moving, face: u > 2.3 ? 'worried' : 'neutral', sweat: u > 2.3, hold, boxLabel: '39', armR: hold ? 1.35 : undefined, armL: hold ? -1.2 : undefined });
    if (u > 4.3 && u < 5.2) { const p = seg(u, 4.4, 4.7); cross(c, 640, 760, 54 * E.outBack(p), p); }
    // timer above client
    const mins = Math.floor(lerp(1, 7, wait)), secs = Math.floor((lerp(1, 7, wait) % 1) * 60);
    const tp = E.outBack(seg(u, 0.5, 0.9));
    if (tp > 0) { c.save(); c.translate(330, 650); c.scale(tp, tp); timer(c, 0, 0, 62, wait, `0${mins}:${String(secs).padStart(2, '0')}`); c.restore(); }
    if (u > 0.3 && u < 2.2) bubble(c, 470, 720, '42 бар ма?', { scale: E.outBack(seg(u, 0.3, 0.6)), tail: -60 });
  });
  // foreground blurred rack passing
  blurLayer(ctx, cam, 1.4, c => { rack(c, 900, 1420, 520, 19, u * 2); plant(c, 2350, 1760, 1.3); }, 14);
  headline(ctx, u, 0.35, 5.5, ['Клиент *күтеді*.', 'Сатушы *жүгіреді*.'], { hcolor: C.red });
}

// ── 2 · POCKET (12–20) ────────────────────────────────────────────────────
cue(12.0, 'whoosh', 0.5); cue(12.55, 'paper', 0.7); cue(13.9, 'swish', 0.8); cue(14.1, 'pocket', 0.8);
cue(14.9, 'focus', 0.5); cue(15.5, 'tick', 0.6); cue(16.2, 'whoosh', 0.9);
cue(16.9, 'pop', 0.7); cue(17.3, 'pop', 0.7); cue(17.85, 'stamp', 1.0);
function sPocket(ctx, u) {
  if (u < 4.2) {
    // Part A: counter close-up
    const enter = E.outC(seg(u, 0, 0.45));
    const focusP = E.ioC(seg(u, 2.6, 3.3));
    const cam = { x: lerp(-300, 540, enter) + focusP * 40, y: 900 + focusP * 260, z: 1.35 + u * 0.03 + focusP * 0.25, r: lerp(0.06, -0.01, enter) };
    blurLayer(ctx, cam, 1, c => {
      storeRoom(c, -1600, 2400);
      rack(c, -300, 620, 520, 5, u); shoeShelf(c, 760, 500, 460, 3, 9); lamp(c, 540, 260);
      // client handing money
      const give = seg(u, 0.35, 1.0);
      person(c, 'c2', { x: 170, y: FLOOR, s: 0.9, face: 'smile', armR: lerp(0.2, 1.25, E.outC(give)) - E.inC(seg(u, 1.0, 1.4)) * 1.0 });
      // seller
      const lk = u < 1.1 ? 0 : u < 1.45 ? -1 : u < 1.8 ? 1 : 0;
      const pocketP = seg(u, 1.85, 2.15);
      person(c, 'sly', { x: 640, y: FLOOR, s: 0.9, face: u > 1.05 && u < 2.6 ? 'sly' : 'smile', look: lk, armL: lerp(-1.1, -0.15, E.ioC(seg(u, 0.85, 1.1))) * (u < 0.85 ? (u > 0.6 ? 1 : 0.1) : 1) + E.ioC(pocketP) * 0.0, armR: lerp(0.15, -0.05, pocketP) });
      counter(c, 330, 1130, 620);
      // bill path
      if (u > 0.5 && u < 2.2) {
        const p1 = E.ioC(seg(u, 0.5, 1.0)), p2 = E.ioC(seg(u, 1.85, 2.15));
        const bx = lerp(lerp(330, 470, p1), 545, p2), by = lerp(lerp(860, 870, p1), 1120, p2);
        bill(c, bx, by, lerp(-0.2, 0.6, p2), lerp(1, 0.5, p2));
      }
      if (u > 2.05 && u < 2.6) { c.save(); c.globalAlpha = 1 - seg(u, 2.3, 2.6); text(c, 'шап!', 470, 1060, font(900, 40), C.redInk); c.restore(); }
    }, focusP * 12);
    // foreground notebook comes into focus
    layer(ctx, { x: 540, y: 960, z: 1, r: 0 }, 1, c => {
      const nb = E.outC(seg(u, 2.3, 3.0));
      const blurNB = (1 - focusP) * 10;
      c.save(); if (blurNB > 0.5) c.filter = `blur(${blurNB}px)`;
      notebook(c, lerp(760, 560, nb), lerp(1700, 1360, nb), 620, 440, { rot: lerp(-0.25, -0.08, nb), title: 'Сатылымдар' });
      c.restore();
      if (u > 3.0) {
        const pp = E.outBack(seg(u, 3.1, 3.45));
        c.save(); c.translate(600, 1390); c.scale(pp, pp); text(c, '?', 0, 0, font(900, 160), C.red); c.restore();
        // hovering pen
        c.save(); c.translate(760 + Math.sin(u * 6) * 14, 1300 + Math.cos(u * 5) * 10); c.rotate(-0.7); fillRR(c, -10, -110, 20, 150, 6, '#2e4a8a'); c.restore();
      }
    });
    headline(ctx, u, 0.35, 3.9, ['Сатылды, бірақ', '*жазылмады*'], { hcolor: C.red });
  } else {
    // Part B: revision in warehouse
    const v = u - 4.2;
    const cam = { x: 560 - v * 22, y: 980 - v * 10, z: 1.05 + v * 0.035, r: lerp(0.02, -0.015, seg(v, 0, 3.8)) };
    blurLayer(ctx, cam, 0.85, c => { warehouseRoom(c, -1400, 2600); whShelf(c, -200, 520, 560, 800, ['42', '42', '42', '41', '42'], 31); whShelf(c, 760, 520, 560, 800, ['40', '42', '43'], 33); }, 6);
    layer(ctx, cam, 1, c => {
      c.fillStyle = C.whFloor; c.fillRect(-1400, FLOOR, 4000, 1000);
      const shock = v > 1.55;
      person(c, 'owner', { x: 360, y: FLOOR, s: 0.95, face: shock ? (v > 2.4 ? 'angry' : 'shock') : 'neutral', hold: 'notebook', armR: 0.95, armL: shock ? -0.5 : -0.12, lean: shock ? -0.03 : 0, headTilt: shock ? 0.05 : 0 });
    });
    layer(ctx, { x: 540, y: 960, z: 1, r: 0 }, 1, c => {
      const a = E.outBack(seg(v, 0.5, 0.85)), b = E.outBack(seg(v, 0.95, 1.3));
      c.save(); c.translate(790, 880); c.scale(a, a); c.rotate(-0.04); appCard(c, -190, -80, 380, 160); text(c, 'Дәптерде', 0, -30, font(700, 34), C.ink2); text(c, '12 жұп', 0, 30, font(900, 60), C.ink); c.restore();
      c.save(); c.translate(790, 1090); c.scale(b, b); c.rotate(0.03); appCard(c, -190, -80, 380, 160); text(c, 'Сөреде', 0, -30, font(700, 34), C.ink2); text(c, '9 жұп', 0, 30, font(900, 60), C.ink); c.restore();
      const st = seg(v, 1.6, 1.9);
      if (st > 0) {
        const sc = lerp(2.4, 1, E.outC(st));
        c.save(); c.translate(800, 1330); c.rotate(-0.12); c.scale(sc, sc); c.globalAlpha = clamp(st * 3);
        c.strokeStyle = C.red; c.lineWidth = 12; rr(c, -150, -80, 300, 160, 24); c.stroke();
        text(c, '−3', 0, 6, font(900, 120), C.red); c.restore();
      }
    });
    headline(ctx, v, 0.15, 3.6, ['Ревизияда тауар', '*жетпейді*'], { hcolor: C.red });
  }
  const w = seg(u, 4.0, 4.45); wipe(ctx, w, C.ink, -0.35, C.red);
}

// ── 3 · CROWD (20–28.5) ───────────────────────────────────────────────────
cue(20.0, 'whoosh', 0.7); cue(20.3, 'steps', 0.9); cue(21.35, 'thud', 1.0); cue(21.5, 'thud', 0.9); cue(21.62, 'thud', 0.9);
cue(21.9, 'thud', 0.7); cue(22.2, 'thud', 0.6); cue(22.75, 'pop', 0.6); cue(23.05, 'pop', 0.6); cue(23.35, 'pop', 0.6);
cue(24.3, 'swish', 0.6); cue(24.7, 'paper', 1.0); cue(25.2, 'paper', 0.8); cue(26.1, 'pop', 0.6);
function sCrowd(ctx, u) {
  const shakeT = u - 1.35; const shake = shakeT > 0 && shakeT < 0.7 ? Math.exp(-shakeT * 6) * 22 : 0;
  const pan = E.ioC(seg(u, 4.0, 4.8));
  const cam = {
    x: lerp(540, 1440, pan) + noise1(u * 30, 1) * shake,
    y: lerp(1000, 1060, pan) + noise1(u * 30, 2) * shake,
    z: lerp(lerp(0.75, 0.95, E.outC(seg(u, 0, 1.4))), 1.12, pan) + u * 0.006,
    r: lerp(-0.02, 0.03, pan) + noise1(u * 20, 3) * shake * 0.001,
  };
  layer(ctx, cam, 1, c => {
    storeRoom(c, -1600, 3000);
    // warehouse door wall section
    c.fillStyle = '#d8d0c2'; c.fillRect(320, 640, 440, FLOOR - 640);
    door(c, 410, 830, 260, 520, u > 0.9 ? 1 : 0, 'ҚОЙМА');
    rack(c, -560, 660, 600, 13, u); shoeShelf(c, 820, 520, 380, 3, 14);
    counter(c, 1150, 1120, 560);
    // falling boxes from above door
    for (let i = 0; i < 4; i++) {
      const tt = u - (1.6 + i * 0.14); if (tt < 0) continue;
      const y = Math.min(500 + tt * tt * 2600, FLOOR - 4), bx = 450 + i * 70 + tt * 40 * (i % 2 ? 1 : -1);
      c.save(); c.translate(bx, y); c.rotate(Math.min(tt, 0.35) * (i % 2 ? 3 : -3)); box3(c, 0, 0, 100, 74, ['42', '38', 'M', '40'][i]); c.restore();
    }
    // three sellers rushing to door
    const rush = p => E.ioQ(p);
    const s1 = rush(seg(u, 0.2, 1.35)), s2 = rush(seg(u, 0.3, 1.5)), s3 = rush(seg(u, 0.4, 1.62));
    const jam = u > 1.35 ? Math.sin((u - 1.35) * 22) * Math.exp(-(u - 1.35) * 2.5) : 0;
    person(c, 'sly', { x: lerp(-250, 470, s1) + jam * 10, y: FLOOR, s: 0.82, dir: 1, walk: s1 < 1 ? u * 15 : 0, run: 1, moving: s1 > 0 && s1 < 1, face: u > 1.35 ? 'shock' : 'neutral', squash: 1 - Math.abs(jam) * 0.05 });
    person(c, 'seller3', { x: lerp(1300, 610, s2) - jam * 12, y: FLOOR, s: 0.82, dir: -1, walk: s2 < 1 ? u * 15 : 0, run: 1, moving: s2 > 0 && s2 < 1, face: u > 1.5 ? 'worried' : 'neutral', squash: 1 + Math.abs(jam) * 0.04 });
    person(c, 'yeraly', { x: lerp(1500, 540, s3), y: FLOOR + 6, s: 0.84, dir: -1, walk: s3 < 1 ? u * 15 : 0, run: 1, moving: s3 > 0 && s3 < 1, face: u > 1.62 ? 'worried' : 'neutral', sweat: u > 1.8, lean: jam * 0.05 });
    if (u > 1.35 && u < 3.8) { const a = 1 - seg(u, 3.3, 3.8); c.save(); c.globalAlpha = a; for (let i = 0; i < 3; i++) star(c, 520 + Math.cos(u * 5 + i * 2.1) * 120, 760 + Math.sin(u * 5 + i * 2.1) * 30, 18, '#FFD23F'); c.restore(); }
    // seller at counter with notebook, forgetting
    const fp = seg(u, 4.4, 5.2);
    person(c, 'c4', { x: 1820, y: FLOOR, s: 0.84, dir: -1, face: 'neutral', armL: -0.6 });
    person(c, 'c1', { x: 2120, y: FLOOR, s: 0.84, dir: -1, face: 'worried' });
    // notebook sliding & pages flying
    if (u < 6.5) {
      const slide = E.inQ(seg(u, 4.5, 5.0));
      notebook(c, 1430 + slide * 280, 1080 + slide * slide * 300, 300, 220, { rot: slide * 1.2, title: 'Сатылымдар', lines: ['Кросс. 42', 'Жейде M'] });
    }
    for (let i = 0; i < 9; i++) {
      const tt = u - (4.75 + i * 0.12); if (tt < 0 || tt > 3) continue;
      const R = rng(i + 70);
      const px = 1700 + tt * (180 + R() * 380) + Math.sin(tt * 6 + i) * 60, py = 1350 - tt * (260 + R() * 360);
      c.save(); c.translate(px, py); c.rotate(Math.sin(tt * 5 + i) * 0.9); c.scale(Math.cos(tt * 7 + i), 1);
      fillRR(c, -50, -36, 100, 72, 6, '#fffdf6', '#c9bfa8', 2); c.restore();
    }
    // forgetting seller at counter (thought bubble)
    person(c, 'seller3', { x: 1440, y: FLOOR, s: 0.84, dir: 1, face: 'worried', hold: 'phone', phoneColor: '#9aa', armR: u > 5.6 ? 0.2 : 0.1, armL: u > 5.8 ? -2.4 + Math.sin(u * 3) * 0.1 : -0.15, headTilt: u > 5.8 ? 0.12 : 0 });
    if (u > 5.8) {
      const p = E.outBack(seg(u, 5.85, 6.25));
      c.save(); c.translate(1180, 760); c.scale(p, p);
      circle(c, 230, 125, 14, '#fff'); circle(c, 200, 92, 20, '#fff');
      shadowOn(c, 20, 6, 0.15); fillRR(c, -60, -110, 360, 170, 85, '#fff'); shadowOff(c);
      text(c, 'Не саттым?..', 120, -25, font(800, 42), C.ink); c.restore();
    }
    // client bubbles near door
    const qs = [['42?', 780, 720, 2.7], ['M бар ма?', 140, 700, 3.0], ['38?', 960, 900, 3.3]];
    qs.forEach(([s, x, y, t0]) => { if (u > t0 && u < 4.4) bubble(c, x, y, s, { scale: E.outBack(seg(u, t0, t0 + 0.3)) * (1 - E.inC(seg(u, 4.1, 4.4))), size: 38 }); });
  });
  // foreground clients' heads (depth)
  blurLayer(ctx, cam, 1.35, c => {
    person(c, 'c3', { x: -40, y: 2080, s: 1.1, face: 'worried' });
    person(c, 'c2', { x: 1180, y: 2120, s: 1.15, face: 'angry', dir: -1 });
    person(c, 'c1', { x: 2330, y: 2120, s: 1.1, face: 'worried', dir: -1 });
  }, 12);
  if (u < 4.1) headline(ctx, u, 0.3, 3.8, ['Бір қойма —', '*үш сатушы*'], { hcolor: C.red });
  else headline(ctx, u, 4.35, 9, ['Дәптер *жоғалды*.', 'Жазу *ұмытылды*.'], { hcolor: C.red });
}

// ── 4 · TURN (28.5–32) ────────────────────────────────────────────────────
cue(28.5, 'riserEnd', 0.6); cue(28.55, 'whooshUp', 0.9); cue(29.0, 'impact', 1.0); cue(29.6, 'pop', 0.8); cue(31.65, 'swish', 0.9);
function sTurn(ctx, u) {
  // frozen, desaturated chaos
  if (u < 1.2) {
    ctx.save(); ctx.filter = `grayscale(${clamp(u * 3)}) brightness(${1 - clamp(u * 3) * 0.25})`;
    const b = _frozen(); ctx.drawImage(b, 0, 0); ctx.restore();
  }
  // phone rising
  const rise = E.outBack(seg(u, 0.05, 0.5), 1.2);
  const wp = E.inQ(seg(u, 0.45, 0.85)); // wave
  if (u < 1.2) {
    phone(ctx, 540, lerp(2600, 1060, rise), 380, lerp(0.3, -0.05, rise), (c, w, h) => { c.fillStyle = C.green; c.fillRect(0, 0, w, h); const s = w * 0.55; c.drawImage(LOGO, w / 2 - s / 2, h / 2 - s / 2, s, s); });
  }
  if (u > 0.45) {
    ctx.save(); const R = lerp(0, 2300, wp);
    ctx.beginPath(); ctx.arc(540, 1060, R, 0, Math.PI * 2);
    const g = ctx.createRadialGradient(540, 1060, 0, 540, 1060, Math.max(1, R)); g.addColorStop(0, '#00B56A'); g.addColorStop(1, C.greenDeep);
    ctx.fillStyle = g; ctx.fill(); ctx.restore();
    if (u < 1.2) { ctx.save(); ctx.strokeStyle = 'rgba(255,255,255,0.6)'; ctx.lineWidth = 30 * (1 - wp); ctx.beginPath(); ctx.arc(540, 1060, R + 30, 0, 7); ctx.stroke(); ctx.restore(); }
  }
  if (u > 0.85) {
    // logo + headline on green
    const pulse = 1 + Math.sin((u - 0.85) * 6) * Math.exp(-(u - 0.85) * 3) * 0.06;
    const ls = spring(u - 0.9, 1.4, 5.5) * pulse;
    ctx.save(); ctx.translate(540, 1150); ctx.scale(ls, ls);
    shadowOn(ctx, 60, 24, 0.3); fillRR(ctx, -150, -150, 300, 300, 70, '#fff'); shadowOff(ctx);
    ctx.save(); rr(ctx, -132, -132, 264, 264, 58); ctx.clip(); ctx.drawImage(LOGO, -132, -132, 264, 264); ctx.restore(); ctx.restore();
    headline(ctx, u, 0.95, 3.0, ['Енді —', '*Qoima*'], { y: 420, size: 150, color: '#fff', hcolor: '#fff', htext: C.greenDeep });
    // radiating rings
    for (let i = 0; i < 3; i++) { const tt = (u - 0.9 - i * 0.35); if (tt < 0 || tt > 1.4) continue; ctx.save(); ctx.globalAlpha = 0.35 * (1 - tt / 1.4); ctx.strokeStyle = '#fff'; ctx.lineWidth = 6; ctx.beginPath(); ctx.arc(540, 1150, 200 + tt * 500, 0, 7); ctx.stroke(); ctx.restore(); }
  }
  const w = seg(u, 3.15, 3.5); wipe(ctx, w * 0.5, C.greenDeep, -1.5708 + 0.25);
}
let _frozenCanvas = null;
function _frozen() {
  if (_frozenCanvas) return _frozenCanvas;
  _frozenCanvas = document.createElement('canvas'); _frozenCanvas.width = W; _frozenCanvas.height = H;
  const c = _frozenCanvas.getContext('2d'); sCrowd(c, 8.45); grade(c, 1); return _frozenCanvas;
}

// ── 5 · STOCK (32–38) ─────────────────────────────────────────────────────
cue(32.0, 'swish', 0.7); cue(32.5, 'tap', 0.8); cue(32.9, 'type', 0.6); cue(33.4, 'ding', 0.6);
cue(34.6, 'focus', 0.4); cue(34.95, 'pop', 0.7); cue(35.15, 'pop', 0.7); cue(35.35, 'pop', 0.7); cue(36.6, 'ding', 0.9);
function stockScreen(c, w, h, u) {
  ui(c, w, c => {
    appBar(c, 'Қойма · іздеу');
    fillRR(c, 20, 140, 360, 64, 32, '#fff', C.line, 3);
    const typed = '42'.slice(0, Math.floor(clamp((u - 0.85) / 0.25) * 2 + 0.001));
    text(c, '🔍', 46, 173, font(500, 26), C.ink2, 'left');
    text(c, typed || 'Размер…', 86, 173, font(700, 28), typed ? C.ink : '#9aa', 'left');
    const rows = [['Кроссовка', '42', 'B-3', '3 дана', true], ['Кроссовка', '41', 'B-2', '5 дана'], ['Кеды', '42', 'C-1', '2 дана'], ['Етік', '42', 'A-4', '1 дана']];
    rows.forEach((r, i) => {
      const a = E.outC(seg(u, 1.05 + i * 0.08, 1.4 + i * 0.08)); if (a <= 0) return;
      c.save(); c.globalAlpha = a; c.translate(0, (1 - a) * 30);
      const y = 230 + i * 120;
      appCard(c, 20, y, 360, 104);
      if (r[4]) { c.strokeStyle = C.green; c.lineWidth = 4; rr(c, 20, y, 360, 104, 18); c.stroke(); }
      sneaker(c, 38, y + 70, 0.6, r[4] ? C.green : '#9aa');
      text(c, `${r[0]} · ${r[1]}`, 110, y + 36, font(800, 26), C.ink, 'left');
      text(c, r[3], 110, y + 74, font(600, 22), C.ink2, 'left');
      pill(c, 330, y + 52, r[2], { size: 22, pad: 14, bg: r[4] ? C.green : C.line, color: r[4] ? '#fff' : C.ink, shadow: false });
      c.restore();
    });
  });
}
function sStock(ctx, u) {
  const rf = E.ioC(seg(u, 2.4, 3.0)); // rack focus to background
  const cam = { x: 540 + Math.sin(u * 0.7) * 50 - u * 12, y: 980 + u * 8, z: 1.0 + u * 0.03, r: lerp(-0.025, 0.02, seg(u, 0, 6)) };
  blurLayer(ctx, cam, 1, c => {
    storeRoom(c, -1600, 2800);
    rack(c, -420, 640, 500, 41, u); shoeShelf(c, 760, 500, 520, 3, 42); lamp(c, 300, 260); lamp(c, 900, 260);
    const ppl = [['seller3', 230, 'A-1'], ['yeraly', 560, 'B-3'], ['sly', 890, 'C-2']];
    ppl.forEach(([k, x, chip], i) => {
      const hand = u < 4.3 || k !== 'yeraly';
      person(c, k, { x, y: FLOOR, s: 0.8, face: 'smile', hold: hand ? 'phone' : 'box', boxLabel: '42', armR: hand ? 1.05 + Math.sin(u * 2 + i) * 0.03 : 1.3, armL: hand ? undefined : -1.2, look: 0.4 });
      const cp = E.outBack(seg(u, 2.95 + i * 0.2, 3.3 + i * 0.2));
      if (cp > 0) { c.save(); c.translate(x, 640); c.scale(cp, cp); fillRR(c, -90, -40, 180, 80, 40, C.green); check(c, -50, 0, 22, seg(u, 3.1 + i * 0.2, 3.5 + i * 0.2), '#fff'); text(c, chip, 20, 2, font(900, 34), '#fff'); c.restore(); }
    });
    // Madina receives
    const mIn = E.outC(seg(u, 3.6, 4.3));
    person(c, 'madina', { x: lerp(1500, 800, mIn), y: FLOOR + 4, s: 0.82, dir: -1, walk: mIn < 1 ? u * 11 : 0, moving: mIn > 0 && mIn < 1, face: u > 4.6 ? 'happy' : 'smile', hold: u > 4.6 ? 'box' : null, boxLabel: '42', armR: u > 4.6 ? 1.2 : undefined });
    burst(c, 700, 760, u - 4.6, 14, C.green, 5, 240);
  }, rf * 0 + (1 - rf) * 9);
  // foreground big phone (out of focus after rack)
  const ph = E.ioC(seg(u, 2.4, 3.1));
  ctx.save(); if (ph > 0.05) ctx.filter = `blur(${(ph * 14).toFixed(1)}px)`;
  phone(ctx, lerp(560, 260, ph) + Math.sin(u * 0.8) * 10, lerp(1080, 1900, ph), lerp(520, 640, ph), lerp(-0.06, -0.25, ph), (c, w, h) => stockScreen(c, w, h, u));
  // finger tap
  if (u > 0.4 && u < 1.1) { const tp = seg(u, 0.4, 0.7); ctx.save(); ctx.globalAlpha = 1 - seg(u, 0.8, 1.1); circle(ctx, 560, 830, 20 + tp * 40, null, C.green, 6); ctx.restore(); }
  ctx.restore();
  headline(ctx, u, 0.3, 5.6, ['Қойма — әр сатушының', '*қалтасында*']);
}

// ── 6 · PUSH (38–43.5) ────────────────────────────────────────────────────
cue(38.0, 'whoosh', 0.7); cue(38.5, 'tap', 0.8); cue(38.75, 'print', 0.7); cue(39.4, 'cash', 0.9); cue(39.95, 'ding', 0.8);
cue(40.25, 'whoosh', 0.9); cue(40.85, 'notif', 1.0); cue(41.55, 'notif', 0.9); cue(42.25, 'notif', 0.9);
function sPush(ctx, u) {
  if (u < 2.25) {
    const enter = E.outC(seg(u, 0, 0.4)); const ex = E.inC(seg(u, 1.95, 2.25));
    const cam = { x: lerp(260, 560, enter) + ex * 900, y: 960, z: 1.3 + u * 0.04, r: lerp(-0.05, 0.01, enter) + ex * 0.05 };
    layer(ctx, cam, 1, c => {
      storeRoom(c, -1600, 3000); shoeShelf(c, 160, 500, 700, 3, 51); lamp(c, 560, 260);
      const reach = E.ioC(seg(u, 1.2, 1.55)) * (1 - E.ioC(seg(u, 1.75, 2.0)));
      person(c, 'sly', { x: 560, y: FLOOR, s: 0.9, face: u > 1.55 ? 'shock' : 'sly', armL: lerp(-0.9, -0.05, reach), armR: 0.25, look: u > 1.55 ? 1 : 0 });
      counter(c, 250, 1130, 620);
      // POS tablet + receipt
      fillRR(c, 600, 1000, 200, 130, 14, C.ink); fillRR(c, 612, 1012, 176, 106, 8, C.green);
      text(c, 'Сату ✓', 700, 1066, font(800, 30), '#fff');
      const rp = E.outC(seg(u, 0.7, 1.3));
      c.save(); c.beginPath(); c.rect(560, 600, 300, 400); c.clip();
      fillRR(c, 625, 1000 - rp * 300, 150, 300, 6, '#fff', '#ddd', 2);
      for (let i = 0; i < 5; i++) { c.fillStyle = '#bbb'; c.fillRect(645, 1030 - rp * 300 + i * 34, i === 4 ? 70 : 110, 8); }
      c.restore();
      if (u > 1.55) { const cp = E.outBack(seg(u, 1.55, 1.85)); c.save(); c.translate(420, 820); c.scale(cp, cp); pill(c, 0, 0, '✓ Жүйеде жазылды', { size: 34 }); c.restore(); }
    });
  } else {
    const v = u - 2.25;
    const enter = E.outC(seg(v, 0, 0.5));
    const cam = { x: lerp(-500, 520, enter) + v * 14, y: 980 - v * 6, z: 1.0 + v * 0.05, r: lerp(-0.06, 0.015, enter) };
    blurLayer(ctx, cam, 0.7, c => {
      c.fillStyle = '#F3E9DC'; c.fillRect(-2000, -1400, 5000, 4000);
      fillRR(c, -100, 380, 520, 420, 20, '#bfe3f2', '#e6d8c4', 18); fillRR(c, 640, 380, 520, 420, 20, '#bfe3f2', '#e6d8c4', 18);
      plant(c, 1250, 1180, 1.3); plant(c, -200, 1180, 1.1); lamp(c, 270, 120); lamp(c, 900, 120);
      c.fillStyle = '#D8C3A5'; c.fillRect(-2000, FLOOR, 5000, 1000);
    }, 9);
    layer(ctx, cam, 1, c => {
      // table + cup
      fillRR(c, 40, 1150, 470, 26, 10, C.woodDark); c.fillStyle = C.woodDark; c.fillRect(260, 1170, 26, 180);
      fillRR(c, 120, 1090, 54, 62, 10, '#fff', '#ccc', 3);
      person(c, 'owner', { x: 300, y: FLOOR + 10, s: 0.92, face: v > 0.7 ? 'smile' : 'neutral', hold: 'phone', armR: 1.05, armL: -0.2, look: 1 });
    });
    // notifications stack (screen space)
    const N = [['Жаңа сатылым', 'Кроссовка · 42 · 38 000 ₸', 0.55], ['Жаңа сатылым', 'Жейде · M · 12 500 ₸', 1.25], ['Жаңа сатылым', 'Куртка · L · 45 000 ₸', 1.95]];
    N.forEach(([a, b, t0], i) => {
      const d = v - t0; if (d < 0) return;
      const n = N.filter(x => v > x[2]).length;
      const pos = n - 1 - i; // newest on top
      const sp = spring(d, 1.5, 6);
      const y = 690 + pos * 180 - (1 - clamp(sp)) * 260;
      notif(ctx, 560 + (1 - clamp(sp)) * 40, y, 900, a, b, { logo: LOGO, time: 'қазір', scale: lerp(0.85, 1, clamp(sp)) * (1 - pos * 0.04), alpha: clamp(d * 5) * (1 - pos * 0.18) });
    });
  }
  headline(ctx, u, 0.3, 5.0, ['Әр сатылым —', '*сізде*']);
}

// ── 7 · REVISION (43.5–49) ────────────────────────────────────────────────
cue(43.5, 'swish', 0.8); cue(43.75, 'whoosh', 0.8);
for (let i = 0; i < 7; i++) cue(44.85 + i * 0.28, 'tick', 0.55);
cue(47.0, 'ding', 0.9); cue(47.35, 'pop', 0.7);
function revScreen(c, w, h, u) {
  ui(c, w, c => {
    appBar(c, 'Ревизия');
    const prog = clamp(seg(u, 1.3, 3.4));
    text(c, 'Тексерілді', 24, 170, font(700, 26), C.ink2, 'left');
    text(c, `${Math.round(prog * 124)}/124`, 376, 170, font(900, 30), C.ink, 'right');
    fillRR(c, 24, 196, 352, 18, 9, C.line); fillRR(c, 24, 196, Math.max(18, 352 * prog), 18, 9, C.green);
    const items = ['Кроссовка 42', 'Кроссовка 41', 'Жейде M', 'Куртка L', 'Кеды 39', 'Шалбар 32', 'Етік 40'];
    items.forEach((s, i) => {
      const y = 240 + i * 86; appCard(c, 20, y, 360, 74);
      text(c, s, 40, y + 37, font(700, 26), C.ink, 'left');
      const ck = seg(u, 1.35 + i * 0.28, 1.6 + i * 0.28);
      if (i === 4) { if (ck > 0) { pill(c, 316, y + 37, '−1', { size: 22, pad: 14, bg: C.amber, shadow: false, scale: E.outBack(ck) }); } }
      else if (ck > 0) check(c, 340, y + 37, 22 * E.outBack(ck), ck);
    });
  });
}
function sRev(ctx, u) {
  const cam = { x: 540 + u * 16, y: 980, z: 1.05 + u * 0.03, r: lerp(0.025, -0.02, seg(u, 0, 5.5)) };
  blurLayer(ctx, cam, 0.8, c => { warehouseRoom(c, -1600, 2800); whShelf(c, -300, 480, 600, 840, ['42', '41', '40', '39'], 61); whShelf(c, 760, 480, 600, 840, ['M', 'L', 'S'], 62); }, 8);
  layer(ctx, cam, 1, c => {
    c.fillStyle = C.whFloor; c.fillRect(-1600, FLOOR, 4400, 1000);
    person(c, 'owner', { x: 170, y: FLOOR, s: 0.9, face: u > 3.4 ? 'happy' : 'smile', armL: -0.15, armR: u > 3.4 ? 2.6 : 0.3, hold: u > 3.4 ? null : null });
  });
  // notebook flies away
  if (u < 1.0) { const p = E.inC(seg(u, 0.1, 0.9)); notebook(ctx, lerp(560, -500, p), lerp(1150, 500, p), 520, 380, { rot: -0.1 - p * 3, title: 'Ревизия', lines: ['Кросс. 42 — ?', 'Жейде — ?'] }); }
  const ph = E.outBack(seg(u, 0.45, 1.0), 1.1);
  phone(ctx, lerp(1300, 640, ph), 1110, 560, lerp(0.35, 0.05, ph) + Math.sin(u * 0.9) * 0.01, (c, w, h) => revScreen(c, w, h, u));
  if (u > 3.5) { const p = E.outBack(seg(u, 3.5, 3.85)); ctx.save(); ctx.translate(740, 1660); ctx.scale(p, p); pill(ctx, 0, 0, '⏱  4 минут', { size: 44, bg: C.ink }); ctx.restore(); burst(ctx, 640, 700, u - 3.5, 12, C.green, 9, 260); }
  headline(ctx, u, 0.3, 5.1, ['Ревизия —', '*бірнеше минутта*']);
  const w = seg(u, -0.25, 0.25); wipe(ctx, w + 0.0, C.green, -0.35);
}

// ── 8 · ANALYTICS (49–55) ─────────────────────────────────────────────────
cue(49.0, 'whoosh', 0.8); cue(49.6, 'pop', 0.7); cue(49.9, 'pop', 0.7); cue(50.2, 'pop', 0.7); cue(50.5, 'pop', 0.7); cue(51.8, 'ding', 0.6); cue(54.6, 'whooshUp', 0.9);
function sAna(ctx, u) {
  const out = E.inC(seg(u, 5.5, 6.0));
  const cam = { x: lerp(380, 700, E.ioQ(seg(u, 0, 6))), y: lerp(1000, 940, seg(u, 0, 6)), z: lerp(0.92, 1.12, E.ioQ(seg(u, 0, 6))) + out * 0.6, r: lerp(-0.03, 0.035, E.ioQ(seg(u, 0, 6))) };
  blurLayer(ctx, cam, 0.6, c => { c.fillStyle = '#E7F4EE'; c.fillRect(-3000, -3000, 7000, 7000); for (let i = 0; i < 18; i++) { const R = rng(i + 90); circle(c, R() * 2200 - 600, R() * 2400 - 300, 40 + R() * 90, `rgba(0,168,98,${0.06 + R() * 0.08})`); } }, 10);
  const card = (d, blur, x, y, t0, w, h, draw) => {
    const p = spring(u - t0, 1.4, 5.5); if (p <= 0) return;
    blurLayer(ctx, cam, d, c => { c.save(); c.translate(x, y); c.scale(clamp(p, 0, 1.2), clamp(p, 0, 1.2)); c.rotate((1 - clamp(p)) * 0.3); shadowOn(c, 40, 18, 0.18); fillRR(c, -w / 2, -h / 2, w, h, 30, '#fff'); shadowOff(c); draw(c, w, h); c.restore(); }, blur);
  };
  // back card: warehouses
  card(0.75, 5, 120, 560, 0.6, 420, 260, (c, w, h) => {
    text(c, 'Қоймалар', -w / 2 + 30, -h / 2 + 46, font(800, 34), C.ink, 'left');
    [['Қойма 1', -90], ['Қойма 2', 90]].forEach(([s, x], i) => { const pin = E.outBack(seg(u, 1.0 + i * 0.2, 1.3 + i * 0.2)); c.save(); c.translate(x, 30); c.scale(pin, pin); circle(c, 0, -20, 34, C.green); circle(c, 0, -20, 13, '#fff'); c.beginPath(); c.moveTo(-20, 0); c.lineTo(0, 40); c.lineTo(20, 0); c.fillStyle = C.green; c.fill(); text(c, s, 0, 80, font(700, 26), C.ink2); c.restore(); });
  });
  layer(ctx, cam, 1, c => { person(c, 'owner', { x: 540, y: FLOOR + 40, s: 1.05, face: 'smile', hold: 'phone', armR: 1.0, armL: -0.25, look: 0.3 }); });
  // chart card
  card(1.0, 0, 860, 720, 0.9, 400, 330, (c, w, h) => {
    text(c, 'Сатылым', -w / 2 + 30, -h / 2 + 46, font(800, 34), C.ink, 'left');
    const bars = [0.35, 0.5, 0.42, 0.66, 0.74, 0.95];
    bars.forEach((b, i) => { const p = E.outC(seg(u, 1.3 + i * 0.12, 2.0 + i * 0.12)); const bh = 200 * b * p; fillRR(c, -w / 2 + 36 + i * 58, h / 2 - 30 - bh, 40, Math.max(bh, 1), 8, i === 5 ? C.green : '#bfe8d3'); });
  });
  // fg card: top seller
  card(1.25, 6, 150, 1290, 1.2, 420, 200, (c, w, h) => {
    circle(c, -w / 2 + 70, 0, 44, C.amber); text(c, '1', -w / 2 + 70, 2, font(900, 44), '#fff');
    text(c, 'Топ-1: Ералы', -w / 2 + 132, -24, font(800, 34), C.ink, 'left'); text(c, '46 сатылым', -w / 2 + 132, 26, font(600, 28), C.ink2, 'left');
  });
  // fg card: month total
  card(1.12, 2, 900, 1220, 1.5, 400, 200, (c, w, h) => {
    const val = Math.round(lerp(0, 4820000, E.outC(seg(u, 1.6, 3.0))) / 1000) * 1000;
    text(c, 'Ай бойы', 0, -38, font(700, 30), C.ink2); text(c, val.toLocaleString('ru-RU').replace(/,/g, ' ') + ' ₸', 0, 22, font(900, 46), C.greenDeep);
  });
  headline(ctx, u, 0.3, 5.2, ['Бәрі —', '*бір телефонда*']);
  // rise to end card
  const rise = E.ioC(seg(u, 5.55, 6.0));
  if (rise > 0) { ctx.fillStyle = C.green; ctx.fillRect(0, H * (1 - rise), W, H * rise + 2); }
}

// ── master ────────────────────────────────────────────────────────────────
const TL1 = [[0, 6, sIntro], [6, 12, sRun], [12, 20, sPocket], [20, 28.5, sCrowd], [28.5, 32, sTurn], [32, 38, sStock], [38, 43.5, sPush], [43.5, 49, sRev], [49, 55, sAna], [55, 60, (c, u) => endCard(c, u)]];
cue(55.0, 'impact', 0.7); cue(55.3, 'pop', 0.9); cue(55.85, 'chime', 0.9);
const SCENE = {
  dur: 60, sub: 4,
  cues: CUES1, vo: VO1.map(v => ({ key: 'v1_' + v[0], t: v[1] })),
  draw(ctx, t) {
    ctx.save();
    for (const [a, b, fn] of TL1) { if (t >= a && t < b) { fn(ctx, t - a); break; } }
    if (t >= 60) endCard(ctx, t - 55);
    // problem grading 6–28.5
    const warm = seg(t, 6, 6.6) * (1 - seg(t, 28.4, 28.6));
    if (warm > 0) { grade(ctx, warm * 0.8); vignette(ctx, 0.3 * warm); }
    captions(ctx, t, CAPS1, { y: 1540 });
    ctx.restore();
  }
};
