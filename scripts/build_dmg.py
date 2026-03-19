#!/usr/bin/env python3

import argparse
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

from ds_store import DSStore
from mac_alias import Alias, Bookmark


WINDOW_BOUNDS = "{{200, 160}, {720, 440}}"
ICON_LOCATIONS = {
    "TypoFixr.app": (180, 242),
    "Applications": (540, 242),
}


def run(*args: str) -> None:
    subprocess.check_call(args)


def write_ds_store(mount_path: Path, background_path: Path) -> None:
    ds_store_path = mount_path / ".DS_Store"

    bwsp = {
        "ContainerShowSidebar": False,
        "PreviewPaneVisibility": False,
        "ShowPathbar": False,
        "ShowSidebar": False,
        "ShowStatusBar": False,
        "ShowTabView": False,
        "ShowToolbar": False,
        "SidebarWidth": 180,
        "WindowBounds": WINDOW_BOUNDS,
    }

    icvp = {
        "arrangeBy": "none",
        "backgroundColorBlue": 1.0,
        "backgroundColorGreen": 1.0,
        "backgroundColorRed": 1.0,
        "backgroundImageAlias": Alias.for_file(str(background_path)).to_bytes(),
        "backgroundType": 2,
        "gridOffsetX": 0.0,
        "gridOffsetY": 0.0,
        "gridSpacing": 120.0,
        "iconSize": 112.0,
        "labelOnBottom": True,
        "scrollPositionX": 0.0,
        "scrollPositionY": 0.0,
        "showIconPreview": False,
        "showItemInfo": False,
        "textSize": 14.0,
        "viewOptionsVersion": 1,
    }

    with DSStore.open(str(ds_store_path), "w+") as store:
        store["."]["vSrn"] = ("long", 1)
        store["."]["bwsp"] = bwsp
        store["."]["icvp"] = icvp
        store["."]["pBBk"] = Bookmark.for_file(str(background_path))
        store["."]["icvl"] = (b"type", b"icnv")

        for item_name, location in ICON_LOCATIONS.items():
            store[item_name]["Iloc"] = location


def build_dmg(app_path: Path, background_path: Path, dmg_title: str, output_path: Path) -> None:
    temp_dir = Path(tempfile.mkdtemp(prefix="typofixr-dmg-"))
    mount_path = temp_dir / "mount"
    mount_path.mkdir(parents=True, exist_ok=True)

    writable_dmg = temp_dir / "staging.dmg"
    converted_base = temp_dir / "final"
    final_converted_path = converted_base.with_suffix(".dmg")

    try:
        run(
            "hdiutil",
            "create",
            "-ov",
            "-volname",
            dmg_title,
            "-fs",
            "HFS+",
            "-size",
            "32m",
            str(writable_dmg),
        )
        run(
            "hdiutil",
            "attach",
            "-nobrowse",
            "-owners",
            "off",
            "-mountpoint",
            str(mount_path),
            str(writable_dmg),
        )

        try:
            background_dir = mount_path / ".background"
            background_dir.mkdir(parents=True, exist_ok=True)
            background_in_image = background_dir / "background.png"
            shutil.copyfile(background_path, background_in_image)

            run("/usr/bin/ditto", str(app_path), str(mount_path / "TypoFixr.app"))
            os.symlink("/Applications", mount_path / "Applications")
            write_ds_store(mount_path, background_in_image)
            run("sync", "--file-system", str(mount_path))
        finally:
            run("hdiutil", "detach", str(mount_path), "-quiet")

        if output_path.exists():
            output_path.unlink()

        run("hdiutil", "convert", str(writable_dmg), "-format", "UDZO", "-o", str(converted_base))
        shutil.move(str(final_converted_path), str(output_path))
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app-path", required=True)
    parser.add_argument("--background-path", required=True)
    parser.add_argument("--dmg-title", required=True)
    parser.add_argument("--output-path", required=True)
    args = parser.parse_args()

    build_dmg(
        app_path=Path(args.app_path),
        background_path=Path(args.background_path),
        dmg_title=args.dmg_title,
        output_path=Path(args.output_path),
    )


if __name__ == "__main__":
    main()
