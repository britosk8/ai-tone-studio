"""Reaproveita aprovação humana existente, conferindo SHA do original e cache v2.
Não escolhe uma música por título, não altera presets nem grava a pedaleira.
"""

import argparse
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "backend"))
from app.core.reference_library import saved_source, select_region
from app.core.storage import load_record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pair-id", required=True)
    args = parser.parse_args()
    approval = json.loads(
        (ROOT / "repertorio/fase_1/01/APROVACAO_REFERENCIAS.json").read_text()
    )
    comparison = json.loads(
        (ROOT / "repertorio/fase_2/infest_comparacao/comparacao.json").read_text()
    )
    selected = []
    for role, candidate in [("rhythm", "01_base_01"), ("lead", "01_solo_destaque_01")]:
        decision = next(
            d for d in approval["decisions"] if d["candidate_id"] == candidate
        )
        expected = next(
            r for r in comparison["results"] if r["candidate_id"] == candidate
        )
        if decision["decision"] not in {"aceitar_base", "aceitar_solo"} or (
            decision["start_seconds"],
            decision["end_seconds"],
        ) != (expected["start_seconds"], expected["end_seconds"]):
            raise ValueError("Intervalo não aprovado")
        source = saved_source(args.pair_id, role)
        original = ROOT / expected["source_file"]
        if (
            hashlib.sha256(original.read_bytes()).hexdigest()
            != expected["source_sha256"]
            or source["original_sha256"] != expected["source_sha256"]
        ):
            raise ValueError("Original diferente do áudio aprovado")
        start = decision["start_seconds"]
        duration = decision["end_seconds"] - start
        if (
            start < source["cache_start_seconds"]
            or start + duration
            > source["cache_start_seconds"] + source["available_duration"]
        ):
            raise ValueError("Cache não contém o trecho aprovado")
        existing = (
            load_record("comparison_reference", json.dumps([args.pair_id, role])) or {}
        )
        if existing.get("binding_method") == "saved_guitar_role_region":
            print(role, "seleção existente preservada")
            continue
        selected.append((role, start, duration))
    for role, start, duration in selected:
        print(
            json.dumps(
                select_region(args.pair_id, role, start, duration), ensure_ascii=False
            )
        )


if __name__ == "__main__":
    main()
