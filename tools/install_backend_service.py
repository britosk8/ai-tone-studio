"""Install the local backend as a user service. Does not kill an existing server.
Run from the repository: backend/.venv/bin/python tools/install_backend_service.py
Then systemctl --user start ai-tone-studio after the old process has stopped.
"""

from pathlib import Path
import subprocess
import os

root = Path(__file__).resolve().parents[1]
if not (root / "backend/.venv/bin/uvicorn").is_file():
    raise SystemExit("Prepare backend/.venv before installing the service.")
value = str(root)
if "\n" in value or "\r" in value:
    raise SystemExit("Invalid project path")
value = value.replace("\\", "\\\\").replace('"', '\\"').replace("%", "%%")
unit = (root / "ops/ai-tone-studio.service.in").read_text().replace("@ROOT@", value)
folder = Path.home() / ".config/systemd/user"
folder.mkdir(parents=True, exist_ok=True)
path = folder / "ai-tone-studio.service"
stage = folder / "ai-tone-studio-check.service"
try:
    stage.write_text(unit)
    subprocess.run(["systemd-analyze", "--user", "verify", str(stage)], check=True)
    os.replace(stage, path)
finally:
    stage.unlink(missing_ok=True)
subprocess.run(["systemctl", "--user", "daemon-reload"], check=True)
subprocess.run(["systemctl", "--user", "enable", "ai-tone-studio.service"], check=True)
print(f"Installed {path}; start after stopping an idle manual backend.")
