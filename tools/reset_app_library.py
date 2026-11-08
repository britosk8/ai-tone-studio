#!/usr/bin/env python3
"""Delete app music/presets offline; preserve recordings and pedal recovery evidence."""
import argparse
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))
from app.core.library_reset import reset_library

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--backend-stopped-and-delete",
        action="store_true",
        required=True,
        help="Confirm backend/workers are stopped and permanently delete library",
    )
    parser.parse_args()
    print(reset_library())
