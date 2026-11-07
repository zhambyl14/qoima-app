// ВИДЕО 2 — «Дүкеніңіз телефонда»
'use strict';
const VO2_KK = [
  ['intro', 0.6, 4.75, 'Дүкеніңіз телефонда ашылса, не өзгереді? Көрейік.'],
  ['pickup', 6.25, 7.87, 'Клиент қосымшадан тапсырыс береді, дүкенге келіп, QR кодын көрсетеді де, тауарын алып кетеді. Өте қарапайым.'],
  ['promo', 15.3, 3.96, 'Промокод пен акция жасаңыз — сатылым бірден өседі.'],
  ['referral', 20.75, 9.72, '«Досыңды шақыр» қосылса, клиенттер достарына өз промокодын жібереді. Досы да, өзі де жеңілдік алады, сатылым одан сайын көбейеді.'],
  ['qa', 31.25, 5.23, 'Клиенттер тауар туралы онлайн сұрақ қояды, сатып алғандар баға береді.'],
  ['demand', 38.25, 5.42, 'Клиенттер не қалайтынын көресіз: көп сұралған тауарды уақытында әкелесіз.'],
  ['growth', 45.5, 2.86, 'Сауда өседі, жұмыс жеңілдейді.'],
  ['end', 53.0, 2.9, 'Qoima-ны тегін қолданып көріңіз!'],
];
const VO2 = LANG === 'ru' ? VO2_KK.map(([k, s]) => [k, s, RUVO['v2_' + k].dur, RUVO['v2_' + k].text]) : VO2_KK;
const CAPS2 = VO2.flatMap(([k, s, d, c]) => chunkVO(c, s, d));
const CUES2 = [];
const cue2 = (t, s, g = 1) => CUES2.push({ t: +t.toFixed(3), s, g });

function productImg(c, x, y, w, h, col = C.green) {
  fillRR(c, x, y, w, h, 18, '#EEF4F1'); sneaker(c, x + w * 0.12, y + h * 0.72, w / 125, col);
}

// ── 0 · INTRO (0–6) night storefront ──────────────────────────────────────
cue2(0.3, 'swish', 0.5); cue2(2.2, 'flip', 0.9); cue2(2.45, 'ding', 0.9); cue2(2.5, 'hum', 0.6); cue2(5.1, 'whoosh', 1.0);
function storefront(c, u, open) {
  // building
  fillRR(c, -60, 380, 1200, 1100, 0, '#2b3445');
  c.fillStyle = '#232b39'; for (let i = 0; i < 6; i++) c.fillRect(-60 + i * 200, 380, 6, 1000);
  // sign board
  fillRR(c, 120, 470, 840, 170, 26, '#11161f');
  c.save(); c.globalAlpha = 0.25 + open * 0.75;
  c.shadowColor = C.greenBright; c.shadowBlur = 40 * open;
  text(c, 'ДҮКЕН', 540, 558, font(900, 110), open > 0.5 ? '#7CF2B6' : '#3d5d4f');
  c.restore();
  // window
  const wl = open;
  const g = c.createLinearGradient(0, 760, 0, 1350); g.addColorStop(0, `rgba(255,${200 + 30 * wl},${120 + 60 * wl},${0.15 + 0.75 * wl})`); g.addColorStop(1, `rgba(255,190,110,${0.1 + 0.6 * wl})`);
  fillRR(c, 90, 760, 560, 590, 10, '#151b25'); fillRR(c, 90, 760, 560, 590, 10, g);
  c.save(); c.globalAlpha = 0.4 + 0.6 * wl; rack(c, 130, 880, 480, 77, u * 2); c.restore();
  // door
  fillRR(c, 700, 760, 280, 590, 10, '#151b25'); fillRR(c, 714, 774, 252, 576, 8, `rgba(255,214,150,${0.1 + 0.5 * wl})`);
  circle(c, 940, 1060, 10, '#e6c26b');
  // hanging sign flip
  const fl = Math.cos(Math.PI * E.ioC(seg(u, 2.0, 2.4)));
  c.save(); c.translate(840, 900); c.rotate(Math.sin(u * 3) * 0.03 * (1 - open) + Math.sin((u - 2.4) * 10) * Math.exp(-(u - 2.4) * 3) * 0.12 * (u > 2.4));
  c.strokeStyle = '#ccc'; c.lineWidth = 4; c.beginPath(); c.moveTo(-60, -40); c.lineTo(0, -90); c.lineTo(60, -40); c.stroke();
  c.scale(Math.abs(fl), 1);
  const isOpen = fl < 0;
  fillRR(c, -110, -45, 220, 90, 14, isOpen ? C.green : C.red);
  if (Math.abs(fl) > 0.15) text(c, isOpen ? 'АШЫҚ' : 'ЖАБЫҚ', 0, 2, font(900, 44), '#fff');
  c.restore();
  // pavement
  c.fillStyle = '#1b2230'; c.fillRect(-1200, 1350, 3600, 900);
}
function sIntro2(ctx, u) {
  const open = E.outC(seg(u, 2.3, 3.0));
  const g = ctx.createLinearGradient(0, 0, 0, H); g.addColorStop(0, '#0a1020'); g.addColorStop(1, '#1d2a40');
  ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
  const cam = { x: 540 + Math.sin(u * 0.4) * 20, y: lerp(820, 960, E.ioQ(seg(u, 0, 5))), z: lerp(0.86, 1.0, E.ioQ(seg(u, 0, 5))), r: lerp(0.03, -0.01, seg(u, 0, 5)) };
  // stars + skyline (far)
  layer(ctx, cam, 0.2, c => { const R = rng(4); for (let i = 0; i < 70; i++) { c.globalAlpha = 0.3 + 0.7 * Math.abs(Math.sin(u * 2 + i)); circle(c, R() * 1600 - 260, R() * 900 - 200, 2 + R() * 2.5, '#fff'); } c.globalAlpha = 1; circle(c, 880, 120, 60, '#f4f1de'); });
  blurLayer(ctx, cam, 0.5, c => { const R = rng(8); c.fillStyle = '#16203a'; for (let i = 0; i < 12; i++) { const w = 120 + R() * 140, h = 300 + R() * 500; c.fillRect(-400 + i * 170, 1300 - h, w, h + 400); } c.fillStyle = 'rgba(255,214,120,0.5)'; for (let i = 0; i < 40; i++) c.fillRect(-380 + R() * 1900, 700 + R() * 500, 14, 20); }, 6);
  layer(ctx, cam, 1, c => storefront(c, u, open));
  // glow after open
  if (open > 0) { ctx.save(); ctx.globalAlpha = 0.25 * open; const gg = ctx.createRadialGradient(540, 1100, 50, 540, 1100, 900); gg.addColorStop(0, '#ffd28a'); gg.addColorStop(1, 'rgba(255,210,138,0)'); ctx.fillStyle = gg; ctx.fillRect(0, 0, W, H); ctx.restore(); }
  // foreground phone rising, then zoom into it (match cut)
  const rise = E.outBack(seg(u, 1.3, 1.9), 1.1);
  const dive = E.inC(seg(u, 4.9, 6.0));
  if (rise > 0) {
    const sc = lerp(1, 5.2, dive);
    phone(ctx, lerp(820, 540, dive), lerp(2500, 1560, rise) + lerp(0, -600, dive), 300, lerp(0.25, 0.12, rise) * (1 - dive), (c, w, h) => { c.fillStyle = C.green; c.fillRect(0, 0, w, h); const s = w * 0.5; c.drawImage(LOGO, w / 2 - s / 2, h / 2 - s / 2 - 20, s, s); text(c, 'Дүкен ашық', w / 2, h / 2 + s / 2 + 10, font(800, 26), '#fff'); }, { scale: sc });
  }
  headline(ctx, u, 0.4, 4.7, ['Дүкеніңіз', '*телефонда* ашылса?'], { color: '#fff', size: 100, y: 250 });
  vignette(ctx, 0.5);
}

