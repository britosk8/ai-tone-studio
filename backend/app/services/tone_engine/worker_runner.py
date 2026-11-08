"""Stream worker events without buffering an entire separation or blocking stderr."""

import json
import queue
import subprocess
import tempfile
import threading
import time


def run_worker(command, env, progress, timeout=3600):
    events = queue.Queue()
    with tempfile.TemporaryFile(mode="w+b") as errors:
        process = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=errors,
            text=True,
            encoding="utf-8",
            env=env,
        )

        def read():
            try:
                for line in process.stdout:
                    events.put(line)
            finally:
                events.put(None)

        reader = threading.Thread(target=read, daemon=True)
        reader.start()
        deadline = time.monotonic() + timeout
        try:
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise subprocess.TimeoutExpired(command, timeout)
                try:
                    line = events.get(timeout=min(remaining, 0.5))
                except queue.Empty:
                    continue
                if line is None:
                    break
                try:
                    event = json.loads(line)
                    if isinstance(event, dict) and event.get("event") == "progress":
                        progress(event)
                except (json.JSONDecodeError, UnicodeError):
                    pass
            result = process.wait(timeout=max(0.001, deadline - time.monotonic()))
            if result:
                errors.seek(0)
                raise subprocess.CalledProcessError(
                    result, command, stderr=errors.read()[-8192:]
                )
        finally:
            if process.poll() is None:
                process.kill()
            process.wait()
            reader.join(timeout=2)
            process.stdout.close()
