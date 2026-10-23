import unittest,importlib.util,json,base64
from pathlib import Path
import numpy as np
spec=importlib.util.spec_from_file_location('worker',Path(__file__).parents[2]/'Runtime/Dictation/worker.py');worker=importlib.util.module_from_spec(spec);spec.loader.exec_module(worker)
class ProtocolTests(unittest.TestCase):
 def packet(self,values=None,rate=16000):
  return {'id':'test','rate':rate,'language':None,'pcm':base64.b64encode(np.asarray(values if values is not None else [0.1]*1600,dtype='<f4').tobytes()).decode()}
 def test_backend_is_explicit_and_never_falls_back(self):
  import tempfile
  with tempfile.TemporaryDirectory() as d:
   root=Path(d)
   self.assertEqual(worker.backend_for(root,'whisper-turbo'),'mlx')
   (root/'runtime-backends.json').write_text(json.dumps({'whisper-turbo':'whisper.cpp'}))
   self.assertEqual(worker.backend_for(root,'whisper-turbo'),'whisper.cpp')
   with self.assertRaises(ValueError):worker.backend_for(root,'qwen3-asr')
   (root/'runtime-backends.json').write_text(json.dumps({'whisper-turbo':'cloud'}))
   with self.assertRaises(ValueError):worker.backend_for(root,'whisper-turbo')
 def test_valid(self):
  audio,rate,language,vocabulary=worker.decode_request(self.packet());self.assertEqual(len(audio),1600);self.assertEqual(rate,16000);self.assertIsNone(language);self.assertEqual(vocabulary,[])
 def test_vocabulary_is_trimmed_and_deduplicated(self):
  p=self.packet();p['vocabulary']=[' Saywing ','Böbel','saywing','Owl Frame']
  self.assertEqual(worker.decode_request(p)[3],['Saywing','Böbel','Owl Frame'])
 def test_invalid_vocabulary_is_rejected(self):
  for value in ['Saywing',[1],[''],['a\nb'],['x'*61],['t%d'%i for i in range(51)]]:
   p=self.packet();p['vocabulary']=value
   with self.assertRaises(ValueError):worker.decode_request(p)
 def test_vocabulary_prompt(self):
  self.assertIsNone(worker.vocabulary_prompt([]))
  self.assertEqual(worker.vocabulary_prompt(['Saywing','Owl Frame']),'Saywing, Owl Frame.')
 def test_whisper_prompt_keeps_leading_terms_within_token_budget(self):
  terms=['Term%d'%i for i in range(50)]
  fitted=worker.fit_prompt_terms(terms,lambda text:len(text.split()),10)
  self.assertEqual(fitted,terms[:len(fitted)]);self.assertLessEqual(len(worker.vocabulary_prompt(fitted).split()),10);self.assertGreater(len(fitted),0)
 def test_vocabulary_retries_without_terms_after_a_loop(self):
  calls=[]
  def run(vocabulary):calls.append(vocabulary);return 'Kone, '*30 if vocabulary else 'Vielen Dank.'
  self.assertEqual(worker.recognize_with_vocabulary(run,['Saywing']),'Vielen Dank.');self.assertEqual(calls,[['Saywing'],[]])
 def test_vocabulary_retries_when_the_list_is_echoed(self):
  calls=[]
  def run(vocabulary):calls.append(vocabulary);return 'Saywing, Böbel, Owl Frame.' if vocabulary else ''
  self.assertEqual(worker.recognize_with_vocabulary(run,['Saywing','Böbel','Owl Frame']),'');self.assertEqual(len(calls),2)
 def test_vocabulary_result_is_kept_when_plausible(self):
  calls=[]
  def run(vocabulary):calls.append(vocabulary);return 'Ich habe Saywing installiert.'
  self.assertEqual(worker.recognize_with_vocabulary(run,['Saywing']),'Ich habe Saywing installiert.');self.assertEqual(calls,[['Saywing']])
  self.assertEqual(worker.recognize_with_vocabulary(run,[]),'Ich habe Saywing installiert.');self.assertEqual(calls,[['Saywing'],[]])
 def test_nonfinite(self):
  with self.assertRaises(ValueError):worker.decode_request(self.packet([float('nan')]))
 def test_bad_language(self):
  p=self.packet();p['language']='unknown'
  with self.assertRaises(ValueError):worker.decode_request(p)
 def test_invalid_rate(self):
  with self.assertRaises(ValueError):worker.decode_request(self.packet(rate=0))
 def test_duration_limit(self):
  with self.assertRaises(ValueError):worker.decode_request(self.packet([0.1]*(16000*60+1)))
 def test_zero_input(self):self.assertIsNone(worker.prepare_audio(np.zeros(16000,dtype=np.float32),16000))
 def test_resampling(self):
  a=worker.prepare_audio(np.full(48000,0.1,dtype=np.float32),48000);self.assertEqual(len(a),16000);self.assertAlmostEqual(float(a[8000]),0.1,places=4)
 def test_hash_mismatch(self):
  import tempfile
  with tempfile.TemporaryDirectory() as d:
   p=Path(d);(p/'Model').mkdir();(p/'Model/x').write_bytes(b'x');(p/'model-manifest.json').write_text(json.dumps({'files':[{'rfilename':'x','size':1,'verified_sha256':'bad'}]}))
   with self.assertRaises(ValueError):worker.verify_model(p)
 def test_whisper_manifest_is_selected_without_qwen_fallback(self):
  import tempfile,hashlib
  with tempfile.TemporaryDirectory() as d:
   p=Path(d);(p/'WhisperTurbo').mkdir();(p/'WhisperTurbo/x').write_bytes(b'x')
   manifest={'files':[{'rfilename':'x','size':1,'verified_sha256':hashlib.sha256(b'x').hexdigest()}]}
   (p/'whisper-turbo-manifest.json').write_text(json.dumps(manifest))
   self.assertEqual(worker.verify_model(p,'whisper-turbo'),(p/'WhisperTurbo').resolve())
   with self.assertRaises(FileNotFoundError):worker.verify_model(p,'qwen3-asr')
   with self.assertRaises(ValueError):worker.verify_model(p,'unknown')
 def test_whisper_large_uses_its_own_manifest_and_directory(self):
  import tempfile,hashlib
  with tempfile.TemporaryDirectory() as d:
   p=Path(d);(p/'WhisperLargeV3').mkdir();(p/'WhisperLargeV3/x').write_bytes(b'x')
   (p/'whisper-large-v3-manifest.json').write_text(json.dumps({'files':[{'rfilename':'x','size':1,'verified_sha256':hashlib.sha256(b'x').hexdigest()}]}))
   self.assertEqual(worker.verify_model(p,'whisper-large-v3'),(p/'WhisperLargeV3').resolve())
   with self.assertRaises(FileNotFoundError):worker.verify_model(p,'whisper-turbo')
 def test_installed_model_is_read_from_model_root_with_bundled_manifest(self):
  import tempfile,hashlib
  with tempfile.TemporaryDirectory() as bundle,tempfile.TemporaryDirectory() as installed:
   b=Path(bundle);i=Path(installed);(i/'WhisperLargeV3').mkdir();(i/'WhisperLargeV3/x').write_bytes(b'x')
   (b/'whisper-large-v3-manifest.json').write_text(json.dumps({'files':[{'rfilename':'x','size':1,'verified_sha256':hashlib.sha256(b'x').hexdigest()}]}))
   (i/'whisper-large-v3-manifest.json').write_text(json.dumps({'files':[]}))
   self.assertEqual(worker.verify_model(b,'whisper-large-v3',i),(i/'WhisperLargeV3').resolve())
   (i/'WhisperLargeV3/x').write_bytes(b'y')
   with self.assertRaises(ValueError):worker.verify_model(b,'whisper-large-v3',i)
 def test_model_manifest_cannot_escape_model_directory(self):
  import tempfile,hashlib
  with tempfile.TemporaryDirectory() as d:
   p=Path(d);(p/'WhisperTurbo').mkdir();(p/'outside').write_bytes(b'x')
   (p/'whisper-turbo-manifest.json').write_text(json.dumps({'files':[{'rfilename':'../outside','size':1,'verified_sha256':hashlib.sha256(b'x').hexdigest()}]}))
   with self.assertRaises(ValueError):worker.verify_model(p,'whisper-turbo')
 def whisper_fixture(self,d,files=None):
  import hashlib
  p=Path(d);(p/'WhisperTurbo').mkdir()
  files=files or {'weights.safetensors':b'w','config.json':b'{}'}
  for name,data in files.items():(p/'WhisperTurbo'/name).write_bytes(data)
  manifest={'files':[{'rfilename':'.gitattributes','size':3}]+[{'rfilename':name,'size':len(data),'verified_sha256':hashlib.sha256(data).hexdigest()} for name,data in files.items()]}
  (p/'whisper-turbo-manifest.json').write_text(json.dumps(manifest))
  return p
 def test_unlisted_model_files_are_rejected_because_backends_glob_for_weights(self):
  import tempfile
  for extra in ['extra.safetensors','nested/model.safetensors','LICENSE.safetensors','config 2.json']:
   with tempfile.TemporaryDirectory() as d:
    p=self.whisper_fixture(d)
    target=p/'WhisperTurbo'/extra;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(b'x')
    with self.assertRaises(ValueError,msg=extra):worker.verify_model(p,'whisper-turbo')
 def test_known_metadata_files_beside_the_model_are_ignored(self):
  import tempfile
  with tempfile.TemporaryDirectory() as d:
   p=self.whisper_fixture(d)
   for name in ['.DS_Store','VERIFIED.json','LICENSE-OpenAI','LICENSE-Apache-2.0']:(p/'WhisperTurbo'/name).write_bytes(b'x')
   self.assertEqual(worker.verify_model(p,'whisper-turbo'),(p/'WhisperTurbo').resolve())
 def test_files_changed_between_hashing_and_loading_are_rejected(self):
  import tempfile,os
  with tempfile.TemporaryDirectory() as d:
   p=self.whisper_fixture(d)
   path,identity=worker.verify_model_files(p,'whisper-turbo')
   worker.ensure_unchanged(path,identity)
   (path/'added.safetensors').write_bytes(b'x')
   with self.assertRaises(ValueError):worker.ensure_unchanged(path,identity)
   os.remove(path/'added.safetensors');worker.ensure_unchanged(path,identity)
   # A same-size replacement under the same name is a different file.
   (path/'swap').write_bytes(b'v');os.replace(path/'swap',path/'weights.safetensors')
   with self.assertRaises(ValueError):worker.ensure_unchanged(path,identity)
 def test_load_checks_the_model_again_after_the_backend_has_read_it(self):
  import tempfile
  with tempfile.TemporaryDirectory() as d:
   p=self.whisper_fixture(d)
   original=worker.load_backend
   def tampering(root,backend,model_id,model_path):
    (model_path/'late.safetensors').write_bytes(b'x');return lambda *a:''
   worker.load_backend=tampering
   try:
    with self.assertRaises(ValueError):worker.load_transcriber(p,'whisper-turbo')
   finally:worker.load_backend=original
 def test_only_a_valid_request_id_is_echoed(self):
  self.assertEqual(worker.request_id({'id':'abc'}),'abc')
  for packet in [{'id':[1,2]},{'id':{'x':1}},{'id':'x'*81},{'id':7},['id'],'id',None]:
   self.assertIsNone(worker.request_id(packet))
 def test_worker_loop_answers_malformed_requests_without_echoing_their_content(self):
  import io,sys
  lines=[json.dumps({'id':['secret'],'rate':16000}),json.dumps({'id':'ok','rate':0}),json.dumps(self.packet())]
  stdin=io.TextIOWrapper(io.BytesIO(('\n'.join(lines)+'\n').encode()));stdout=io.StringIO()
  saved=(sys.stdin,sys.stdout,sys.argv,worker.load_transcriber)
  sys.stdin,sys.stdout,sys.argv=stdin,stdout,['worker.py','--model','whisper-turbo']
  worker.load_transcriber=lambda root,model,model_root=None:(lambda audio,language,vocabulary:'Hallo')
  try:self.assertEqual(worker.main(),0)
  finally:sys.stdin,sys.stdout,sys.argv,worker.load_transcriber=saved
  replies=[json.loads(line) for line in stdout.getvalue().splitlines()]
  self.assertEqual([r['type'] for r in replies],['ready','error','error','result'])
  self.assertIsNone(replies[1]['id']);self.assertNotIn('secret',stdout.getvalue())
  self.assertEqual(replies[2]['id'],'ok');self.assertEqual(replies[3],{'type':'result','id':'test','text':'Hallo'})
if __name__=='__main__':unittest.main()
