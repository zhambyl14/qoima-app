import json, os, subprocess
HERE=os.path.dirname(os.path.abspath(__file__)); os.makedirs(HERE+'/vo',exist_ok=True)
L=json.load(open(HERE+'/ru_lines.json',encoding='utf8')); env=dict(os.environ,SSL_CERT_FILE='/root/.ccr/ca-bundle.crt')
def dur(p): return float(subprocess.run(['ffprobe','-v','error','-show_entries','format=duration','-of','csv=p=0',p],capture_output=True,text=True).stdout.strip())
out={}
for v,lines in L.items():
  for k,t0,mx,text in lines:
    p=f'{HERE}/vo/ru_{v}_{k}.mp3'
    print('...',v,k,flush=True)
    for rate in (-4,0,4,8,12):
      import time
      for attempt in range(25):
        r=subprocess.run(['edge-tts','--proxy',os.environ['HTTPS_PROXY'],'--voice','ru-RU-DmitryNeural',f'--rate={rate:+d}%','--text',text,'--write-media',p],env=env,capture_output=True,timeout=60)
        if r.returncode==0 and os.path.getsize(p)>2000: break
        time.sleep(5)
      else: raise SystemExit('TTS failed for '+k)
      d=dur(p)
      if d<=mx: break
    print(v,k,f'{d:.2f}s (max {mx}) rate {rate:+d}%', 'OVER!' if d>mx else '',flush=True)
    out[f'{v}_{k}']={'t':t0,'dur':round(d,3),'text':text}
open(HERE+'/ru_vo.js','w',encoding='utf8').write('const RUVO = '+json.dumps(out,ensure_ascii=False)+';\n')
