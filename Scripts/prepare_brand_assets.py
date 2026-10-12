#!/usr/bin/env python3
"""Package generated artwork for Xcode without changing the approved design.

The built-in image generation tool supplies square PNG files at 1254 px.
Xcode's universal iOS app icon requires exactly 1024 px and no alpha channel.
Only standard icon downsampling occurs here. All visual editing, cleaning,
background creation, and composition are performed by the image generation
tool. The transparent in-app mark is copied byte for byte.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil

from PIL import Image


def image_details(path: Path) -> dict:
    with Image.open(path) as image:
        alpha = image.getchannel("A").getextrema() if "A" in image.getbands() else None
        return {
            "size": list(image.size),
            "mode": image.mode,
            "alpha_extrema": list(alpha) if alpha else None,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        }


def package(mark_source: Path, icon_source: Path, assets: Path, outputs: Path) -> dict:
    with Image.open(mark_source) as mark:
        if "A" not in mark.getbands() or mark.getchannel("A").getextrema()[0] != 0:
            raise ValueError("The in-app logo must retain genuine transparency.")
    with Image.open(icon_source) as icon:
        if icon.width != icon.height:
            raise ValueError("The generated app icon must be square.")
        if "A" in icon.getbands() and icon.getchannel("A").getextrema() != (255, 255):
            raise ValueError("The generated app icon must already be opaque.")
        # iOS asset packaging only; the tool has already created the background.
        icon = icon.convert("RGB")
        if icon.size != (1024, 1024):
            icon = icon.resize((1024, 1024), Image.Resampling.LANCZOS)
        icon_dir = assets / "AppIcon.appiconset"
        icon_dir.mkdir(parents=True, exist_ok=True)
        icon.save(icon_dir / "AppIcon.png", optimize=True)

    mark_dir = assets / "LuqmaMark.imageset"
    mark_dir.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(mark_source, mark_dir / "LuqmaMark.png")
    contents = {
        "images": [{"filename": "LuqmaMark.png", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    }
    (mark_dir / "Contents.json").write_text(
        json.dumps(contents, indent=2) + "\n", encoding="utf-8"
    )
    outputs.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(mark_dir / "LuqmaMark.png", outputs / "لقمة-شعار.png")
    shutil.copyfile(icon_dir / "AppIcon.png", outputs / "لقمة-أيقونة.png")
    result = {
        "image_generation": "Built-in image_gen: logo generation and icon editing",
        "packaging": "Transparent mark copied unchanged; opaque icon downsampled to 1024 px with Lanczos",
        "mark": image_details(mark_dir / "LuqmaMark.png"),
        "icon": image_details(icon_dir / "AppIcon.png"),
        "icon_prompt": "Preserve the orange plate with upper-right bite cutouts and negative-space fork; center the mark at 70 percent of a square opaque charcoal #16151D canvas; clean edges, no specks or text.",
    }
    (outputs / "loqma-brand-assets.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mark", required=True, type=Path)
    parser.add_argument("--icon", required=True, type=Path)
    parser.add_argument("--assets", required=True, type=Path)
    parser.add_argument("--outputs", required=True, type=Path)
    args = parser.parse_args()
    print(json.dumps(package(args.mark, args.icon, args.assets, args.outputs), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
