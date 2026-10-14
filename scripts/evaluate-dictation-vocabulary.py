"""Measures the dictation vocabulary through the real worker code, offline.

Usage (needs Metal, so run outside a sandbox):
  /abs/Dictation/Python/bin/python3 -I -B scripts/evaluate-dictation-vocabulary.py /abs/Dictation [whisper-turbo|qwen3-asr]

Speech comes from local macOS `say` voices, written to a temporary directory and
deleted afterwards. Synthetic voices are a proxy; confirm with real recordings.
"""
import importlib.util,json,subprocess,sys,tempfile,warnings
from pathlib import Path
import numpy as np
warnings.filterwarnings('ignore')
repo=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('worker',repo/'Runtime/Dictation/worker.py')
worker=importlib.util.module_from_spec(spec);spec.loader.exec_module(worker)
VOCABULARY=['Saywing','Supertonic','Böbel','Qwen','OpenRAIL-M','Owl Frame','Voice Mint','Wojciechowski','Hexaplan','Kubernetes']
SENTENCES={
 's1':('Ich habe Saywing heute auf meinem Mac installiert.',['Saywing']),
 's2':('Das Standardmodell für die Sprachausgabe ist Supertonic.',['Supertonic']),
 's3':('Christopher Böbel hat den Pull Request gemergt.',['Böbel']),
 's4':('Wir vergleichen Qwen mit Whisper Turbo.',['Qwen']),
 's5':('Die Lizenz OpenRAIL-M ist noch ein offener Punkt.',['OpenRAIL-M']),
 's6':('Das Farbschema heißt Owl Frame und Voice Mint.',['Owl Frame','Voice Mint']),
 's7':('Bitte schick die Datei an Frau Wojciechowski.',['Wojciechowski']),
 's8':('Unser Kunde Hexaplan betreibt alles auf Kubernetes.',['Hexaplan','Kubernetes']),
 'c1':('Morgen gehe ich mit meiner Schwester einkaufen.',[]),
 'c2':('Das Wetter in Berlin ist heute ziemlich kalt.',[]),
 'c3':('Kannst du mir bitte die Unterlagen bis Freitag schicken?',[]),
}
VOICES=['Anna','Eddy (Deutsch (Deutschland))','Flo (Deutsch (Deutschland))']

def synthesize(directory):
 from scipy.io import wavfile
 samples={}
 for voice in VOICES:
  for key,(text,_) in SENTENCES.items():
   path=Path(directory)/'sample.wav'
   subprocess.run(['say','-v',voice,'-o',str(path),'--data-format=LEF32@16000',text],check=True)
   rate,audio=wavfile.read(path)
   if rate!=16000 or not len(audio):raise SystemExit('say produced no audio; run outside the sandbox')
   samples[(voice.split()[0],key)]=audio.astype(np.float32)
 for seed in range(5):
  samples[('noise',f'n{seed}')]=(np.random.default_rng(seed).standard_normal(48000)*0.004).astype(np.float32)
 return samples

def main():
 resources=Path(sys.argv[1]).resolve();model=sys.argv[2] if len(sys.argv)>2 else 'whisper-turbo'
 recognize=worker.load_transcriber(resources,model)
 with tempfile.TemporaryDirectory() as directory:samples=synthesize(directory)
 report={}
 for language in (None,'German'):
  runs={name:{key:recognize(audio,language,terms) for key,audio in samples.items()} for name,terms in (('without',[]),('with',VOCABULARY))}
  hits={name:sum(term.casefold() in text.casefold() for (_,key),text in run.items() if key in SENTENCES for term in SENTENCES[key][1]) for name,run in runs.items()}
  total=sum(len(SENTENCES[key][1]) for (_,key) in samples if key in SENTENCES)
  changed=sum(runs['with'][k]!=runs['without'][k] for k in samples if k[1].startswith('c'))
  noise=[runs['with'][k] for k in samples if k[0]=='noise']
  report[str(language)]={'terms_without':f"{hits['without']}/{total}",'terms_with':f"{hits['with']}/{total}",
   'controls_changed':changed,'noise_with_vocabulary':noise,
   'loops_left':sum(worker.looks_degenerate(text,VOCABULARY) for text in noise)}
 print(json.dumps({'model':model,'vocabulary':VOCABULARY,'results':report},ensure_ascii=False,indent=1))

if __name__=='__main__':main()
