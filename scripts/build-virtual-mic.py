#!/usr/bin/env python3
"""Build a separate GPL-3.0 BlackHole-based development driver. Never installs it."""
import pathlib, re, shutil, subprocess
root = pathlib.Path(__file__).resolve().parents[1]
source = root / '.artifacts' / 'BlackHole'
revision = 'ffcb74433fbcf8c8ca5c736677c1a4864384dc09'
if not source.exists():
    subprocess.run(['git', 'clone', '--no-checkout', 'https://github.com/ExistentialAudio/BlackHole.git', str(source)], check=True)
    subprocess.run(['git', '-C', str(source), 'checkout', '--detach', revision], check=True)
actual = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
if actual != revision:
    raise SystemExit('Driver source is not at the reviewed revision: ' + revision)
cfile = source / 'BlackHole' / 'BlackHole.c'
text = cfile.read_text()
text = re.sub(r'(#define\s+kDriver_Name\s+)"[^"]*"', r'\1"ChupMic"', text)
text = re.sub(r'(#define\s+kPlugIn_BundleID\s+)"[^"]*"', r'\1"com.chup.mic.prototype"', text)
text = re.sub(r'(#define\s+kDevice_Name\s+).*', r'\1"Chup! Mic"', text)
cfile.write_text(text)
out = root / '.artifacts' / 'Driver'
subprocess.run(['xcodebuild','-project',str(source / 'BlackHole.xcodeproj'),'-target','BlackHole',
    '-configuration','Release','ARCHS=arm64','CODE_SIGNING_ALLOWED=NO','MACOSX_DEPLOYMENT_TARGET=15.0',
    'PRODUCT_BUNDLE_IDENTIFIER=com.chup.mic.prototype',
    'CONFIGURATION_BUILD_DIR=' + str(out)], check=True)
built = out / 'BlackHole.driver'
renamed = out / 'ChupMic.driver'
if renamed.exists(): shutil.rmtree(renamed)
shutil.copytree(built, renamed)
shutil.copy2(source / 'LICENSE', out / 'LICENSE-BlackHole.txt')
print('Built separate prototype:', renamed)
print('Not installed. See DriverPrototype/README.md for qualification and licensing.')
