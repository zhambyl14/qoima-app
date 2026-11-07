// usage: node shot.js v t1,t2,... out_prefix [sub]
const {chromium}=require('playwright'); const fs=require('fs');
(async()=>{const [v,ts,pre,sub]=process.argv.slice(2);
const b=await chromium.launch({args:['--allow-file-access-from-files']}); const p=await b.newPage({viewport:{width:1080,height:1920}});
p.on('console',m=>{if(m.type()==='error')console.log('ERR',m.text())}); p.on('pageerror',e=>console.log('PAGEERR',e.message));
await p.goto('file://'+__dirname+'/page.html?v='+v); await p.waitForFunction('window.READY===true',{timeout:20000});
for(const t of ts.split(',')){const d=await p.evaluate(([t,n])=>window.frame(+t,n,0.9),[t,+(sub||1)]); fs.writeFileSync(`${pre}_${t}.jpg`,Buffer.from(d.split(',')[1],'base64'));}
// perf
const t0=Date.now(); for(let i=0;i<20;i++) await p.evaluate(([t])=>window.frame(t,4,0.95),[i/60]); console.log('ms/frame(4sub+jpeg)',(Date.now()-t0)/20);
await b.close();})();
