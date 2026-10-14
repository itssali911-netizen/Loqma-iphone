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
        "icon_prompt": "Create the final iOS app icon for LUQMA from attached mark. Flat Sandow theme only. Square opaque solid charcoal background HEX #111214 edge to edge, NO rounded-square outer frame, NO transparency. Restyle the logo to a SINGLE solid flat orange HEX #F97316, removing ALL orange gradients, light highlights, shadow, noise and specks. Preserve circular plate / progress ring and three-prong negative-space fork, but simplify the two scalloped bites into one confident single bite cutout at top-right. Center the orange emblem, about68% canvas width, with balanced empty margins. Extremely crisp minimal geometric vector-like silhouette, clean anti-aliased edges, professional brand identity. No text, no photographic texture, no mockup, no devices, no additional variants. The fork cutout and ring interior are the same charcoal background. Deliver one high quality square opaque PNG.",
        "mark_prompt": "Create the transparent in-app version of this approved LUQMA app icon. Preserve EXACTLY the orange plate/ring/fork emblem with its ONE upper-right bite, same geometry, same clean edge quality, same scale and position, no design changes. Remove ALL charcoal background including the charcoal within the fork and circular ring interior so those are genuinely transparent negative space. Keep only the orange logo on a transparent square PNG canvas. Do not add black edges, noise, shadows, text or any new elements. Single output matching the attached icon's emblem.",
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
