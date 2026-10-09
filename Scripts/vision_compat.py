"""Backport two upstream Qwen3-VL fixes to our tested, pinned MLX release.

PRs 411 (sRGB preprocessing) and 455 (fused vision attention) are MIT-licensed
upstream changes. Refuse any unrecognized source; never patch a moving version.
Both the iPhone build and the runtime check use these identical changes.
"""
import hashlib
import json
from pathlib import Path


def apply_vision_compat(packages: Path, verify_only: bool = False) -> None:
    spec = json.loads(Path(__file__).with_name("qwen3vl-compat.json").read_text())
    file = packages / "checkouts/mlx-swift-lm/Libraries/MLXVLM/Models/Qwen3VL.swift"
    original = file.read_bytes()
    digest = hashlib.sha256(original).hexdigest()
    if digest == spec["patched_sha256"]:
        return
    if verify_only:
        raise RuntimeError("Xcode did not retain the verified Qwen3-VL compatibility fixes.")
    if digest != spec["original_sha256"]:
        raise RuntimeError("The pinned Qwen3-VL source changed. Review the compatibility patch before building.")
    source = original.decode()
    for patch in spec["patches"]:
        if source.count(patch["old"]) != 1:
            raise RuntimeError("Qwen3-VL upstream patch context mismatch.")
        source = source.replace(patch["old"], patch["replacement"])
    if hashlib.sha256(source.encode()).hexdigest() != spec["patched_sha256"]:
        raise RuntimeError("Qwen3-VL compatibility patch integrity check failed.")
    # SwiftPM makes checkout files read-only. Enable owner-write for this one
    # checksum-verified file and restore its original permissions afterwards.
    mode = file.stat().st_mode
    try:
        file.chmod(mode | 0o200)
        file.write_text(source)
    finally:
        file.chmod(mode)
    print("Applied verified upstream Qwen3-VL sRGB and fused-attention fixes.", flush=True)