// ── 1 · PICKUP (6–15) ─────────────────────────────────────────────────────
cue2(6.0, 'whoosh', 0.5); cue2(6.7, 'tap', 0.8); cue2(7.35, 'tap', 0.8); cue2(7.8, 'ding', 0.8);
cue2(9.3, 'swish', 0.8); cue2(9.5, 'steps', 0.7); cue2(11.25, 'beep', 0.9); cue2(11.85, 'ding', 1.0); cue2(12.5, 'bag', 0.8); cue2(13.1, 'steps', 0.6);
function orderScreen(c, w, h, u) {
  ui(c, w, c => {
    appBar(c, 'Qoima');
    productImg(c, 20, 140, 360, 300);
    text(c, 'Кроссовка · 42', 24, 480, font(800, 32), C.ink, 'left');
    text(c, '38 000 ₸', 24, 528, font(900, 34), C.greenDeep, 'left');
    const st = u < 0.7 ? 0 : u < 1.35 ? 1 : 2;
    const lab = ['Себетке', 'Тапсырыс беру', 'Тапсырыс берілді ✓'][st];
    fillRR(c, 20, 580, 360, 84, 42, st === 2 ? C.greenDeep : C.green);
    text(c, lab, 200, 623, font(800, 30), '#fff');
    if (u > 1.8) {
      const p = E.outBack(seg(u, 1.8, 2.15));
      c.save(); c.translate(200, 800); c.scale(p, p); qr(c, -90, -90, 180, 12); c.restore();
      text(c, 'Сатушыға QR көрсетіңіз', 200, 940, font(700, 22), C.ink2);
    }
    [0.7, 1.35].forEach(tt => { if (u > tt - 0.05 && u < tt + 0.35) { const p = seg(u, tt - 0.05, tt + 0.35); c.save(); c.globalAlpha = 1 - p; circle(c, 260, 622, 20 + p * 70, null, '#fff', 8); c.restore(); } });
  });
}
function sPickup(ctx, u) {
  if (u < 3.3) {
    const pull = E.ioC(seg(u, 2.0, 3.1));
    const cam = { x: 540 + pull * 30, y: 960, z: lerp(1.25, 1.0, pull), r: lerp(0.02, -0.01, pull) };
    blurLayer(ctx, cam, 1, c => {
      c.fillStyle = '#EFE3D3'; c.fillRect(-1000, -1000, 3000, 4000);
      fillRR(c, 640, 360, 380, 460, 16, '#bfe3f2', '#e2d2bb', 18); lamp(c, 200, 200);
      c.fillStyle = '#D9C6AE'; c.fillRect(-1000, FLOOR, 3000, 1000);
      // sofa
      fillRR(c, 40, 980, 1000, 300, 60, '#2F7DF6'); fillRR(c, 0, 1100, 1080, 240, 60, '#4b8ff7');
      person(c, 'madina', { x: 540, y: FLOOR - 40, s: 0.85, face: u > 1.8 ? 'happy' : 'smile', hold: 'phone', armR: 1.15, armL: -0.3 });
    }, (1 - pull) * 12);
    const sc = lerp(1, 0.16, pull);
    phone(ctx, lerp(540, 640, pull), lerp(1120, 820, pull), 560, lerp(-0.03, -0.15, pull), (c, w, h) => orderScreen(c, w, h, u), { scale: sc });
    headline(ctx, u, 0.25, 2.9, ['Тапсырыс —', '*бір басумен*']);
  } else {
    const v = u - 3.3;
    const walkIn = E.ioQ(seg(v, 0.2, 1.6)), walkOut = E.inQ(seg(v, 4.0, 5.7));
    const mx = lerp(-250, 380, walkIn) + walkOut * 1100;
    const cam = { x: lerp(400, 620, seg(v, 0, 5.7)) + walkOut * 200, y: 980, z: 1.05 + v * 0.02, r: lerp(-0.02, 0.025, seg(v, 0, 5.7)) };
    layer(ctx, cam, 1, c => {
      storeRoom(c, -1800, 3200); shoeShelf(c, 560, 470, 560, 3, 81); rack(c, -700, 640, 500, 82, v); lamp(c, 720, 250);
      person(c, 'yeraly', { x: 800, y: FLOOR, s: 0.88, dir: -1, face: 'smile', hold: v > 3.0 && v < 3.8 ? 'bag' : 'phone', armR: v > 1.7 && v < 2.9 ? 1.25 : v > 3.0 && v < 3.8 ? 1.1 : 0.3 });
      counter(c, 560, 1130, 520);
      const showing = v > 1.6 && v < 3.0;
      const gotBag = v > 3.6;
      person(c, 'madina', { x: mx, y: FLOOR + 4, s: 0.86, dir: 1, walk: (walkIn > 0 && walkIn < 1) || (walkOut > 0 && walkOut < 1) ? u * 11 : 0, moving: (walkIn > 0 && walkIn < 1) || (walkOut > 0 && walkOut < 1), face: gotBag ? 'happy' : 'smile', hold: gotBag ? 'bag' : 'phone', armR: showing ? 1.45 : gotBag ? 0.5 : 0.25 });
      if (showing) {
        const p = E.outBack(seg(v, 1.6, 1.9)) * (1 - E.inC(seg(v, 2.75, 3.0)));
        c.save(); c.translate(480, 800); c.scale(p, p); shadowOn(c, 30, 10, 0.2); fillRR(c, -130, -130, 260, 260, 30, '#fff'); shadowOff(c); qr(c, -100, -100, 200, 12);
        const sy = lerp(-100, 100, (Math.sin((v - 1.9) * 6) + 1) / 2);
        if (v > 1.9 && v < 2.55) { c.fillStyle = 'rgba(242,59,79,0.85)'; c.fillRect(-120, sy - 3, 240, 6); c.fillStyle = 'rgba(242,59,79,0.18)'; c.fillRect(-120, sy - 30, 240, 30); }
        if (v > 2.55) check(c, 0, 0, 70 * E.outBack(seg(v, 2.55, 2.8)), seg(v, 2.55, 2.85));
        c.restore();
      }
      burst(c, 480, 800, v - 2.55, 14, C.green, 21, 230);
      if (v > 3.1) { const p = E.outBack(seg(v, 3.1, 3.4)); c.save(); c.translate(820, 1250); c.scale(p, p); pill(c, 0, 0, '⏱ 10 секунд', { size: 40, bg: C.ink }); c.restore(); }
    });
    headline(ctx, v, 0.2, 5.4, ['QR көрсетті —', '*алып кетті*']);
  }
  const w = seg(u, 3.1, 3.5); wipe(ctx, w, C.green, -0.35);
}

