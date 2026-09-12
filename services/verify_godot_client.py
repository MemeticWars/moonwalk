"""End-to-end Godot HTTP/cache test against the adapter with an analytic WCS fixture."""
import os
from pathlib import Path
import subprocess
import tempfile
import threading
from unittest.mock import patch

import terrain_gateway as gateway
from test_terrain_gateway import CONFIG, analytic_wcs

root = Path(__file__).resolve().parents[1]
engine = root / 'tools/godot/Godot_v4.6.1-stable_win64_console.exe'
with tempfile.TemporaryDirectory(dir=root / 'artifacts') as folder:
    server = gateway.Gateway(('127.0.0.1', 0), CONFIG, Path(folder))
    with patch.object(gateway, 'fetch', side_effect=analytic_wcs):
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            env = dict(os.environ, APPDATA=str(root / 'tools/godot/editor_data'), LOCALAPPDATA=str(root / 'tools/godot/editor_data'))
            result = subprocess.run([str(engine), '--headless', '--path', str(root / 'godot'), '--script', 'res://tests/stream_test.gd', '--', f'--endpoint=http://127.0.0.1:{server.server_port}'], env=env, capture_output=True, text=True, timeout=35, creationflags=subprocess.CREATE_NO_WINDOW)
            output = result.stdout + result.stderr
            (root / 'artifacts/stream-test.log').write_text(output, encoding='utf-8')
            print(output)
            if 'STREAM PASS' not in output or 'SCRIPT ERROR' in output:
                raise SystemExit(1)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
