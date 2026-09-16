#!/usr/bin/python3
"""Isolated terminal input receiver. Never executes input or starts a shell."""
import json, os, pathlib, sys, termios, tty
receipt = pathlib.Path(os.environ['CHUP_PASTE_RECEIPT'])
settings = termios.tcgetattr(sys.stdin.fileno())
received = b''
def save():
    temp = receipt.with_suffix('.tmp')
    temp.write_text(json.dumps(dict(pid=os.getpid(), parent=os.getppid(), received=received.decode('utf-8', errors='replace'))))
    temp.replace(receipt)
try:
    tty.setraw(sys.stdin.fileno())
    os.write(sys.stdout.fileno(), ('CHUP ISOLATED PASTE FIXTURE ' + receipt.parent.name + ' > ').encode())
    save()
    while True:
        chunk = os.read(sys.stdin.fileno(), 4096)
        if not chunk: break
        received += chunk
        save()
        os.write(sys.stdout.fileno(), chunk)
finally:
    termios.tcsetattr(sys.stdin.fileno(), termios.TCSANOW, settings)