// ── 2 · PROMO (15–20.5) ───────────────────────────────────────────────────
cue2(15.0, 'whoosh', 0.7); cue2(15.4, 'type', 0.8); cue2(16.6, 'tap', 0.8); cue2(16.85, 'whoosh', 0.9);
for (let i = 0; i < 8; i++) cue2(17.4 + i * 0.32, 'coin', 0.45 + i * 0.05);
function promoScreen(c, w, h, u) {
  ui(c, w, c => {
    appBar(c, 'Промокод');
    text(c, 'Код', 24, 170, font(700, 24), C.ink2, 'left');
    fillRR(c, 20, 190, 360, 80, 18, '#fff', C.green, 4);
    const code = 'QOIMA20'; const n = Math.floor(clamp(seg(u, 0.3, 1.1)) * code.length + 0.001);
    text(c, code.slice(0, n) + ((u * 2) % 1 < 0.5 && n < 7 ? '|' : ''), 44, 232, font(900, 38), C.ink, 'left');
    text(c, 'Жеңілдік', 24, 320, font(700, 24), C.ink2, 'left');
    pill(c, 90, 370, '−20%', { size: 34, bg: u > 1.1 ? C.green : C.line, color: u > 1.1 ? '#fff' : C.ink, shadow: false });
    pill(c, 240, 370, '−5000 ₸', { size: 30, bg: C.line, color: C.ink, shadow: false });
    fillRR(c, 20, 470, 360, 84, 42, u > 1.6 ? C.greenDeep : C.green); text(c, u > 1.6 ? 'Жарияланды ✓' : 'Жариялау', 200, 513, font(800, 30), '#fff');
    if (u > 1.55 && u < 2.0) { const p = seg(u, 1.55, 2.0); c.save(); c.globalAlpha = 1 - p; circle(c, 200, 512, 20 + p * 80, null, '#fff', 8); c.restore(); }
  });
}
function sPromo(ctx, u) {
  const pan = E.ioC(seg(u, 1.7, 2.6));
  const cam = { x: lerp(470, 700, pan), y: 980, z: lerp(1.08, 0.98, pan) + u * 0.01, r: lerp(-0.02, 0.02, seg(u, 0, 5.5)) };
  blurLayer(ctx, cam, 0.8, c => { storeRoom(c, -1800, 3000, { wall: '#EAF3EE' }); shoeShelf(c, 700, 470, 600, 3, 91); }, 7);
  layer(ctx, cam, 1, c => {
    c.fillStyle = C.floor; c.fillRect(-1800, FLOOR, 4800, 900);
    person(c, 'owner', { x: 150, y: FLOOR, s: 0.9, face: u > 2.4 ? 'happy' : 'smile', hold: 'phone', armR: 1.0, armL: -0.2 });
    // order counter card + bars
    const cp = spring(u - 2.0, 1.4, 6);
    if (cp > 0) {
      c.save(); c.translate(860, 1040); c.scale(clamp(cp, 0, 1.15), clamp(cp, 0, 1.15));
      shadowOn(c, 40, 16, 0.18); fillRR(c, -230, -260, 460, 520, 34, '#fff'); shadowOff(c);
      text(c, 'Тапсырыстар', 0, -200, font(800, 36), C.ink2);
      const n = Math.round(lerp(3, 27, E.ioQ(seg(u, 2.4, 5.0))));
      text(c, String(n), 0, -110, font(900, 110), C.greenDeep);
      const bars = [0.18, 0.25, 0.22, 0.45, 0.62, 0.8, 1.0];
      bars.forEach((b, i) => { const p = E.outC(seg(u, 2.5 + i * 0.3, 3.0 + i * 0.3)); const bh = 200 * b * p; fillRR(c, -190 + i * 56, 220 - bh, 40, Math.max(1, bh), 8, i > 2 ? C.green : '#cfd8d4'); });
      c.restore();
    }
  });
  // flying notifications to clients
  for (let i = 0; i < 6; i++) {
    const d = u - (1.95 + i * 0.12); if (d < 0 || d > 1.4) continue;
    const p = E.ioC(clamp(d / 1.2));
    const x = lerp(380, 1250, p) + Math.sin(d * 4 + i) * 20, y = lerp(980, 380 + i * 180, p) - Math.sin(p * Math.PI) * 120;
    ctx.save(); ctx.globalAlpha = 1 - seg(d, 1.0, 1.4); ctx.translate(x, y); ctx.rotate(-0.2 + p * 0.3);
    fillRR(ctx, -90, -34, 180, 68, 22, '#fff'); fillRR(ctx, -80, -24, 48, 48, 12, C.green); text(ctx, '−20%', 26, 2, font(900, 28), C.greenDeep);
    ctx.restore();
  }
  const ph = E.ioC(seg(u, 1.8, 2.5));
  phone(ctx, lerp(560, 230, ph), lerp(1000, 1090, ph), lerp(500, 330, ph), lerp(-0.05, -0.12, ph), (c, w, h) => promoScreen(c, w, h, u));
  headline(ctx, u, 0.3, 5.0, ['Промокод —', '*сатылым өседі*']);
}

