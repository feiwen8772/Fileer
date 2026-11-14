#!/usr/bin/env python3
"""Compile the layered app icon and install its contributed ICNS fallback before signing.

Usage: python3 scripts/build-icon.py RESOURCES INFO_PLIST
"""
import plistlib
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def build(resources, info_plist):
    resources, info_plist = Path(resources), Path(info_plist)
    with info_plist.open("rb") as file:
        info = plistlib.load(file)
    name = info["CFBundleIconName"]
    raster = ROOT / "Resources" / f"{name}.png"
    if raster.is_file():
        # User-supplied artwork is already rendered: preserve it without adding glass or extra layers.
        with tempfile.TemporaryDirectory(prefix="fileer-icon-") as scratch:
            iconset = Path(scratch) / f"{name}.iconset"
            iconset.mkdir()
            for size in (16, 32, 128, 256, 512):
                for scale, suffix in ((1, ""), (2, "@2x")):
                    pixels = str(size * scale)
                    subprocess.run(["sips", "-z", pixels, pixels, str(raster), "--out",
                                    str(iconset / f"icon_{size}x{size}{suffix}.png")],
                                   check=True, stdout=subprocess.DEVNULL)
            compiled = Path(scratch) / f"{name}.icns"
            subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(compiled)], check=True)
            resources.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(compiled, resources / f"{name}.icns")
            # A raster ICNS uses CFBundleIconFile; CFBundleIconName is for an asset catalog.
            info.pop("CFBundleIconName", None)
            info["CFBundleIconFile"] = name
            with info_plist.open("wb") as file:
                plistlib.dump(info, file, sort_keys=False)
        print(f"Built {name}.icns from the supplied artwork.")
        return
    source = ROOT / "Resources" / f"{name}.icon"
    fallback = ROOT / "Resources" / f"{name}.icns"
    if not (source / "icon.json").is_file() or not fallback.is_file():
        raise FileNotFoundError("The layered app icon and its ICNS fallback are both required.")

    with tempfile.TemporaryDirectory(prefix="strata-icon-") as scratch:
        compiled = Path(scratch)
        partial = compiled / "icon.plist"
        subprocess.run(["xcrun", "actool", "--compile", str(compiled), "--platform", "macosx",
                        "--minimum-deployment-target", info["LSMinimumSystemVersion"], "--app-icon", name,
                        "--output-partial-info-plist", str(partial), str(source)], check=True)
        with partial.open("rb") as file:
            metadata = plistlib.load(file)
        if metadata.get("CFBundleIconName") != name or not (compiled / "Assets.car").is_file():
            raise ValueError("The icon compiler did not produce the named app icon and its asset catalog.")
        resources.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(compiled / "Assets.car", resources / "Assets.car")
        # This export includes the standard macOS sizing and shadow; adaptive appearances use the compiled catalog.
        shutil.copyfile(fallback, resources / f"{name}.icns")
        info.update(metadata)
        with info_plist.open("wb") as file:
            plistlib.dump(info, file, sort_keys=False)
    print(f"Compiled {name}.icon with its ICNS fallback.")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    build(*sys.argv[1:])
