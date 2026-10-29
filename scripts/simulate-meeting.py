#!/usr/bin/env python3
"""End-to-end meeting rehearsal against the installed app and your running backend.

Builds a ~3 minute two-voice call with `say`, launches /Applications/Chup!.app with
--simulate-meeting (records it silently through the real process tap, types notes, then
Stop & save runs the real transcript -> summary -> notes pipeline), and finally reads the
meeting back over MCP. Makes real, billable backend calls. Adds one "Simulated meeting"
to your library (delete it afterwards if you like).

  python3 scripts/simulate-meeting.py            # quit Chup! first (menu bar → Quit, never mid-recording)
  python3 scripts/simulate-meeting.py --short    # one ~90 s pass instead of ~3 min

Needs the backend token saved in Chup! (Settings → Advanced) and, for the MCP step,
Settings → Privacy → Let AI tools read meetings.
"""
import json, os, subprocess, sys, time, wave
from pathlib import Path

APP = '/Applications/Chup!.app'
OUT = Path(__file__).resolve().parent.parent / '.artifacts' / 'simulation'
SCRIPT = [
    ('Samantha', "Thanks for joining. Let's get through the Q3 launch plan."),
    ('Daniel', "Sure. The main question is still the launch date."),
    ('Samantha', "We agreed last week to aim for September fifteenth. Is that still realistic?"),
    ('Daniel', "I think so, but only if QA starts by the end of August."),
    ('Samantha', "Who owns QA this time?"),
    ('Daniel', "Priya will own QA. She confirmed this morning."),
    ('Samantha', "Great. Then the launch stays on September fifteenth. That's decided."),
    ('Daniel', "On budget, we asked for forty thousand euros for the campaign."),
    ('Samantha', "Finance hasn't approved it yet. So the budget is still open."),
    ('Daniel', "I'll follow up with finance by Friday to get an answer on the budget."),
    ('Samantha', "Good. What about the pricing page?"),
    ('Daniel', "Marco will rewrite the pricing page copy. He needs the final tiers first."),
    ('Samantha', "I'll send Marco the final pricing tiers tomorrow."),
    ('Daniel', "One risk: the partner integration might slip. Their API is not stable yet."),
    ('Samantha', "Then we launch without the partner integration if it isn't ready by September first."),
    ('Daniel', "Agreed. We won't block the launch on it."),
    ('Samantha', "Anything else? Customer webinar?"),
    ('Daniel', "We should run a webinar the week after launch, but nobody owns it yet."),
    ('Samantha', "Let's leave the webinar owner open and decide next week."),
    ('Daniel', "Sounds good. So: QA by end of August with Priya, budget follow-up by Friday, pricing tiers tomorrow."),
    ('Samantha', "Perfect. Thanks Daniel, talk next week."),
]

def build_audio(path: Path) -> float:
    OUT.mkdir(parents=True, exist_ok=True)
    rate, frames = 24000, []
    for i, (voice, line) in enumerate(SCRIPT):
        clip = OUT / f'line-{i:02d}.wav'
        subprocess.run(['say', '-v', voice, '--data-format=LEI16@24000', '-o', str(clip), line], check=True)
        with wave.open(str(clip)) as w:
            frames.append(w.readframes(w.getnframes()))
        frames.append(b'\0\0' * int(rate * 0.6))
        clip.unlink()
    # Repeat the call once so live notes get past their one-minute windows.
    body = b''.join(frames)
    with wave.open(str(path), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate)
        w.writeframes(body if '--short' in sys.argv else body + body)
    return len(body) / 2 / rate

def mcp(meeting_id: str) -> dict:
    exe = APP + '/Contents/MacOS/Chup!'
    requests = [
        {'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {'protocolVersion': '2025-06-18', 'capabilities': {}, 'clientInfo': {'name': 'rehearsal', 'version': '1'}}},
        {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
        {'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'},
        {'jsonrpc': '2.0', 'id': 3, 'method': 'tools/call', 'params': {'name': 'list_meetings', 'arguments': {'limit': 3}}},
        {'jsonrpc': '2.0', 'id': 4, 'method': 'tools/call', 'params': {'name': 'get_meeting_notes', 'arguments': {'meeting_id': meeting_id}}},
    ]
    proc = subprocess.run([exe, '--mcp'], input=''.join(json.dumps(r) + '\n' for r in requests),
                          capture_output=True, text=True, timeout=60)
    if proc.returncode not in (0, None) and not proc.stdout:
        return {'ok': False, 'error': proc.stderr.strip() or f'exit {proc.returncode}'}
    replies = {m['id']: m for m in map(json.loads, filter(None, proc.stdout.splitlines()))}
    text = lambda i: replies.get(i, {}).get('result', {}).get('content', [{}])[0].get('text', '')
    tools = [t['name'] for t in replies.get(2, {}).get('result', {}).get('tools', [])]
    return {'ok': meeting_id in text(3) and '[you]' in text(4), 'tools': tools, 'notes': text(4)}

def main():
    # Never quit Chup! from here: it could be recording. The user closes it safely.
    if subprocess.run(['pgrep', '-x', 'Chup!'], capture_output=True).returncode == 0:
        sys.exit('Chup! is running. Quit it from the menu bar (not mid-recording), then rerun.')
    audio, report = OUT / 'meeting.wav', OUT / 'report.json'
    seconds = build_audio(audio)
    report.unlink(missing_ok=True)
    print(f'Built a {seconds * (1 if "--short" in sys.argv else 2):.0f}s two-voice call. Launching Chup! (call audio is muted)…')
    subprocess.run(['open', '-a', APP, '--args', '--simulate-meeting', str(audio), '--simulate-report', str(report)], check=True)
    deadline = time.time() + 25 * 60
    while not report.exists() and time.time() < deadline:
        time.sleep(5)
    if not report.exists():
        sys.exit('No report after 25 minutes. Check the app and ~/Library/Logs/Chup/backend.log.')
    result = json.loads(report.read_text())
    result['mcp'] = mcp(result.get('meetingID', '')) if result.get('meetingID') else {'ok': False}
    result['checks']['mcpReadBack'] = result['mcp']['ok']
    report.write_text(json.dumps(result, indent=2, sort_keys=True))
    for name, ok in sorted(result['checks'].items()):
        print(('PASS ' if ok else 'FAIL ') + name)
    print('\nLive notes:', *result.get('liveNotes', []), sep='\n  ')
    print('\nNotes:', *result.get('notes', []), sep='\n  ')
    print(f"\nRecorded {result.get('recordedSeconds')}s; notes ready {result.get('processingSeconds')}s after stop.")
    print('Full report:', report)
    sys.exit(0 if all(result['checks'].values()) else 1)

if __name__ == '__main__':
    main()
