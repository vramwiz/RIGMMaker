"""Read-only static checks and isolated numerical contracts; does not execute Delphi or launch apps."""
from pathlib import Path
import hashlib,json,re,math,struct,tempfile,wave,copy,unittest

ROOT=Path(__file__).resolve().parents[3]
AUDIO=ROOT/'Source/Studio/Audio'
def read(name):return (AUDIO/name).read_text(encoding='utf-8-sig')
NAMES=['Delay','Eq','Compressor','VoiceDrive','Distortion','Noise','BitCrusher','Tremble','Wobble','Pitch','RingMod','Muffle','Whisper','AutoGain','NoiseGate','Ghost','Chorus','Reverb','Output','Limiter']
def defaults():
 return {k:float(v) for k,v in re.findall(r"if Name='([^']+)' then Exit\(([-0-9.]+)\)",read('RigmVoiceEffectDefaults.inc'))}
def catalog():
 text=read('RigmAul2EffectDefinition.pas');items={}
 for k in re.findall(r"SetEffectBase\(Definition, '[^']+', '[^']+', '([^']+)'",text):items[k]=(0,1,'integer')
 for k,vals in re.findall(r"SetSelect\(Definition, '[^']+', '([^']+)',\s*\[([^]]+)\]\)",text):items[k]=(0,len(re.findall("'[^']*'",vals))-1,'integer')
 for k,a,b in re.findall(r"SetVolume\(Definition, \d+, '[^']+', '([^']+)', ([^,]+), ([^,]+),",text):items[k]=(float(a),float(b),'number')
 return items
def validate(pairs):
 cat=catalog();seen=set()
 for k,v in pairs:
  if k in seen or k not in cat or type(v) not in (int,float) or not math.isfinite(v):raise ValueError(k)
  seen.add(k);a,b,kind=cat[k]
  if not a<=v<=b or kind=='integer' and int(v)!=v:raise ValueError(k)
def stamp(pairs):
 validate(pairs);d=defaults();d.update(dict(pairs));return hashlib.sha256(json.dumps(sorted(d.items())).encode()).hexdigest()
def delay_contract(samples,delay,dry,wet,feedback):
 ring=[0.]*delay;pos=0;out=[]
 for x in samples:
  old=ring[pos];ring[pos]=x+old*feedback;out.append(x*dry+old*wet);pos=(pos+1)%delay
 return out

