"""Local PCM pipe worker; no microphone, clipboard, history, or network API."""
import os
os.environ.update(HF_HUB_OFFLINE='1',TRANSFORMERS_OFFLINE='1',HF_HUB_DISABLE_TELEMETRY='1',DO_NOT_TRACK='1',TOKENIZERS_PARALLELISM='false',PYTHONDONTWRITEBYTECODE='1')
import sys,json,base64,hashlib,math,contextlib,signal,unicodedata,zlib
from pathlib import Path
os.environ['TORCHINDUCTOR_CACHE_DIR']=str(Path(__file__).resolve().parent/'RuntimeCache')
MAX_LINE=65*1024*1024
MODELS={'qwen3-asr':('Model','model-manifest.json'),
        'whisper-turbo':('WhisperTurbo','whisper-turbo-manifest.json'),
        'whisper-large-v3':('WhisperLargeV3','whisper-large-v3-manifest.json')}
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

def request_id(packet):
 # Only a valid identifier is echoed; anything else in the request stays inside the worker.
 if isinstance(packet,dict) and isinstance(packet.get('id'),str) and len(packet['id'])<=80:return packet['id']
 return None

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

# Exact names no backend loads: Finder metadata, the legacy packaging receipt and the license
# copy the portable whisper.cpp layout places beside its pinned model.
IGNORED_MODEL_FILES={'.DS_Store','VERIFIED.json','LICENSE-OpenAI','LICENSE-Apache-2.0'}

def file_identity(stat):
 return (stat.st_dev,stat.st_ino,stat.st_size,stat.st_mtime_ns)

def model_identity(model_path):
 # Every file below the model folder; a swapped, changed or added file changes this map.
 found={}
 for directory,_,names in os.walk(model_path):
  for name in names:
   path=Path(directory)/name
   found[path.relative_to(model_path).as_posix()]=file_identity(path.stat())
 return found

def verify_model_files(root,model_id='qwen3-asr',model_root=None):
 # The manifest always comes from the signed bundle; only the files may be installed elsewhere.
 if model_id not in MODELS:raise ValueError('unknown_model')
 directory,manifest_name=MODELS[model_id]
 model_path=((model_root or root)/directory).resolve(strict=True)
 manifest=json.loads((root/manifest_name).read_text())
 # Backends glob for weights, so any unlisted file could be loaded without a hash check.
 listed={entry['rfilename'] for entry in manifest['files']}
 present=model_identity(model_path)
 if any(name not in listed and Path(name).name not in IGNORED_MODEL_FILES for name in present):raise ValueError('model_extra_file')
 for entry in manifest['files']:
  if entry['rfilename']=='.gitattributes':continue
  file=(model_path/entry['rfilename']).resolve(strict=True)
  if not file.is_relative_to(model_path):raise ValueError('model_path')
  with file.open('rb') as f:
   if file_identity(os.fstat(f.fileno()))!=present.get(entry['rfilename']):raise ValueError('model_changed')
   if os.fstat(f.fileno()).st_size!=entry['size']:raise ValueError('model_size')
   digest=hashlib.file_digest(f,'sha256').hexdigest()
  if digest!=entry['verified_sha256']:raise ValueError('model_hash')
 return model_path,present

def verify_model(root,model_id='qwen3-asr',model_root=None):
 return verify_model_files(root,model_id,model_root)[0]

def ensure_unchanged(model_path,identity):
 # Narrows the window between hashing and loading: the loaded files must be the hashed ones.
 if model_identity(model_path)!=identity:raise ValueError('model_changed')

def backend_for(root,model_id):
 config=root/'runtime-backends.json'
 if not config.exists():return 'mlx'
 value=json.loads(config.read_text()).get(model_id)
 if value not in ('mlx','whisper.cpp'):raise ValueError('unsupported_backend')
 return value

