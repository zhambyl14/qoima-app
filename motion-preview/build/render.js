// node render.js v worker nWorkers  -> seg_v_worker.mp4
const {chromium}=require('playwright'); const {spawn}=require('child_process');
(async()=>{const [v,wi,nw]=process.argv.slice(2).map((x,i)=>i?+x:x);
const FPS=60, DUR=60, N=FPS*DUR; const per=Math.ceil(N/nw); const f0=wi*per, f1=Math.min(N,f0+per);
const b=await chromium.launch({args:['--allow-file-access-from-files']}); const p=await b.newPage({viewport:{width:1080,height:1920}});
p.on('pageerror',e=>console.error('PAGEERR',e.message));
await p.goto('file://'+__dirname+'/page.html?v='+v); await p.waitForFunction('window.READY===true',{timeout:30000});
const ff=spawn('ffmpeg',['-y','-v','error','-f','image2pipe','-framerate',String(FPS),'-c:v','mjpeg','-i','-','-c:v','libx264','-preset','medium','-crf','16','-pix_fmt','yuv420p','-r',String(FPS),'-g','120','-bf','2',`seg_${v}_${wi}.mp4`],{stdio:['pipe','inherit','inherit']});
const t0=Date.now();
for(let f=f0;f<f1;f++){const d=await p.evaluate(([t])=>window.frame(t,4,0.95),[f/FPS]);
 const buf=Buffer.from(d.slice(d.indexOf(',')+1),'base64'); if(!ff.stdin.write(buf)) await new Promise(r=>ff.stdin.once('drain',r));
 if((f-f0)%300===0) console.log(`${v}#${wi} frame ${f}/${f1} ${((Date.now()-t0)/1000).toFixed(0)}s`);}
ff.stdin.end(); await new Promise(r=>ff.on('close',r)); await b.close(); console.log(`${v}#${wi} done ${((Date.now()-t0)/1000).toFixed(0)}s`);})();
