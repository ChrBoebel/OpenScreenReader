import unittest,importlib.util,json,base64
from pathlib import Path
import numpy as np
spec=importlib.util.spec_from_file_location('worker',Path(__file__).parents[2]/'Runtime/Dictation/worker.py');worker=importlib.util.module_from_spec(spec);spec.loader.exec_module(worker)
class ProtocolTests(unittest.TestCase):
 def packet(self,values=None,rate=16000):
  return {'id':'test','rate':rate,'language':None,'pcm':base64.b64encode(np.asarray(values if values is not None else [0.1]*1600,dtype='<f4').tobytes()).decode()}
 def test_valid(self):
  audio,rate,language,vocabulary=worker.decode_request(self.packet());self.assertEqual(len(audio),1600);self.assertEqual(rate,16000);self.assertIsNone(language);self.assertEqual(vocabulary,[])
 def test_vocabulary_is_trimmed_and_deduplicated(self):
  p=self.packet();p['vocabulary']=[' Saywing ','Böbel','saywing','Owl Frame']
  self.assertEqual(worker.decode_request(p)[3],['Saywing','Böbel','Owl Frame'])
 def test_invalid_vocabulary_is_rejected(self):
  for value in ['Saywing',[1],[''],['a\nb'],['x'*61],['t%d'%i for i in range(51)]]:
   p=self.packet();p['vocabulary']=value
   with self.assertRaises(ValueError):worker.decode_request(p)
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
 def test_model_manifest_cannot_escape_model_directory(self):
  import tempfile,hashlib
  with tempfile.TemporaryDirectory() as d:
   p=Path(d);(p/'WhisperTurbo').mkdir();(p/'outside').write_bytes(b'x')
   (p/'whisper-turbo-manifest.json').write_text(json.dumps({'files':[{'rfilename':'../outside','size':1,'verified_sha256':hashlib.sha256(b'x').hexdigest()}]}))
   with self.assertRaises(ValueError):worker.verify_model(p,'whisper-turbo')
if __name__=='__main__':unittest.main()