class CppTranscriber:
 def __init__(self,root,model_path):
  import ctypes as c
  self.c=c;self.context=None
  self.lib=c.CDLL(str(root/'WhisperCpp/libsaywing-whisper.dylib'))
  self.lib.saywing_whisper_open.argtypes=[c.c_char_p];self.lib.saywing_whisper_open.restype=c.c_void_p
  self.lib.saywing_whisper_close.argtypes=[c.c_void_p];self.lib.saywing_whisper_close.restype=None
  self.lib.saywing_whisper_tokens.argtypes=[c.c_void_p,c.c_char_p];self.lib.saywing_whisper_tokens.restype=c.c_int
  self.lib.saywing_whisper_transcribe.argtypes=[c.c_void_p,c.POINTER(c.c_float),c.c_int,c.c_char_p,c.c_char_p,c.POINTER(c.c_char),c.c_int]
  self.lib.saywing_whisper_transcribe.restype=c.c_int
  models=list(model_path.glob('ggml-*.bin'))
  if len(models)!=1:raise ValueError('expected_one_ggml_model')
  self.context=self.lib.saywing_whisper_open(str(models[0]).encode())
  if not self.context:raise ValueError('cpp_model_load_failed')
 def __del__(self):
  if self.context:self.lib.saywing_whisper_close(self.context);self.context=None
 def __call__(self,audio,language,vocabulary):
  import numpy as np
  c=self.c;audio=np.ascontiguousarray(audio,dtype=np.float32)
  def count(text):
   result=self.lib.saywing_whisper_tokens(self.context,(' '+text).encode())
   if result<0:raise ValueError('tokenization_failed')
   return result
  terms=fit_prompt_terms(vocabulary,count,223)
  def run(terms):
   output=c.create_string_buffer(100001)
   prompt=vocabulary_prompt(terms)
   result=self.lib.saywing_whisper_transcribe(self.context,audio.ctypes.data_as(c.POINTER(c.c_float)),len(audio),
    {None:b'auto','German':b'de','English':b'en'}[language],prompt.encode() if prompt else None,output,len(output))
   if result<0:raise ValueError('cpp_transcription_failed')
   return output.value.decode('utf-8').strip()
  return recognize_with_vocabulary(run,terms)

def load_transcriber(root,model_id,model_root=None):
 backend=backend_for(root,model_id)
 model_path,identity=verify_model_files(root,model_id,model_root)
 recognize=load_backend(root,backend,model_id,model_path)
 ensure_unchanged(model_path,identity)
 return recognize

def load_backend(root,backend,model_id,model_path):
 if backend=='whisper.cpp':return CppTranscriber(root,model_path)
 import mlx.core as mx
 if model_id.startswith('whisper-'):
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
  parser.add_argument('--model-root',type=Path)
  arguments=parser.parse_args();model_id=arguments.model
  model_root=arguments.model_root.resolve(strict=True) if arguments.model_root else None
  with contextlib.redirect_stdout(sys.stderr):
   recognize=load_transcriber(root,model_id,model_root)
  send({'type':'ready','version':1})
 except Exception:
  send({'type':'fatal','code':'load_failed','message':'The model or local runtime could not be loaded.'});return 1
 while True:
  line=sys.stdin.buffer.readline(MAX_LINE+1)
  if not line:return 0
  if len(line)>MAX_LINE:send({'type':'fatal','code':'request_too_large','message':'The recording is too large to process.'});return 1
  identifier=packet=audio=text=None
  try:
   packet=json.loads(line);identifier=request_id(packet)
   audio,rate,language,vocabulary=decode_request(packet)
   with contextlib.redirect_stdout(sys.stderr):
    audio=prepare_audio(audio,rate)
    text='' if audio is None else recognize(audio,language,vocabulary)
   if len(text.encode('utf-8'))>100000:raise ValueError('output_limit')
   send({'type':'result','id':identifier,'text':text})
  except Exception:
   send({'type':'error','id':identifier,'code':'processing_failed','message':'The recording could not be processed. Please try again.'})
  finally:
   # Never keep a user's PCM or text while waiting for the next request, also after a failure.
   packet=audio=text=line=None
if __name__=='__main__':raise SystemExit(main())
