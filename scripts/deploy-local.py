#!/usr/bin/env python3
"""Build, locally sign, validate and install Chup! as the commit-count build that later releases update."""
import argparse
import os
import datetime
import json
import pathlib
import plistlib
import re
import shutil
import subprocess
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
ARTIFACTS = ROOT / '.artifacts'
APP_NAME = 'Chup!.app'


def run(*args, **kwargs):
    return subprocess.run([str(arg) for arg in args], cwd=ROOT, check=True, **kwargs)


def info(app):
    value = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if value['CFBundleIdentifier'] != 'com.chup.mac':
        raise RuntimeError('Refusing to replace or install a different application.')
    return value


def running():
    processes = subprocess.check_output(['/bin/ps', '-axo', 'comm='], text=True)
    return any(line.strip().endswith('/Chup!.app/Contents/MacOS/Chup!')
               for line in processes.splitlines())


def code_uuids(app):
    result = {}
    for name in ('Chup!', 'Chup!.debug.dylib'):
        binary = app / 'Contents/MacOS' / name
        if not binary.exists():
            if name == 'Chup!': raise RuntimeError('App executable is missing.')
            continue
        output = subprocess.check_output(['/usr/bin/dwarfdump', '--uuid', str(binary)], text=True)
        matches = re.findall(r'UUID: ([A-Fa-f0-9-]+) \(([^)]+)\)', output)
        if not matches: raise RuntimeError(f'Cannot verify executable UUID for {name}.')
        result[name] = {arch: uuid.upper() for uuid, arch in matches}
    return result


