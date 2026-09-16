#!/usr/bin/env python3
"""Generate local synthetic speech fixtures without playing or recording audio."""
import pathlib, subprocess, wave
root=pathlib.Path(__file__).resolve().parents[1]/'.artifacts/provider-fixtures'
root.mkdir(parents=True,exist_ok=True)
phrases=[('en','Samantha','We decided not to launch on Friday. We need to test three USB microphones.'),('nl','Xander','We hebben besloten om vrijdag niet te lanceren. We moeten drie USB microfoons testen.')]
for language,voice,text in phrases:
    subprocess.run(['/usr/bin/say','-v',voice,'-o',str(root/(language+'.wav')),'--file-format=WAVE','--data-format=LEI16@24000',text],check=True)
with wave.open(str(root/'speakers.wav'),'wb') as output:
    output.setnchannels(1);output.setsampwidth(2);output.setframerate(24000)
    for language,_,_ in phrases:
        with wave.open(str(root/(language+'.wav')),'rb') as source:
            assert source.getframerate()==24000 and source.getnchannels()==1
            pcm=source.readframes(source.getnframes());output.writeframes(pcm)
            (root/(language+'.pcm')).write_bytes(pcm)
        output.writeframes(bytes(24000))
print('Prepared English/Dutch synthetic speech and two-voice WAV. No microphone or speakers opened.')
