"""Local PCM pipe worker; no microphone, clipboard, history, or network API."""
import os
os.environ.update(HF_HUB_OFFLINE='1',TRANSFORMERS_OFFLINE='1',HF_HUB_DISABLE_TELEMETRY='1',DO_NOT_TRACK='1',TOKENIZERS_PARALLELISM='false',PYTHONDONTWRITEBYTECODE='1')
import sys,json,base64,hashlib,math,contextlib,signal
from pathlib import Path
os.environ['TORCHINDUCTOR_CACHE_DIR']=str(Path(__file__).resolve().parent/'RuntimeCache')
MAX_LINE=65*1024*1024
MODELS={'qwen3-asr':('Model','model-manifest.json'),
        'whisper-turbo':('WhisperTurbo','whisper-turbo-manifest.json')}

def decode_request(packet):
 import numpy as np
 if not isinstance(packet,dict) or not isinstance(packet.get('id'),str) or len(packet['id'])>80:raise ValueError('invalid_id')
 language=packet.get('language')
 if language not in (None,'German','English'):raise ValueError('invalid_language')
 rate=packet.get('rate')
 if not isinstance(rate,(float,int)) or not math.isfinite(rate) or not 16000<=rate<=192000 or int(rate)!=rate:raise ValueError('invalid_rate')
 raw=base64.b64decode(packet.get('pcm',''),validate=True)
 if len(raw)%4 or len(raw)<4 or len(raw)>int(rate)*60*4:raise ValueError('invalid_audio_length')
 audio=np.frombuffer(raw,dtype='<f4').copy()
 if not np.isfinite(audio).all() or float(np.max(np.abs(audio)))>1.1:raise ValueError('invalid_samples')
 return audio,int(rate),language

def prepare_audio(audio,rate):
 import numpy as np
 from scipy.signal import resample_poly
 if rate!=16000:
  divisor=math.gcd(rate,16000)
  audio=resample_poly(audio,16000//divisor,rate//divisor).astype(np.float32)
 # Only reject near-zero input; not a claimed full speech/noise classifier.
 if len(audio)<1600 or float(np.sqrt(np.mean(audio**2)))<0.0003:return None
 return audio

def verify_model(root,model_id='qwen3-asr'):
 if model_id not in MODELS:raise ValueError('unknown_model')
 directory,manifest_name=MODELS[model_id]
 model_path=(root/directory).resolve(strict=True)
 manifest=json.loads((root/manifest_name).read_text())
 for entry in manifest['files']:
  if entry['rfilename']=='.gitattributes':continue
  file=(model_path/entry['rfilename']).resolve(strict=True)
  if not file.is_relative_to(model_path):raise ValueError('model_path')
  if file.stat().st_size!=entry['size']:raise ValueError('model_size')
  with file.open('rb') as f:digest=hashlib.file_digest(f,'sha256').hexdigest()
  if digest!=entry['verified_sha256']:raise ValueError('model_hash')
 return model_path

def load_transcriber(root,model_id):
 model_path=verify_model(root,model_id)
 import mlx.core as mx
 if model_id=='whisper-turbo':
  from mlx_whisper.transcribe import ModelHolder,transcribe
  model=ModelHolder.get_model(str(model_path),mx.float16)
  mx.eval(model.parameters());mx.synchronize()
  def recognize(audio,language):
   return transcribe(audio,path_or_hf_repo=str(model_path),
      language={'German':'de','English':'en',None:None}[language],task='transcribe',
      temperature=0.0,condition_on_previous_text=False,word_timestamps=False,
      verbose=None)['text'].strip()
  return recognize
 from mlx_audio.stt.utils import load_model
 model=load_model(model_path,strict=True)
 mx.eval(model.parameters());mx.synchronize()
 return lambda audio,language:model.generate(audio,language=language,max_tokens=1024,verbose=False).text.strip()

def main():
 protocol=sys.stdout
 def send(value):protocol.write(json.dumps(value,ensure_ascii=False)+'\n');protocol.flush()
 root=Path(__file__).resolve().parent
 try:
  import argparse
  parser=argparse.ArgumentParser()
  parser.add_argument('--model',choices=MODELS,default='qwen3-asr')
  model_id=parser.parse_args().model
  with contextlib.redirect_stdout(sys.stderr):
   import mlx.core as mx
   recognize=load_transcriber(root,model_id)
  send({'type':'ready','version':1})
 except Exception:
  send({'type':'fatal','message':'Modell oder lokale Laufzeit konnte nicht geladen werden.'});return 1
 while True:
  line=sys.stdin.buffer.readline(MAX_LINE+1)
  if not line:return 0
  if len(line)>MAX_LINE:send({'type':'fatal','message':'Audioauftrag ist zu groß.'});return 1
  identifier=None
  try:
   packet=json.loads(line);identifier=packet.get('id')
   audio,rate,language=decode_request(packet)
   with contextlib.redirect_stdout(sys.stderr):
    audio=prepare_audio(audio,rate)
    text='' if audio is None else recognize(audio,language)
    mx.synchronize()
   if len(text.encode('utf-8'))>100000:raise ValueError('output_limit')
   send({'type':'result','id':identifier,'text':text})
   del packet,audio,text,line
  except Exception:
   send({'type':'error','id':identifier,'message':'Die Aufnahme konnte nicht verarbeitet werden. Bitte erneut versuchen.'})
if __name__=='__main__':raise SystemExit(main())
