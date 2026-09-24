#!/usr/bin/env python3
"""Create a signed Developer ID DMG. Notarize only with an explicitly supplied Keychain profile."""
import argparse
import hashlib
import json
import pathlib
import plistlib
import shutil
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
# Only release builds carry the updater feed and the public half of the EdDSA
# key that signs it (~/Desktop/chup-updater-key); local installs never self-update.
FEED = 'https://github.com/Kunba-Labs/chup/releases/latest/download/appcast.xml'
PUBLIC_ED_KEY = '0ZjXQFugKOwQMsEa/AsRzZfYOzwqIBqpQj9KCuJI1EI='

def run(*args, **kwargs):
    return subprocess.run([str(a) for a in args], cwd=ROOT, check=True, **kwargs)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--identity', required=True, help='Developer ID Application identity name or SHA-1')
    parser.add_argument('--notary-profile', help='Existing notarytool Keychain profile; authorizes upload to Apple')
    parser.add_argument('--build', type=int, help='Build number (CFBundleVersion); CI passes the commit count')
    args = parser.parse_args()
    output = ROOT / '.artifacts/Distribution'
    output.mkdir(parents=True, exist_ok=True)
    run('xcodegen', 'generate')
    with (output / 'release-build.log').open('w') as log:
        run('xcodebuild', '-project', 'Chup.xcodeproj', '-scheme', 'Chup', '-configuration', 'Release',
            '-destination', 'platform=macOS,arch=arm64', '-derivedDataPath', '.artifacts/ReleaseDerivedData',
            'CODE_SIGNING_ALLOWED=NO', *([f'CURRENT_PROJECT_VERSION={args.build}'] if args.build else []),
            'build', stdout=log, stderr=subprocess.STDOUT)
    source = ROOT / '.artifacts/ReleaseDerivedData/Build/Products/Release/Chup!.app'
    metadata = plistlib.loads((source / 'Contents/Info.plist').read_bytes())
    version = metadata['CFBundleShortVersionString'] + '-' + metadata['CFBundleVersion']
    dmg = output / ('Chup-' + version + '-arm64.dmg')
    if dmg.exists():
        raise RuntimeError('Versioned DMG already exists. Use a new build number or archive the previous artifact.')
    with tempfile.TemporaryDirectory(prefix='chup-package-') as folder:
        stage = pathlib.Path(folder)
        app = stage / 'Chup!.app'
        run('ditto', source, app)
        plist = app / 'Contents/Info.plist'
        values = plistlib.loads(plist.read_bytes())
        values.update(SUFeedURL=FEED, SUPublicEDKey=PUBLIC_ED_KEY, SUEnableAutomaticChecks=True,
                      SUScheduledCheckInterval=3600)
        plist.write_bytes(plistlib.dumps(values))
        # Innermost first: Sparkle nests an app, XPC services and a bare
        # Autoupdate tool inside its framework, and notarization checks them all.
        nested = [p for pattern in ('*.dylib', '*.framework', '*.xpc', '*.app') for p in app.rglob(pattern)]
        nested += list(app.glob('Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate'))
        for item in sorted(nested, key=lambda p: len(p.parts), reverse=True):
            run('codesign', '--force', '--sign', args.identity, '--timestamp', '--options', 'runtime',
                '--preserve-metadata=entitlements', item)
        run('codesign', '--force', '--sign', args.identity, '--timestamp', '--options', 'runtime',
            '--entitlements', ROOT / 'App/Resources/Chup.entitlements', app)
        details = run('codesign', '-dvv', app, capture_output=True, text=True).stderr
        if 'Authority=Developer ID Application:' not in details or 'Timestamp=' not in details or 'runtime' not in details:
            raise RuntimeError('Release must have Developer ID, secure timestamp and hardened runtime.')
        run('codesign', '--verify', '--deep', '--strict', app)
        run('python3', 'scripts/test-live-transport.py', '--app-path', app)
        (stage / 'Applications').symlink_to('/Applications')
        (stage / 'Read me.txt').write_text(
            'Chup! development preview\n\nDrag Chup! into Applications. Ordinary recording needs no virtual driver.\n'
            'Configure your trusted backend and app token in Settings. API keys stay on the backend.\n'
            'Microphone, Accessibility and capture permissions are requested for their features.\n'
            'Assistant broadcast and private voice routing remain a development prototype.\n'
            'The separate virtual microphone driver is not included.\n')
        licenses = stage / 'Licenses'
        licenses.mkdir()
        for notice in (ROOT / 'App/Resources/Licenses').glob('*.txt'):
            shutil.copy2(notice, licenses / notice.name)
        run('hdiutil', 'create', '-volname', 'Chup!', '-srcfolder', stage, '-format', 'UDZO', dmg)
    run('codesign', '--sign', args.identity, '--timestamp', dmg)
    run('codesign', '--verify', '--strict', dmg)
    notarized = False
    if args.notary_profile:
        result = run('xcrun', 'notarytool', 'submit', dmg, '--keychain-profile', args.notary_profile,
                     '--wait', '--output-format', 'json', capture_output=True, text=True)
        receipt = json.loads(result.stdout)
        (output / ('Chup-' + version + '-notary.json')).write_text(json.dumps(receipt, indent=2) + '\n')
        if receipt.get('status') != 'Accepted':
            raise RuntimeError('Apple did not accept this submission. Inspect the notarization log before distributing.')
        run('xcrun', 'stapler', 'staple', dmg)
        run('xcrun', 'stapler', 'validate', dmg)
        run('spctl', '--assess', '--type', 'open', '--context', 'context:primary-signature', '--verbose=2', dmg)
        notarized = True
    digest = hashlib.file_digest(dmg.open('rb'), 'sha256').hexdigest()
    report = {'version': version, 'architecture': 'arm64', 'file': dmg.name, 'sha256': digest,
              'developerIDSigned': True, 'notarized': notarized, 'driverIncluded': False,
              'publicReleaseQualified': False}
    (output / ('Chup-' + version + '-manifest.json')).write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))

if __name__ == '__main__':
    main()