// ── 3 · REFERRAL (20.5–31) ────────────────────────────────────────────────
cue2(20.5, 'swish', 0.7); cue2(21.3, 'tap', 0.8); cue2(21.6, 'whoosh', 0.8); cue2(21.85, 'whoosh', 0.7); cue2(22.7, 'notif', 0.8); cue2(22.95, 'notif', 0.7); cue2(23.3, 'pop', 0.9);
cue2(24.1, 'whooshUp', 0.7);
for (let i = 0; i < 3; i++) cue2(24.6 + i * 0.12, 'pop', 0.6);
for (let i = 0; i < 9; i++) cue2(25.9 + i * 0.06, 'pop', 0.35);
for (let i = 0; i < 12; i++) cue2(27.2 + i * 0.05, 'pop', 0.25);
cue2(28.4, 'chime', 0.7);
const NET = (() => { // nodes: level, angle, parent
  const nodes = [{ l: 0, a: 0, r: 0, p: -1, k: 'madina' }];
  const kinds = ['aru', 'timur', 'c1', 'c2', 'c3', 'c4'];
  let idx = 0; const R = rng(5);
  [3, 9, 27].forEach((cnt, li) => {
    const level = li + 1; const prevStart = nodes.findIndex(n => n.l === li); const prevCount = nodes.filter(n => n.l === li).length;
    for (let i = 0; i < cnt; i++) {
      const parent = prevStart + Math.floor(i / (cnt / prevCount));
      const a = (i + 0.5) / cnt * Math.PI * 2 + level * 0.3 + (R() - 0.5) * 0.15;
      nodes.push({ l: level, a, r: [0, 230, 430, 640][level], p: parent, k: kinds[(idx++) % kinds.length] });
    }
  });
  return nodes;
})();
function face(c, x, y, r, k) {
  const P = PEOPLE[k]; circle(c, x, y, r + 6, '#fff'); circle(c, x, y, r, P.body);
  c.save(); c.beginPath(); c.arc(x, y, r, 0, 7); c.clip(); c.translate(x, y + r * 0.02); c.scale(r / 98, r / 98);
  head(c, k, P, 68, { face: 'smile' }); c.restore();
}
function sReferral(ctx, u) {
  if (u < 3.5) {
    const cam = { x: 540 + u * 20, y: 990, z: 1.05 + u * 0.02, r: lerp(-0.02, 0.01, seg(u, 0, 3.5)) };
    blurLayer(ctx, cam, 0.8, c => { storeRoom(c, -1800, 3000, { wall: '#F1EBF7' }); }, 6);
    layer(ctx, cam, 1, c => {
      c.fillStyle = '#d9cfe3'; c.fillRect(-1800, FLOOR, 4800, 900);
      person(c, 'madina', { x: 200, y: FLOOR, s: 0.86, face: 'happy', hold: 'phone', armR: 1.15, armL: -0.2 });
      const ding = u > 2.2;
      person(c, 'aru', { x: 720, y: FLOOR - 20, s: 0.78, dir: -1, face: ding ? 'happy' : 'neutral', hold: 'phone', armR: ding ? 1.1 : 0.3 });
      person(c, 'timur', { x: 950, y: FLOOR + 10, s: 0.82, dir: -1, face: ding ? 'happy' : 'neutral', hold: 'phone', armR: ding ? 1.15 : 0.3 });
      // paper planes with code
      [[720, 700, 1.1], [950, 720, 1.35]].forEach(([tx, ty, t0], i) => {
        const d = u - t0; if (d < 0 || d > 1.0) return;
        const p = E.ioC(clamp(d / 0.85)); const x = lerp(330, tx, p), y = lerp(850, ty, p) - Math.sin(p * Math.PI) * 220;
        c.save(); c.translate(x, y); c.rotate(-0.3 + p * 0.6); c.fillStyle = '#fff'; c.beginPath(); c.moveTo(50, 0); c.lineTo(-40, -30); c.lineTo(-20, 0); c.lineTo(-40, 30); c.closePath(); c.fill(); c.strokeStyle = C.green; c.lineWidth = 3; c.stroke(); c.restore();
      });
      if (u > 2.8) { const p = E.outBack(seg(u, 2.8, 3.1)); c.save(); c.translate(600, 560); c.scale(p, p); pill(c, 0, 0, '−10% екеуіне де', { size: 42, bg: C.purple }); c.restore(); }
      if (u > 2.2) { [[720, 840], [950, 820]].forEach(([x, y], i) => { const p = E.outBack(seg(u, 2.2 + i * 0.25, 2.5 + i * 0.25)); c.save(); c.translate(x, y - 90); c.scale(p, p); circle(c, 0, 0, 30, C.red); text(c, '1', 0, 2, font(900, 32), '#fff'); c.restore(); }); }
    });
    // Madina's phone inset
    const ip = E.outBack(seg(u, 0.2, 0.6));
    ctx.save(); ctx.translate(300, 1180); ctx.scale(ip, ip); ctx.rotate(-0.06);
    shadowOn(ctx, 40, 16, 0.22); fillRR(ctx, -230, -120, 460, 240, 34, '#fff'); shadowOff(ctx);
    text(ctx, 'Досыңды шақыр', -200, -70, font(800, 32), C.ink, 'left');
    fillRR(ctx, -200, -36, 250, 70, 16, C.greenTint, C.green, 3); text(ctx, 'MADINA10', -75, 0, font(900, 32), C.greenDeep);
    fillRR(ctx, 66, -36, 136, 70, 35, u > 0.8 ? C.greenDeep : C.green); text(ctx, 'Бөлісу', 134, 0, font(800, 26), '#fff');
    ctx.restore();
    headline(ctx, u, 0.25, 3.2, ['*Досыңды* шақыр']);
  } else {
    const v = u - 3.5;
    const cam = { x: 540, y: 1000, z: lerp(1.6, 0.92, E.ioC(seg(v, 0, 3.2))) + v * 0.01, r: v * 0.025 - 0.05 };
    layer(ctx, cam, 1, c => {
      c.fillStyle = '#F4F1FA'; c.fillRect(-3000, -3000, 7000, 7000);
      const t0s = [0, 0.9, 2.3, 3.6];
      // links
      NET.forEach((n, i) => {
        if (n.p < 0) return; const P = NET[n.p];
        const appear = seg(v, t0s[n.l] + (i % 27) * 0.02, t0s[n.l] + 0.5 + (i % 27) * 0.02); if (appear <= 0) return;
        const px = 540 + Math.cos(P.a) * P.r, py = 1000 + Math.sin(P.a) * P.r, nx = 540 + Math.cos(n.a) * n.r, ny = 1000 + Math.sin(n.a) * n.r;
        c.strokeStyle = n.l === 1 ? C.purple : 'rgba(124,92,252,0.5)'; c.lineWidth = 6 - n.l; c.setLineDash([14, 10]); c.lineDashOffset = -v * 40;
        c.beginPath(); c.moveTo(px, py); c.lineTo(lerp(px, nx, appear), lerp(py, ny, appear)); c.stroke(); c.setLineDash([]);
      });
      NET.forEach((n, i) => {
        const tt = t0s[n.l] + 0.35 + (i % 27) * 0.02; const p = spring(v - tt, 1.6, 6); if (p <= 0 && n.l > 0) return;
        const nx = 540 + Math.cos(n.a) * n.r, ny = 1000 + Math.sin(n.a) * n.r; const r = [80, 56, 40, 28][n.l];
        c.save(); c.translate(nx, ny); const s = n.l === 0 ? 1 : clamp(p, 0, 1.2); c.scale(s, s); face(c, 0, 0, r, n.k);
        if (n.l === 1) pill(c, 0, r + 34, '−10%', { size: 24, pad: 12, bg: C.purple, shadow: false });
        c.restore();
      });
    });
    { const g = ctx.createLinearGradient(0, 0, 0, 660); g.addColorStop(0, 'rgba(244,241,250,1)'); g.addColorStop(0.72, 'rgba(244,241,250,0.96)'); g.addColorStop(1, 'rgba(244,241,250,0)'); ctx.fillStyle = g; ctx.fillRect(0, 0, W, 660); }
    // counters
    const cnt = Math.round(lerp(1, 40, E.ioQ(seg(v, 0.8, 5.0))));
    ctx.save(); const cp = E.outBack(seg(v, 0.6, 1.0)); ctx.translate(540, 570); ctx.scale(cp, cp);
    shadowOn(ctx, 30, 12, 0.18); fillRR(ctx, -300, -70, 600, 140, 40, '#fff'); shadowOff(ctx);
    text(ctx, 'Жаңа клиенттер', -260, 0, font(800, 34), C.ink2, 'left'); text(ctx, '+' + cnt, 260, 0, font(900, 60), C.purple, 'right'); ctx.restore();
    headline(ctx, v, 0.4, 6.6, ['Клиенттер —', '*өздері көбейеді*'], { hcolor: C.purple });
  }
  const w = seg(u, 3.3, 3.7); wipe(ctx, w, C.purple, -0.35);
}

