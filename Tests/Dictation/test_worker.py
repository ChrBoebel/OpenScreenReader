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
if __name__=='__main__':unittest.main()
