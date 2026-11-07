// shared scene pieces for both videos
'use strict';
const FLOOR = 1350;

function storeRoom(ctx, x0, x1, opt = {}) {
  // wall
  ctx.fillStyle = opt.wall || C.wall; ctx.fillRect(x0, -1400, x1 - x0, FLOOR + 1400);
  // wainscot stripe
  ctx.fillStyle = 'rgba(0,168,98,0.10)'; ctx.fillRect(x0, 1060, x1 - x0, 290);
  ctx.fillStyle = 'rgba(0,113,63,0.18)'; ctx.fillRect(x0, 1052, x1 - x0, 10);
  // floor
  const g = ctx.createLinearGradient(0, FLOOR, 0, FLOOR + 700);
  g.addColorStop(0, opt.floor || C.floor); g.addColorStop(1, '#c7b79d');
  ctx.fillStyle = g; ctx.fillRect(x0, FLOOR, x1 - x0, 1400);
  ctx.strokeStyle = 'rgba(0,0,0,0.05)'; ctx.lineWidth = 4;
  for (let x = Math.floor(x0 / 180) * 180; x < x1; x += 180) { ctx.beginPath(); ctx.moveTo(x, FLOOR); ctx.lineTo(x - 260, FLOOR + 700); ctx.stroke(); }
}
function warehouseRoom(ctx, x0, x1) {
  ctx.fillStyle = C.whWall; ctx.fillRect(x0, -1400, x1 - x0, FLOOR + 1400);
  ctx.fillStyle = 'rgba(0,0,0,0.05)';
  for (let x = x0; x < x1; x += 120) ctx.fillRect(x, -1400, 6, FLOOR + 1400);
  ctx.fillStyle = C.whFloor; ctx.fillRect(x0, FLOOR, x1 - x0, 1400);
  ctx.fillStyle = '#FFD23F'; for (let x = x0 + 40; x < x1; x += 160) ctx.fillRect(x, FLOOR + 90, 80, 14);
}
function lamp(ctx, x, y, on = 1) {
  ctx.strokeStyle = '#555'; ctx.lineWidth = 4; ctx.beginPath(); ctx.moveTo(x, y - 400); ctx.lineTo(x, y); ctx.stroke();
  ctx.fillStyle = '#2b2f3a'; ctx.beginPath(); ctx.moveTo(x - 60, y + 40); ctx.lineTo(x - 24, y); ctx.lineTo(x + 24, y); ctx.lineTo(x + 60, y + 40); ctx.fill();
  if (on) { const g = ctx.createRadialGradient(x, y + 40, 10, x, y + 300, 420); g.addColorStop(0, 'rgba(255,230,170,0.35)'); g.addColorStop(1, 'rgba(255,230,170,0)'); ctx.fillStyle = g; ctx.beginPath(); ctx.moveTo(x - 60, y + 40); ctx.lineTo(x + 60, y + 40); ctx.lineTo(x + 380, y + 900); ctx.lineTo(x - 380, y + 900); ctx.fill(); }
}
function plant(ctx, x, y, s = 1) {
  ctx.save(); ctx.translate(x, y); ctx.scale(s, s);
  ctx.fillStyle = '#2f8f5b';
  for (let i = 0; i < 7; i++) { ctx.save(); ctx.rotate(-1.1 + i * 0.37); ctx.beginPath(); ctx.ellipse(0, -150, 34, 140, 0, 0, 7); ctx.fill(); ctx.restore(); }
  fillRR(ctx, -70, -60, 140, 120, 18, '#e9e2d6', '#cdbfa8', 4);
  ctx.restore();
}
// screen-space wipe band. p: 0..1 (0.5 = fully covered)
function wipe(ctx, p, col = C.green, ang = -0.35, col2) {
  if (p <= 0 || p >= 1) return;
  ctx.save(); ctx.translate(W / 2, H / 2); ctx.rotate(ang);
  const span = 3400, w = 2600;
  const x = lerp(-span, span, E.ioC(p));
  ctx.fillStyle = col; ctx.fillRect(x - w / 2, -2200, w, 4400);
  if (col2) { ctx.fillStyle = col2; ctx.fillRect(x - w / 2 - 120, -2200, 120, 4400); ctx.fillRect(x + w / 2, -2200, 120, 4400); }
  ctx.restore();
}
function grade(ctx, warm = 0) {
  if (warm <= 0) return;
  ctx.save(); ctx.globalCompositeOperation = 'saturation'; ctx.fillStyle = `rgba(128,128,128,${0.45 * warm})`; ctx.fillRect(0, 0, W, H); ctx.restore();
  ctx.save(); ctx.globalAlpha = 0.08 * warm; ctx.fillStyle = '#7a2f2f'; ctx.fillRect(0, 0, W, H); ctx.restore();
}
function endCard(ctx, u, cues) {
  // u: local time
  const g = ctx.createLinearGradient(0, 0, 0, H); g.addColorStop(0, '#00B56A'); g.addColorStop(1, C.greenDeep);
  ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
  const settle = E.outC(seg(u, 0, 2.2));
  // drifting sneaker pattern (depth)
  for (let i = 0; i < 14; i++) {
    const R = rng(i + 40); const d = 0.3 + R() * 0.7;
    const x = (R() * 1400 - 160) + Math.sin(u * 0.6 + i) * 18 * d - settle * 60 * d;
    const y = (R() * 2100 - 90) - u * 22 * d;
    ctx.save(); ctx.globalAlpha = 0.10 * d; ctx.translate(x, y); ctx.rotate(R() * 0.6 - 0.3);
    const s = 120 + d * 160; ctx.drawImage(LOGOW, -s / 2, -s / 2, s, s); ctx.restore();
  }
  // logo tile
  const ls = spring(u - 0.15, 1.3, 5);
  ctx.save(); ctx.translate(W / 2, 700); ctx.scale(ls, ls); ctx.rotate((1 - clamp(ls)) * -0.4);
  shadowOn(ctx, 70, 30, 0.35); fillRR(ctx, -170, -170, 340, 340, 80, '#fff'); shadowOff(ctx);
  ctx.save(); rr(ctx, -150, -150, 300, 300, 66); ctx.clip(); ctx.drawImage(LOGO, -150, -150, 300, 300); ctx.restore();
  ctx.restore();
  // wordmark
  const wm = spring(u - 0.45, 1.4, 6);
  ctx.save(); ctx.globalAlpha = clamp((u - 0.45) * 5); ctx.translate(W / 2, 1000 + (1 - wm) * 80);
  text(ctx, 'Qoima', 0, 0, font(900, 150), '#fff'); ctx.restore();
  headline(ctx, u, 0.85, 99, ['*Qoima-ны* тегін', 'қолданып көріңіз!'], { y: 1230, size: 84, color: '#fff', hcolor: '#fff', htext: C.greenDeep, rot: 0.1 });
  // underline sparkle
  const sp = seg(u, 1.6, 2.3);
  if (sp > 0 && sp < 1) burst(ctx, W / 2 + 330, 1200, sp * 1.1, 10, '#fff', 3, 160);
}