// ── 4 · Q&A + REVIEWS (31–38) ─────────────────────────────────────────────
cue2(31.0, 'whoosh', 0.8); cue2(31.85, 'pop', 0.8); cue2(32.85, 'pop', 0.8);
for (let i = 0; i < 5; i++) cue2(34.0 + i * 0.16, 'tick', 0.5 + i * 0.08);
cue2(34.9, 'ding', 0.8); cue2(35.3, 'pop', 0.6); cue2(35.85, 'pop', 0.6);
function qaScreen(c, w, h, u) {
  ui(c, w, c => {
    const scroll = E.ioC(seg(u, 2.4, 3.0)) * 330;
    c.save(); c.translate(0, -scroll);
    appBar(c, 'Тауар');
    productImg(c, 20, 140, 360, 220, C.blue);
    text(c, 'Кроссовка · 38 000 ₸', 24, 392, font(800, 28), C.ink, 'left');
    text(c, 'Сұрақтар', 24, 450, font(800, 26), C.ink2, 'left');
    const q = E.outBack(seg(u, 0.75, 1.05));
    if (q > 0) { c.save(); c.translate(24, 480); c.scale(q, q); face(c, 26, 30, 22, 'madina'); fillRR(c, 62, 4, 300, 58, 22, '#fff', C.line, 2); text(c, 'Размері кіші емес пе?', 78, 34, font(700, 21), C.ink, 'left'); c.restore(); }
    const a = E.outBack(seg(u, 1.75, 2.05));
    if (a > 0) { c.save(); c.translate(24, 560); c.scale(a, a); fillRR(c, 0, 4, 300, 58, 22, C.green); text(c, 'Жоқ, стандартты. 42 бар ✓', 16, 34, font(700, 21), '#fff', 'left'); c.drawImage(LOGO, 310, 8, 46, 46); c.restore(); }
    text(c, 'Пікірлер', 24, 680, font(800, 26), C.ink2, 'left');
    for (let i = 0; i < 5; i++) { const p = E.outBack(seg(u, 2.95 + i * 0.16, 3.25 + i * 0.16)); star(c, 44 + i * 50, 730, 20 * Math.max(0.6, p), p > 0.1 ? C.amber : C.line); }
    const rv = seg(u, 3.85, 4.2); if (rv > 0) text(c, '4.9', 330, 732, font(900, 40), C.ink, 'center');
    [['Сапасы керемет!', 4.2, 'c1'], ['Тез алдым, рахмет', 4.75, 'timur']].forEach(([s, t0, k], i) => {
      const p = E.outC(seg(u, t0, t0 + 0.35)); if (p <= 0) return;
      c.save(); c.globalAlpha = p; c.translate((1 - p) * 60, 780 + i * 100); appCard(c, 20, 0, 360, 86); face(c, 60, 43, 24, k); text(c, s, 100, 30, font(700, 22), C.ink, 'left');
      for (let j = 0; j < 5; j++) star(c, 110 + j * 26, 62, 10, C.amber); c.restore();
    });
    c.restore();
  });
}
function sQA(ctx, u) {
  const cam = { x: 540 + Math.sin(u * 0.6) * 40, y: 980, z: 1 + u * 0.02, r: lerp(0.02, -0.02, seg(u, 0, 7)) };
  blurLayer(ctx, cam, 0.7, c => { c.fillStyle = '#EAF2FF'; c.fillRect(-3000, -3000, 7000, 7000); const R = rng(3); for (let i = 0; i < 14; i++) { star(c, R() * 1600 - 260, R() * 2200 - 100, 30 + R() * 40, `rgba(255,165,31,${0.15 + R() * 0.2})`); } }, 8);
  blurLayer(ctx, cam, 1.3, c => { person(c, 'madina', { x: -60, y: 2100, s: 1.1, face: 'smile', hold: 'phone', armR: 1.2 }); person(c, 'timur', { x: 1180, y: 2140, s: 1.1, dir: -1, face: 'happy', hold: 'phone', armR: 1.2 }); }, 10);
  const pin = E.outBack(seg(u, 0, 0.5), 1.1);
  phone(ctx, 540, lerp(2400, 1100, pin), 520, lerp(0.3, 0, pin) + Math.sin(u * 0.8) * 0.015, (c, w, h) => qaScreen(c, w, h, u));
  // floating question / star bubbles around phone
  if (u > 0.8 && u < 2.6) bubble(ctx, 200, 700, '?', { size: 60, scale: E.outBack(seg(u, 0.8, 1.1)) * (1 - seg(u, 2.3, 2.6)), bg: C.blue, color: '#fff' });
  if (u > 3.9) { const p = E.outBack(seg(u, 3.9, 4.25)); ctx.save(); ctx.translate(890, 640); ctx.scale(p, p); ctx.rotate(0.1); star(ctx, 0, 0, 80, C.amber); text(ctx, '4.9', 0, 8, font(900, 40), '#fff'); ctx.restore(); }
  headline(ctx, u, 0.3, 6.5, ['Сұрақ · Жауап ·', '*Баға*'], { hcolor: C.blue });
}

