const SCENE = { dur: 2, draw(ctx, t) {
  ctx.fillStyle = C.wall; ctx.fillRect(0,0,W,H);
  const cam = {x: 540 + t*300, y: 960, z: 1 + t*0.1, r: 0.02};
  blurLayer(ctx, cam, 0.6, c => { rack(c, -200, 700, 900, 2, t*3); door(c, 900, 760, 220, 520, 0, 'ҚОЙМА'); }, 8);
  layer(ctx, cam, 1, c => {
    c.fillStyle = C.floor; c.fillRect(-2000, 1300, 6000, 1200);
    person(c, 'owner', {x: 300, y: 1350, s: 0.85, face: 'smile', hold: 'phone', armR: 0.9});
    person(c, 'yeraly', {x: 650 + t*300, y: 1350, s: 0.85, walk: t*14, run: 1, hold: 'box', armR: 1.2});
    person(c, 'sly', {x: 980, y: 1350, s: 0.85, face: 'sly', hold: 'money', look: 1});
    person(c, 'madina', {x: 1250, y: 1350, s: 0.85, face: 'worried', hold:'phone', armR:0.8});
  });
  headline(ctx, t, 0.1, 5, ['Қойма қосылса —', 'дүкенде не *өзгереді?*']);
  captions(ctx, t, [{t0:0,t1:3,s:'Қойма қосылса, дүкеніңізде не өзгереді? Көрейік.'}]);
  phone(ctx, 860, 1200, 220, 0.1, (c,w,h)=>ui(c,w,(c)=>{appBar(c,'Қойма'); appCard(c,20,150,360,140); text(c,'Кроссовка · 42',40,200,font(800,28),C.ink,'left'); pill(c,300,250,'B-3',{size:22});}));
  notif(ctx, 540, 260+700, 900, 'Жаңа сатылым', 'Кроссовка · 42 · 38 000 ₸', {logo: LOGO, time:'қазір'});
}};