def launch_verified(target):
    executable = str(target / 'Contents/MacOS/Chup!')
    run('/usr/bin/open', '-n', target)
    stable_pid = None
    for _ in range(20):
        time.sleep(1)
        rows = subprocess.check_output(['/bin/ps', '-axo', 'pid=,comm='], text=True).splitlines()
        matches = [int(parts[0]) for row in rows if len(parts := row.strip().split(None, 1)) == 2 and parts[1] == executable]
        if len(matches) != 1:
            raise RuntimeError(f'Expected one running process from {target}; found {len(matches)}. App is installed, but launch is not verified.')
        if stable_pid is not None and matches[0] != stable_pid:
            raise RuntimeError('Installed process restarted during launch verification.')
        stable_pid = matches[0]
    return dict(pid=stable_pid, executable=executable, observedSeconds=20)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--launch', action='store_true', help='Launch the installed copy and verify one stable process for 20 seconds.')
    parser.add_argument('--check-microphone', action='store_true', help='Before launch, run three meter-only startup cycles on the selected physical input. Saves/uploads no audio.')
    parser.add_argument('--applications-dir', type=pathlib.Path, default=pathlib.Path('/Applications'))
    parser.add_argument('--signing-identity', help='Override the local Apple Development signing identity.')
    args = parser.parse_args()
    target = args.applications_dir.expanduser().resolve() / APP_NAME
    if target.is_symlink():
        raise RuntimeError('The installed app is a symbolic link; choose a regular Applications destination.')
    if target.exists(): info(target)  # refuses to replace a different app
    # Developer ID first: it is what CI releases carry, so Sparkle can replace this
    # install in place and macOS keeps its microphone and Accessibility grants.
    identities = subprocess.check_output(['/usr/bin/security', 'find-identity', '-v', '-p', 'codesigning'], text=True)
    available = (re.findall(r'([A-F0-9]{40}) "Developer ID Application:[^"]+"', identities)
                 or re.findall(r'([A-F0-9]{40}) "Apple Development:[^"]+"', identities))
    identity = args.signing_identity or (available[0] if available else None)
    if not identity:
        raise RuntimeError('No Developer ID or Apple Development identity is available. Configure Xcode signing or pass --signing-identity.')
    # The same number CI gives a release of HEAD, so every later push updates this install.
    version = int(subprocess.check_output(['git', 'rev-list', '--count', 'HEAD'], cwd=ROOT, text=True))
    ARTIFACTS.mkdir(exist_ok=True)
    log = ARTIFACTS / f'deploy-build-{version}.log'
    print(f'Building Chup! build {version}. Log: {log}', flush=True)
    run('xcodegen', 'generate')
    with log.open('w') as output:
        run('xcodebuild', '-project', 'Chup.xcodeproj', '-scheme', 'Chup',
            '-configuration', 'Debug', '-destination', 'platform=macOS,arch=arm64',
            '-derivedDataPath', '.artifacts/DerivedData', 'CODE_SIGNING_ALLOWED=NO',
            f'CURRENT_PROJECT_VERSION={version}', 'build', stdout=output, stderr=subprocess.STDOUT)
    built = ARTIFACTS / 'DerivedData/Build/Products/Debug' / APP_NAME
    metadata = info(built)
    expected_uuids = code_uuids(built)
    if metadata['CFBundleVersion'] != str(version) or metadata['CFBundleExecutable'] != 'Chup!':
        raise RuntimeError('Built application version or executable does not match the requested product.')
    run('python3', 'scripts/test-live-transport.py', '--app-path', built)
    if running():
        raise RuntimeError(f'Build {version} is ready at {built}. Close Chup! safely before deployment; no process was stopped.')
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.chup-install-', dir=target.parent) as directory:
        stage = pathlib.Path(directory) / APP_NAME
        run('/usr/bin/ditto', built, stage)
        # Xcode's Debug product includes a separate app-code dylib. Sign embedded
        # code before its containing bundle so hardened runtime sees one Team ID.
        # Sparkle nests an app, XPC services and Autoupdate inside its framework.
        nested = [p for pattern in ('*.dylib', '*.framework', '*.xpc', '*.app') for p in stage.rglob(pattern)]
        nested += list(stage.glob('Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate'))
        for item in sorted(nested, key=lambda p: len(p.parts), reverse=True):
            run('/usr/bin/codesign', '--force', '--sign', identity, '--timestamp=none',
                '--preserve-metadata=entitlements', item)
        run('/usr/bin/codesign', '--force', '--sign', identity, '--options', 'runtime',
            '--timestamp=none', '--entitlements', ROOT / 'App/Resources/Chup.entitlements', stage)
        run('/usr/bin/codesign', '--verify', '--deep', '--strict', stage)
        run('python3', 'scripts/test-live-transport.py', '--app-path', stage)
        if running():
            raise RuntimeError('Chup! started during deployment. Close it safely and retry; the installed app was not replaced.')
        backup = pathlib.Path(directory) / 'previous.app'
        had_previous = target.exists()
        if had_previous:
            info(target)
            target.rename(backup)
        try:
            stage.rename(target)
            run('/usr/bin/codesign', '--verify', '--deep', '--strict', target)
            if code_uuids(target) != expected_uuids:
                raise RuntimeError('Installed executable UUIDs differ from the build output.')
            if info(target)['CFBundleVersion'] != str(version):
                raise RuntimeError('Installed build verification failed.')
            run('python3', 'scripts/test-live-transport.py', '--app-path', target)
            if args.check_microphone:
                run('python3', 'scripts/test-live-transport.py', '--app-path', target, '--timeout', '60',
                    env={**os.environ, 'CHUP_HARDWARE_MIC_TEST': '1'})
        except BaseException:
            if target.exists():
                shutil.rmtree(target)
            if had_previous:
                backup.rename(target)
            raise
        if had_previous:
            stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
            saved = ARTIFACTS / 'InstalledBackups' / stamp / APP_NAME
            saved.parent.mkdir(parents=True)
            shutil.move(backup, saved)
    receipt = dict(path=str(target), version=metadata['CFBundleShortVersionString'], build=version,
                   executableUUIDs=expected_uuids, signingIdentity=identity, installedAt=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                   validation='codesign --verify --deep --strict; installed native offline audio/localhost Live')
    (ARTIFACTS / 'last-install.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(f"Installed Chup! {receipt['version']} ({version}) at {target}", flush=True)
    if args.launch:
        receipt['running'] = launch_verified(target)
        (ARTIFACTS / 'last-install.json').write_text(json.dumps(receipt, indent=2) + '\n')
        print(f"Verified running build {version}: PID {receipt['running']['pid']} at {receipt['running']['executable']} for 20 seconds.", flush=True)
    print('Local development install; notarization and physical recording qualification are separate.')


if __name__ == '__main__':
    main()
