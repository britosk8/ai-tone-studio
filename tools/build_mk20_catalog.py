"""Reproduce the reviewed MK20 AM4 subset from the already inspected official APK.
Usage: backend/.venv/bin/python tools/build_mk20_catalog.py /path/M-EFCS.apk
Does not execute vendor binaries or access hardware. Legacy metadata comes from
our pinned pre-migration catalog; unknown acoustic families remain unknown.
"""

import json, zipfile, re, copy, hashlib, subprocess, sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
old = json.loads(
    subprocess.check_output(
        ["git", "show", "1fddb15:catalogs/mk20/catalog.json"], cwd=root
    )
)
shared = json.loads((root / "catalogs/mk300/catalog.json").read_text())
apk = Path(sys.argv[1])
if (
    hashlib.sha256(apk.read_bytes()).hexdigest()
    != "e72ab3df88a968357db11e9554b9deeaa8b82254fa4dcc421a9cbdd77e196992"
):
    raise SystemExit(
        "APK differs from the reviewed artifact; review before regenerating."
    )
b = zipfile.ZipFile(apk).read(
    "assets/flutter_assets/lib/resources/bin/mk20/mk20_am4_ampCab.bin"
)
marks = list(re.finditer(b"AM4\x00|CAB\x00", b))


def names(a, z):
    return [
        b[m.start() + 4 : m.start() + 18].split(b"\0")[0].decode("ascii")
        for m in marks[a:z]
    ]


def spec(lo=0, hi=100, default=50, **kw):
    return {"min": lo, "max": hi, "default": default, **kw}


blocks = {}
for key, id in [("GATE", 1), ("EQ", 5), ("MOD", 6), ("DLY", 7), ("REV", 8), ("VOL", 9)]:
    v = copy.deepcopy(shared["blocks"][key])
    v["block_id"] = id
    v["models"] = v["models"][:1]
    v.pop("knob_ranges", None)
    if key == "EQ":
        for p in v["models"][0]["params"].values():
            p.update(min=-24, max=24, step=0.5, unit="dB", wire_scale=2)
    if key == "VOL":
        v["models"][0]["params"]["VOL"]["default"] = 60
    # These initial values match the controls in the physical Infest image, not inferred firmware defaults.
    if key in ["MOD", "DLY"]:
        v["models"][0]["params"]["Sync"]["default"] = 0
    blocks[key] = v
knobs = ["Gain", "Level", "Bass", "Middle", "Treble", "Reso", "Pres", "Bright"]
for key, id, ns, oldkey in [
    ("DS", 2, names(0, 40), "ds_models"),
    ("AMP", 3, names(40, 130), "amp_models"),
    ("CAB", 4, names(150, 250), "cab_models"),
]:
    models = []
    previous = {
        m["name"]: m
        for m in old[oldkey].get("models", old[oldkey].get("selected_models", []))
    }
    for n in ns:
        suffix = re.sub(r"^\d+", "", n)
        meta = previous.get(suffix, {})
        idx = int(re.match(r"\d+", n)[0]) - 1
        params = {k: spec(default=0 if k == "Reso" else 50) for k in knobs}
        ks = knobs
        if key == "CAB":
            ks = ["Level", "Low Cut", "High Cut"]
            params = {
                "Level": spec(default=60),
                "Low Cut": spec(20, 300, 80, unit="Hz"),
                "High Cut": spec(
                    5000, 18000, 7500, step=100, unit="Hz", wire_scale=0.01
                ),
            }
        model = {
            "id": idx,
            "name": n,
            "knobs": ks,
            "params": params,
            "defaults": [p["default"] for p in params.values()],
            "initial_values_basis": "app starting values; not firmware reset defaults",
        }
        if key == "AMP":
            t = meta.get("type")
            if not t:
                t = (
                    "clean"
                    if suffix.startswith("CL") or "JC120" in suffix
                    else (
                        "crunch"
                        if suffix.startswith("CR")
                        else (
                            "overdrive"
                            if suffix.startswith("OD")
                            else "high_gain" if suffix.startswith("DS") else "unknown"
                        )
                    )
                )
            model["type"] = t
        if key == "DS":
            model["type"] = meta.get("type", "distortion")
        for k in ["based_on", "config"]:
            if k in meta:
                model[k] = meta[k]
        models.append(model)
    blocks[key] = {"block_id": id, "models": models, "verification_status": "VERIFIED"}
new = {
    "_meta": {
        "device": "M-VAVE MK20",
        "catalog_version": "0.4.0",
        "verification_status": "VERIFIED",
        "last_updated": "2026-10-29",
        "sources": old["_meta"]["sources"][:2]
        + ["https://resource.m-vave.com/software/app/M-EFCS.apk"],
        "warnings": [
            "USB full-image pilot targets slot 150 only; acoustic matching remains heuristic.",
            "Factory AM4 models only; custom NAM/IR slots require confirmation.",
            "FX and additional temporal algorithms are not enabled for transfer in this reviewed subset.",
        ],
        "resource_sha256": hashlib.sha256(b).hexdigest(),
    },
    "device_info": old["device_info"],
    "blocks": blocks,
}
(root / "catalogs/mk20/catalog.json").write_text(
    json.dumps(new, ensure_ascii=False, indent=2) + "\n"
)
(root / "android/assets/mk20_catalog.json").write_text(
    json.dumps(new, ensure_ascii=False, indent=2) + "\n"
)
print("models", [(k, len(v["models"])) for k, v in blocks.items()])
