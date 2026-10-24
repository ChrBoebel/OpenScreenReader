"""Runs the real bundled model on public samples, with network and writes denied."""
from pathlib import Path
import subprocess,json,select,time,base64,wave,sys,os,signal,re
import numpy as np
res=Path(sys.argv[1]).resolve();root=Path(sys.argv[2]).resolve();root.mkdir(parents=True,exist_ok=True)
python=res/'Python/bin/python3'
model_id=sys.argv[3] if len(sys.argv)>3 else 'qwen3-asr'
# Optional folder of an on-demand installed model; the manifest still comes from the bundle.
model_root=['--model-root',str(Path(sys.argv[4]).resolve(strict=True))] if len(sys.argv)>4 else []
# Same parameters the app passes: canonical runtime, model folder and interpreter paths.
interpreter=Path(os.path.realpath(python))
sandbox=['/usr/bin/sandbox-exec','-f',str(res/'worker.sb'),'-D','RESOURCES='+os.path.realpath(res),
 '-D','MODEL_ROOT='+os.path.realpath(model_root[1] if model_root else res),
 '-D','PYTHON='+str(interpreter),'-D','PYTHON_HOME='+str(interpreter.parent.parent)]
checks=[]
def check(value,name):
 if not value:raise AssertionError(name)
 checks.append(name);print('PASS',name,flush=True)
def read(proc,seconds):
 ready,_,_=select.select([proc.stdout],[],[],seconds)
 if not ready:raise TimeoutError('Worker response timeout')
 line=proc.stdout.readline()
 if not line:raise RuntimeError('Worker exited '+str(proc.poll()))
 return json.loads(line)
def pcm(name):
 import soundfile as sf
 audio,rate=sf.read(res/'Demos'/(name+'.wav'),dtype='float32')
 assert audio.ndim==1
 return audio,rate
def send(proc,id,audio,rate,language=None,vocabulary=None):
 packet={'id':id,'pcm':base64.b64encode(audio.astype('<f4').tobytes()).decode(),'rate':rate,'language':language}
 if vocabulary is not None:packet['vocabulary']=vocabulary
 proc.stdin.write((json.dumps(packet)+'\n').encode());proc.stdin.flush()
# Like the app, start inside the runtime: the profile hides every other folder, even the working directory.
env={'PATH':'/usr/bin:/bin','HOME':str(res),'HF_HUB_OFFLINE':'1','TRANSFORMERS_OFFLINE':'1','PYTHONDONTWRITEBYTECODE':'1'}
p=None
try:
 started=time.monotonic();p=subprocess.Popen(sandbox+[str(python),'-I','-B','-u',str(res/'worker.py'),'--model',model_id]+model_root,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,env=env,cwd=res)
 check(read(p,120).get('type')=='ready','packaged model loads without network or file writes');load=time.monotonic()-started
 de,rate=pcm('Deutsch');en,enrate=pcm('English')
 send(p,'de',np.repeat(de,3),rate*3);d=read(p,90);check(d.get('id')=='de' and 'hongkong' in re.sub(r'\s+', '', d.get('text','')).casefold(),'German through 48 kHz microphone-format pipeline')
 send(p,'en',en,enrate);e=read(p,90);check(e.get('id')=='en' and 'communication' in e.get('text',''),'English through warm model')
 send(p,'de-explicit',de,rate,'German');de_explicit=read(p,90);check('hongkong' in re.sub(r'\s+', '', de_explicit.get('text','')).casefold(),'explicit German transcription')
 send(p,'en-explicit',en,enrate,'English');en_explicit=read(p,90);check('communication' in en_explicit.get('text',''),'explicit English transcription')
 send(p,'vocabulary',de,rate,'German',['Saywing','Böbel','Owl Frame']);v=read(p,90);check(v.get('id')=='vocabulary' and 'hongkong' in re.sub(r'\s+', '', v.get('text','')).casefold(),'vocabulary request keeps the transcript')
 send(p,'bad-vocabulary',de,rate,'German',['a\nb']);b=read(p,10);check(b.get('type')=='error' and b.get('id')=='bad-vocabulary','malformed vocabulary rejected without crashing worker')
 send(p,'silent',np.zeros(32000,dtype=np.float32),16000);s=read(p,90);check(s.get('text')=='','silent input does not create text')
 send(p,'invalid',np.array([np.nan],dtype=np.float32),16000);s=read(p,10);check(s.get('type')=='error','malformed samples rejected without crashing worker')
 send(p,'cancel',np.tile(de,3),rate);time.sleep(.05);t=time.monotonic();p.terminate();p.wait(timeout=2);latency=time.monotonic()-t;check(latency<1,'active inference process cancelled within one second')
 network=subprocess.run(sandbox+[str(python),'-I','-B','-c',"import urllib.request; urllib.request.urlopen('https://huggingface.co',timeout=3)"],capture_output=True,timeout=10,env=env,cwd=res)
 check(network.returncode!=0,'network access denied by worker profile')
 blocked=root/'should-not-exist.tmp'
 write=subprocess.run(sandbox+[str(python),'-I','-B','-c',"open("+repr(str(blocked))+",'w').write('no')"],capture_output=True,timeout=10,env=env,cwd=res)
 check(write.returncode!=0 and not blocked.exists(),'file writes denied by worker profile')
 spawned=subprocess.run(sandbox+[str(python),'-I','-B','-c',"import subprocess; subprocess.run(['/usr/bin/true'],check=True)"],capture_output=True,timeout=10,env=env,cwd=res)
 check(spawned.returncode!=0,'child processes denied by worker profile')
 private=root/'outside-the-runtime.txt';private.write_text('private')
 outside=subprocess.run(sandbox+[str(python),'-I','-B','-c',"print(open("+repr(str(private))+").read())"],capture_output=True,timeout=10,env=env,cwd=res)
 check(outside.returncode!=0 and b'private' not in outside.stdout,'files outside the runtime and model unreadable');private.unlink()
 (root/(model_id+'-worker-integration-result.json')).write_text(json.dumps({'model':model_id,'checks':checks,'load_seconds':load,'cancellation_seconds':latency,'german_text':d['text'],'english_text':e['text']},ensure_ascii=False,indent=2))
finally:
 if p is not None and p.poll() is None:p.kill();p.wait()