// ── 5 · DEMAND (38–45) ────────────────────────────────────────────────────
cue2(38.0, 'whoosh', 0.8);
for (let i = 0; i < 6; i++) cue2(38.6 + i * 0.2, 'pop', 0.4);
cue2(40.9, 'tap', 0.8); cue2(41.35, 'thud', 0.8); cue2(41.55, 'thud', 0.7); cue2(41.75, 'thud', 0.7); cue2(42.25, 'ding', 0.9); cue2(42.8, 'cash', 0.8);
function demandScreen(c, w, h, u) {
  ui(c, w, c => {
    appBar(c, 'Сұраныс');
    const rows = [['Жейде oversize', 48, false, C.purple], ['Ақ кроссовка', 31, false, '#ffffff'], ['Куртка', 22, true, C.amber]];
    rows.forEach((r, i) => {
      const y = 150 + i * 150; appCard(c, 20, y, 360, 130);
      fillRR(c, 36, y + 18, 94, 94, 14, '#EEF4F1'); if (i === 1) sneaker(c, 44, y + 92, 0.85, '#fff'); else { c.fillStyle = r[3]; c.fillRect(58, y + 36, 50, 60); }
      text(c, r[0], 146, y + 40, font(800, 24), C.ink, 'left');
      const hearts = Math.round(r[1] * clamp(seg(u, 0.4, 1.8)));
      text(c, '❤ ' + hearts, 146, y + 80, font(800, 24), C.red, 'left');
      const restocked = i === 0 && u > 4.2;
      const ok = r[2] || restocked;
      const lab = ok ? (restocked ? 'Келді ✓' : 'Бар') : 'Қоймада жоқ';
      pill(c, 300, y + 80, lab, { size: 18, pad: 10, bg: ok ? C.green : C.red, shadow: false, scale: restocked ? E.outBack(seg(u, 4.2, 4.5)) : 1 });
      if (i === 0 && !restocked) { fillRR(c, 250, y + 20, 116, 40, 20, u > 2.9 ? C.greenDeep : C.ink); text(c, 'Әкелу', 308, y + 41, font(800, 20), '#fff'); }
      if (i === 0 && u > 2.85 && u < 3.3) { const p = seg(u, 2.85, 3.3); c.save(); c.globalAlpha = 1 - p; circle(c, 308, y + 40, 16 + p * 50, null, C.green, 6); c.restore(); }
    });
    if (u > 4.8) { const p = E.outBack(seg(u, 4.8, 5.1)); c.save(); c.translate(200, 660); c.scale(p, p); pill(c, 0, 0, '+12 сатылым', { size: 32 }); c.restore(); }
  });
}
function sDemand(ctx, u) {
  const cam = { x: lerp(520, 660, seg(u, 0, 7)), y: 980, z: 1.0 + u * 0.025, r: lerp(-0.02, 0.025, seg(u, 0, 7)) };
  blurLayer(ctx, cam, 0.85, c => { warehouseRoom(c, -1800, 3000); whShelf(c, 640, 470, 560, 860, ['M', 'L', 'XL', 'S'], 101, { highlight: u > 3.6 ? 2 : -1 }); }, 4);
  layer(ctx, cam, 1, c => {
    c.fillStyle = C.whFloor; c.fillRect(-1800, FLOOR, 4800, 900);
    person(c, 'owner', { x: 130, y: FLOOR, s: 0.9, face: u > 4.2 ? 'happy' : 'neutral', hold: 'phone', armR: 1.0, armL: -0.15, look: 1 });
    // boxes dropping onto shelf area floor
    for (let i = 0; i < 3; i++) {
      const tt = u - (3.25 + i * 0.2); if (tt < 0) continue;
      const y = Math.min(200 + tt * tt * 3200, FLOOR - 4 - 0), bx = 760 + i * 150;
      const sq = tt > 0.3 ? 1 + Math.sin((tt - 0.3) * 20) * Math.exp(-(tt - 0.3) * 8) * 0.15 : 1;
      c.save(); c.translate(bx, y); c.scale(1 / sq, sq); box3(c, 0, 0, 130, 100, 'M', C.purple); c.restore();
    }
  });
  // hearts flying from small avatars into phone
  for (let i = 0; i < 10; i++) {
    const d = u - (0.4 + i * 0.14); if (d < 0 || d > 0.9) continue;
    const R = rng(i + 7); const sx = R() > 0.5 ? -60 : 1140, sy = 500 + R() * 1100;
    const p = E.inQ(clamp(d / 0.8));
    ctx.save(); ctx.globalAlpha = 1 - seg(d, 0.7, 0.9); text(ctx, '❤', lerp(sx, 560, p), lerp(sy, 900, p), font(900, 60), C.red); ctx.restore();
  }
  const pin = E.outBack(seg(u, 0.05, 0.5), 1.1);
  phone(ctx, lerp(1500, 600, pin), 1080, 540, lerp(0.3, 0.04, pin), (c, w, h) => demandScreen(c, w, h, u));
  headline(ctx, u, 0.3, 6.5, ['Клиент не қалайды —', '*көресіз*']);
}

