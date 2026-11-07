// node contact.js v t0 t1 step out.jpg [cols]
const {chromium}=require('playwright');
(async()=>{const [v,t0,t1,st,out,cols]=process.argv.slice(2);
const b=await chromium.launch({args:['--allow-file-access-from-files']}); const p=await b.newPage({viewport:{width:1080,height:1920}});
const errs=[]; p.on('pageerror',e=>errs.push(e.message)); p.on('console',m=>{if(m.type()==='error')errs.push(m.text())});
await p.goto('file://'+__dirname+'/page.html?v='+v); await p.waitForFunction('window.READY===true',{timeout:20000});
const ts=[]; for(let t=+t0;t<=+t1+1e-6;t+=+st) ts.push(+t.toFixed(3));
const url=await p.evaluate(async ([ts,cols])=>{
  const c=document.getElementById('c'); const tw=270,th=480; const n=ts.length; const C=+cols||8; const R=Math.ceil(n/C);
  const sheet=document.createElement('canvas'); sheet.width=C*tw; sheet.height=R*(th+30); const sx=sheet.getContext('2d'); sx.fillStyle='#222'; sx.fillRect(0,0,sheet.width,sheet.height);
  ts.forEach((t,i)=>{ try{window.still(t,1);}catch(e){console.error('t='+t+' '+e.message+' '+e.stack.split('\n')[1]);} sx.drawImage(c,(i%C)*tw,Math.floor(i/C)*(th+30),tw,th); sx.fillStyle='#fff'; sx.font='bold 22px sans-serif'; sx.fillText(t.toFixed(2)+'s',(i%C)*tw+8,Math.floor(i/C)*(th+30)+th+24); });
  return sheet.toDataURL('image/jpeg',0.85);},[ts,cols]);
require('fs').writeFileSync(out,Buffer.from(url.split(',')[1],'base64'));
console.log(errs.slice(0,10).join('\n')||'no errors'); await b.close();})();