class EffectsChecks(unittest.TestCase):
 def test_catalog_defaults_registry(self):
  cat=catalog();d=defaults();self.assertEqual(len(cat),100);self.assertEqual(set(cat),set(d));validate(list(d.items()))
  keys=set()
  for name in NAMES:
   keys.update(re.findall(r"Add(?:Check|Track|Select)\([^,]+, '([^']+)'",read('RigmAul2'+name+'.pas')))
  self.assertEqual(set(cat),keys)
 def test_reject_invalid_and_duplicates(self):
  for p in [[('Out: Use',1),('Out: Use',0)],[('Out: Gain(dB)',25)],[('Out: Use',.5)],[('Out: Gain(dB)',float('nan'))],[('x',1)],[('Out: Use',True)],[('Pitch: Mode',4)]]:
   with self.assertRaises(ValueError):validate(p)
 def test_canonical_stamp_and_cue_isolation(self):
  self.assertEqual(stamp([]),stamp(list(defaults().items())))
  self.assertEqual(stamp([('Out: Use',1),('Out: Gain(dB)',-3)]),stamp([('Out: Gain(dB)',-3),('Out: Use',1)]))
  original={'cue-a':{},'cue-b':{}};saved=copy.deepcopy(original);saved['cue-a']['Out: Use']=1
  self.assertEqual(original,{'cue-a':{},'cue-b':{}});self.assertEqual(saved['cue-b'],{})
  self.assertNotEqual(stamp(saved['cue-a'].items()),stamp(saved['cue-b'].items()))
 def test_dsp_chain_and_adapter(self):
  dsp=read('RigmVoiceEffectsDsp.pas');self.assertEqual(re.findall(r'Process(\w+)\(@A,Buffer.Count,1\)',dsp),NAMES)
  self.assertEqual([n for n in re.findall(r'ResetCopied(\w+);',dsp) if n!='Chain'],NAMES)
  for token in ['TMonitor.Enter(EffectLock)','ResetCopiedChain; BeginCopiedSettings','ResetCopiedChain; TMonitor.Exit(EffectLock)','Samples := Copy(Samples)','O.SampleIndex := Position','Assigned(Cancel) and Cancel()']:self.assertIn(token,dsp)
  fields=set(re.findall(r'ObjectInfo\^\.(\w+)|Object_\^\.(\w+)', '\n'.join(read('RigmAul2'+n+'.pas') for n in NAMES)))
  for a,b in fields:self.assertIn(a or b,{'ID','EffectID','SampleIndex','SampleNum','ChannelNum','Frame','FrameS','FrameE','Layer'})
  for n in NAMES:self.assertNotRegex(read('RigmAul2'+n+'.pas'),r'TAudio\w+Data|Aul2Audio\w+Shared|ControllerGraphRequested|(?:Capture|Publish)\w+\(')
 def test_copy_provenance_and_encoding(self):
  m=json.loads((AUDIO/'AUL2-COPY-PROVENANCE.json').read_text(encoding='utf-8'));self.assertEqual(len(m['files']),24)
  for f in m['files']:
   p=Path(f['source'])
   if p.exists():self.assertEqual(hashlib.sha256(p.read_bytes()).hexdigest(),f['sourceSha256'])
  fs=list(AUDIO.glob('RigmAul2*.pas'))+list(AUDIO.glob('RigmVoiceEffect*.pas'))+[AUDIO/'RigmVoiceEffectDefaults.inc',ROOT/'Source/Shell/Pages/RigmScriptVoiceEffectsFrame.pas']
  for p in fs:
   data=p.read_bytes();self.assertTrue(data.startswith(b'\xef\xbb\xbf'),p);self.assertNotIn(b'\n',data.replace(b'\r\n',b''),p)
 def test_model_mix_and_preview_contracts(self):
  model=(ROOT/'Source/Studio/Model/RigmMovieModel.pas').read_text(encoding='utf-8-sig');mix=read('RigmMovieAudio.pas')
  for k in ['AudioEffects.Free',"'audioEffects'","'effectWaveFile'",'ValidateVoiceEffectSettings(C.AudioEffects)']:self.assertIn(k,model)
  self.assertIn('CueVoiceEffectsStamp(C)',mix);self.assertIn('ApplyCueVoiceEffects(C,Source.Rate,Source.Samples)',mix)
  frame=(ROOT/'Source/Shell/Pages/RigmScriptVoiceEffectsFrame.pas').read_text(encoding='utf-8-sig');worker=read('RigmVoiceEffectsPreview.pas')
  for k in ['CommitPendingValue','FRetired.Count>0','Job.Key=CueEffectPreviewKey(P,C)','FVoiceSourceKey<>CueEffectSourceStamp','FWorkspace.NotifyVoiceEffectsPreview','FLoop or (FJob<>nil)']:self.assertIn(k,frame)
  for k in ['FProject := Project.Clone','fmShareDenyWrite','CREATE_NEW','TRigmPcm.Load(Path)','FKey<>CueEffectPreviewKey(FProject,Cue)']:self.assertIn(k,worker)
  self.assertNotIn('Synchronize(',worker);self.assertNotIn('Queue(',worker)
 def test_isolated_pcm_contract_original_preserved(self):
  # Numerical contract for copied ring-delay and output gain; actual Pascal DSP is not executed.
  x=[.5,0,0,0,0,0,0,0];y=delay_contract(x,2,1,.5,.5)
  self.assertEqual(y,[.5,0,.25,0,.125,0,.0625,0]);self.assertEqual(delay_contract([0]*8,2,1,.5,.5),[0]*8)
  gain=10**(-6/20);self.assertAlmostEqual(.5*gain,.2505936168,9)
  with tempfile.TemporaryDirectory(prefix='rigm-effects-fixture-') as folder:
   src=Path(folder)/'source.wav';dst=Path(folder)/'derived.wav'
   def save(p,s):
    with wave.open(str(p),'wb') as w:w.setnchannels(1);w.setsampwidth(2);w.setframerate(48000);w.writeframes(struct.pack('<'+'h'*len(s),*[max(-32768,min(32767,round(v*32768))) for v in s]))
   save(src,x);before=src.read_bytes();save(dst,y);self.assertEqual(src.read_bytes(),before)
   self.assertNotEqual(src.read_bytes(),dst.read_bytes())
   with wave.open(str(dst),'rb') as w:self.assertEqual(w.getnframes(),len(x))

if __name__=='__main__':unittest.main(verbosity=2)