// ── 6 · GROWTH (45–52.5) ──────────────────────────────────────────────────
cue2(45.0, 'whoosh', 0.8);
for (let i = 0; i < 7; i++) cue2(45.6 + i * 0.75, 'notif', 0.45);
cue2(48.6, 'cash', 0.6); cue2(52.1, 'whooshUp', 0.9);
function sGrowth(ctx, u) {
  const cam = { x: lerp(200, 1300, E.ioQ(seg(u, 0, 7.5))), y: lerp(1000, 940, seg(u, 0, 7.5)), z: lerp(0.95, 1.08, seg(u, 0, 7.5)), r: lerp(0.03, -0.03, E.ioQ(seg(u, 0, 7.5))) };
  layer(ctx, cam, 0.85, c => {
    storeRoom(c, -1800, 3600);
    // wall growth chart
    c.save(); c.translate(-80, 380); fillRR(c, 0, 0, 1700, 520, 30, 'rgba(255,255,255,0.75)');
    const pts = 12; const prog = E.ioQ(seg(u, 0.2, 6.5));
    c.strokeStyle = C.green; c.lineWidth = 14; c.lineCap = 'round'; c.lineJoin = 'round'; c.beginPath();
    for (let i = 0; i <= pts * prog; i++) { const x = 60 + i * 1580 / pts, y = 460 - Math.pow(i / pts, 1.6) * 380 - Math.sin(i * 1.7) * 18; i === 0 ? c.moveTo(x, y) : c.lineTo(x, y); }
    c.stroke();
    const ix = 60 + pts * prog * 1580 / pts, iy = 460 - Math.pow(prog, 1.6) * 380 - Math.sin(pts * prog * 1.7) * 18; circle(c, ix, iy, 22, C.green); circle(c, ix, iy, 10, '#fff');
    c.restore();
    shoeShelf(c, 1900, 480, 600, 3, 111); rack(c, 2600, 660, 600, 112, u);
  });
  layer(ctx, cam, 1, c => {
    counter(c, 560, 1130, 520);
    person(c, 'c1', { x: 120, y: FLOOR, s: 0.84, face: 'happy', hold: 'bag', armR: 0.4, walk: u * 9, moving: true });
    person(c, 'yeraly', { x: 800, y: FLOOR - 4, s: 0.86, dir: -1, face: 'happy', hold: 'bag', armR: 1.15 });
    person(c, 'c2', { x: 380, y: FLOOR + 6, s: 0.86, face: 'smile', hold: 'phone', armR: 1.2 });
    person(c, 'c3', { x: 1250, y: FLOOR, s: 0.84, face: 'happy', hold: 'phone', armR: 1.1 });
    person(c, 'seller3', { x: 1560, y: FLOOR, s: 0.86, face: 'smile', hold: 'box', boxLabel: 'L', armR: 1.3, armL: -1.2 });
    person(c, 'owner', { x: 1950, y: FLOOR + 10, s: 0.92, dir: -1, face: 'happy', hold: 'cup', armR: 1.25, armL: -0.15 });
  });
  // rising notification pills
  for (let i = 0; i < 7; i++) {
    const d = u - (0.6 + i * 0.75); if (d < 0 || d > 2.2) continue;
    const x = 260 + (i * 271) % 600, y = 1200 - d * 360;
    ctx.save(); ctx.globalAlpha = clamp(d * 6) * (1 - seg(d, 1.6, 2.2)); notif(ctx, x + 120, y, 600, 'Жаңа тапсырыс', ['Жейде · M', 'Кроссовка · 42', 'Куртка · L', 'Кеды · 39'][i % 4], { logo: LOGO, h: 130, scale: 0.8 }); ctx.restore();
  }
  headline(ctx, u, 0.3, 6.8, ['Сауда *өседі*.', 'Жұмыс *жеңілдейді*.']);
  const rise = E.ioC(seg(u, 7.0, 7.5)); if (rise > 0) { ctx.fillStyle = C.green; ctx.fillRect(0, H * (1 - rise), W, H * rise + 2); }
}

// ── master ────────────────────────────────────────────────────────────────
const TL2 = [[0, 6, sIntro2], [6, 15, sPickup], [15, 20.5, sPromo], [20.5, 31, sReferral], [31, 38, sQA], [38, 45, sDemand], [45, 52.5, sGrowth], [52.5, 60, (c, u) => endCard(c, u)]];
cue2(52.5, 'impact', 0.7); cue2(52.8, 'pop', 0.9); cue2(53.35, 'chime', 0.9);
const SCENE = {
  dur: 60, sub: 4,
  cues: CUES2, vo: VO2.map(v => ({ key: VOPFX + 'v2_' + v[0], t: v[1] })),
  draw(ctx, t) {
    ctx.save();
    for (const [a, b, fn] of TL2) { if (t >= a && t < b) { fn(ctx, t - a); break; } }
    if (t >= 60) endCard(ctx, t - 52.5);
    captions(ctx, t, CAPS2, { y: 1540 });
    ctx.restore();
  }
};
