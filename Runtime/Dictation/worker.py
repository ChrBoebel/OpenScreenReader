"""Local PCM pipe worker; no microphone, clipboard, history, or network API."""
import os
os.environ.update(HF_HUB_OFFLINE='1',TRANSFORMERS_OFFLINE='1',HF_HUB_DISABLE_TELEMETRY='1',DO_NOT_TRACK='1',TOKENIZERS_PARALLELISM='false',PYTHONDONTWRITEBYTECODE='1')
import sys,json,base64,hashlib,math,contextlib,signal,unicodedata,zlib
from pathlib import Path
os.environ['TORCHINDUCTOR_CACHE_DIR']=str(Path(__file__).resolve().parent/'RuntimeCache')
MAX_LINE=65*1024*1024
MODELS={'qwen3-asr':('Model','model-manifest.json'),
        'whisper-turbo':('WhisperTurbo','whisper-turbo-manifest.json')}
MAX_TERMS=50;MAX_TERM_LENGTH=60

def decode_vocabulary(value):
 if value is None:return []
 if not isinstance(value,list) or len(value)>MAX_TERMS:raise ValueError('invalid_vocabulary')
 terms,seen=[],set()
 for item in value:
  if not isinstance(item,str):raise ValueError('invalid_vocabulary')
  term=item.strip()
  if not term or len(term)>MAX_TERM_LENGTH or any(unicodedata.category(c) in ('Cc','Cf') for c in term):raise ValueError('invalid_vocabulary')
  if term.casefold() not in seen:seen.add(term.casefold());terms.append(term)
 return terms

def vocabulary_prompt(terms):
 # A plain list with a final period kept punctuation intact; a 'Glossar:' label leaked into output.
 return ', '.join(terms)+'.' if terms else None

def fit_prompt_terms(terms,count_tokens,budget):
 # Whisper keeps only the last prompt tokens; drop trailing terms instead of the first ones.
 terms=list(terms)
 while terms and count_tokens(vocabulary_prompt(terms))>budget:terms.pop()
 return terms

def looks_degenerate(text,terms):
 raw=text.encode('utf-8')
 if len(raw)>40 and len(raw)/len(zlib.compress(raw))>2.4:return True
 parts=[part.strip(' .!?') for part in text.replace(';',',').split(',')]
 known={term.casefold() for term in terms}
 return len(parts)>2 and all(part.casefold() in known for part in parts)

def recognize_with_vocabulary(run,terms):
 # A prompt can turn noise into a loop or an echo of the list; decode once more without it.
 text=run(terms)
 if terms and looks_degenerate(text,terms):text=run([])
 return text

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
 return audio,int(rate),language,decode_vocabulary(packet.get('vocabulary'))

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
  from mlx_whisper.tokenizer import get_tokenizer
  model=ModelHolder.get_model(str(model_path),mx.float16)
  mx.eval(model.parameters());mx.synchronize()
  tokenizer=get_tokenizer(model.is_multilingual,num_languages=model.num_languages,task='transcribe')
  budget=model.dims.n_text_ctx//2-1
  def recognize(audio,language,vocabulary):
   terms=fit_prompt_terms(vocabulary,lambda text:len(tokenizer.encode(' '+text)),budget)
   def run(terms):
    return transcribe(audio,path_or_hf_repo=str(model_path),
       language={'German':'de','English':'en',None:None}[language],task='transcribe',
       temperature=0.0,condition_on_previous_text=False,word_timestamps=False,
       initial_prompt=vocabulary_prompt(terms),verbose=None)['text'].strip()
   return recognize_with_vocabulary(run,terms)
  return recognize
 from mlx_audio.stt.utils import load_model
 model=load_model(model_path,strict=True)
 mx.eval(model.parameters());mx.synchronize()
 def recognize(audio,language,vocabulary):
  run=lambda terms:model.generate(audio,language=language,max_tokens=1024,verbose=False,hotwords=terms or None).text.strip()
  return recognize_with_vocabulary(run,vocabulary)
 return recognize

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
  send({'type':'fatal','code':'load_failed','message':'The model or local runtime could not be loaded.'});return 1
 while True:
  line=sys.stdin.buffer.readline(MAX_LINE+1)
  if not line:return 0
  if len(line)>MAX_LINE:send({'type':'fatal','code':'request_too_large','message':'The recording is too large to process.'});return 1
  identifier=None
  try:
   packet=json.loads(line);identifier=packet.get('id')
   audio,rate,language,vocabulary=decode_request(packet)
   with contextlib.redirect_stdout(sys.stderr):
    audio=prepare_audio(audio,rate)
    text='' if audio is None else recognize(audio,language,vocabulary)
    mx.synchronize()
   if len(text.encode('utf-8'))>100000:raise ValueError('output_limit')
   send({'type':'result','id':identifier,'text':text})
   del packet,audio,text,line
  except Exception:
   send({'type':'error','id':identifier,'code':'processing_failed','message':'The recording could not be processed. Please try again.'})
if __name__=='__main__':raise SystemExit(main())
