#!/usr/bin/env python3
"""
Recenter the SF Symbol checkmark in Together AppIcon PNGs.

SF Symbol `checkmark` 字形不对称（短臂左下，长臂右上），叠加光晕/渐变后
视觉重心偏右上。本脚本通过像素级平移补偿，把整个"打勾+光晕/渐变"向左下移，
使视觉重心对齐几何中心。

Usage:
    python3 scripts/recenter_app_icon.py --dry-run
    python3 scripts/recenter_app_icon.py --out-dir /tmp/icon_preview/
    python3 scripts/recenter_app_icon.py
    python3 scripts/recenter_app_icon.py --shift -15,18
"""

import argparse
import shutil
import sys
from pathlib import Path

try:
    from PIL import Image
    import numpy as np
except ImportError:
    sys.exit("Missing deps. Run: python3 -m pip install --user Pillow numpy")


ICONSET = Path(__file__).resolve().parent.parent / \
    "Together/Assets.xcassets/AppIcon.appiconset"
TARGETS = ["1024.png", "icon_dark.png", "icon_tinted.png"]
REFERENCE = "1024.png"  # 三张图物理位置一致，用这张的检测结果统一应用

CORNER_PATCH = 12          # px, size of each corner sample block
FG_THRESHOLD = 25.0        # L2 color distance below this = background
MAX_SHIFT = 60             # px, abort if computed shift exceeds this


def estimate_bg(rgb: np.ndarray) -> np.ndarray:
    H, W, _ = rgb.shape
    p = CORNER_PATCH
    corners = np.concatenate([
        rgb[:p, :p].reshape(-1, 3),
        rgb[:p, W - p:].reshape(-1, 3),
        rgb[H - p:, :p].reshape(-1, 3),
        rgb[H - p:, W - p:].reshape(-1, 3),
    ]).astype(np.float32)
    return np.median(corners, axis=0)


def compute_shift(img: Image.Image, mode: str = "binary"):
    """
    mode: 'binary' — 每个前景像素权重=1（几何重心，不受渐变影响）
          'l2'     — 权重=到背景色的 L2 距离（视觉重心，含光晕强度）
    """
    rgb = np.asarray(img.convert("RGB"), dtype=np.float32)
    H, W, _ = rgb.shape
    bg = estimate_bg(rgb)
    diff = rgb - bg
    l2 = np.sqrt((diff * diff).sum(axis=2))
    fg_mask = l2 >= FG_THRESHOLD

    if mode == "binary":
        weight = fg_mask.astype(np.float32)
    elif mode == "l2":
        weight = np.where(fg_mask, l2, 0.0).astype(np.float32)
    else:
        raise ValueError(f"unknown mode: {mode}")

    total = weight.sum()
    if total <= 0:
        raise RuntimeError("no foreground detected — bg estimate likely wrong")

    ys, xs = np.indices((H, W), dtype=np.float32)
    cx = float((xs * weight).sum() / total)
    cy = float((ys * weight).sum() / total)
    dx = (W / 2.0 - 0.5) - cx
    dy = (H / 2.0 - 0.5) - cy
    fg_count = int(fg_mask.sum())
    return dx, dy, bg, (cx, cy), fg_count


def shift_image(img: Image.Image, dx: float, dy: float, bg: np.ndarray) -> Image.Image:
    idx, idy = int(round(dx)), int(round(dy))
    if idx == 0 and idy == 0:
        return img.copy()
    fill = (int(bg[0]), int(bg[1]), int(bg[2]), 255)
    canvas = Image.new("RGBA", img.size, fill)
    canvas.paste(img.convert("RGBA"), (idx, idy))
    return canvas


def process(path: Path, dry_run: bool, out_dir,
            applied_shift, force_bak: bool, per_file: bool) -> bool:
    if not path.exists():
        print(f"\n{path.name}: MISSING ({path})")
        return False

    img = Image.open(path)
    detected_dx, detected_dy, bg, (cx, cy), fg_count = compute_shift(img)

    if per_file:
        dx, dy = detected_dx, detected_dy
    else:
        dx, dy = applied_shift

    print(f"\n{path.name}")
    print(f"  bg              ≈ ({int(bg[0])},{int(bg[1])},{int(bg[2])})")
    print(f"  fg pixels       = {fg_count:,}")
    print(f"  centroid        = ({cx:.1f}, {cy:.1f})")
    print(f"  detected shift  = ({detected_dx:+.1f}, {detected_dy:+.1f})")
    print(f"  applied shift   = ({dx:+.1f}, {dy:+.1f})")

    if max(abs(dx), abs(dy)) > MAX_SHIFT:
        print(f"  ABORT: |shift| > {MAX_SHIFT}px, suspicious")
        return False

    if dry_run:
        return True

    if out_dir is not None:
        out_path = out_dir / path.name
    else:
        out_path = path
        bak = path.with_suffix(path.suffix + ".bak")
        if bak.exists() and not force_bak:
            print(f"  refuse: {bak.name} already exists (use --force-bak to overwrite)")
            return False
        shutil.copy2(path, bak)
        print(f"  backup    → {bak.name}")

    shifted = shift_image(img, dx, dy, bg)
    shifted.save(out_path, format="PNG", optimize=True)
    print(f"  written   → {out_path}")
    return True


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true", help="print computed shift only")
    ap.add_argument("--out-dir", type=Path, default=None,
                    help="write to this dir instead of overwriting (for preview)")
    ap.add_argument("--shift", type=str, default=None,
                    help="override auto detection, e.g. --shift -15,18")
    ap.add_argument("--per-file", action="store_true",
                    help="use each file's own detected shift (default: use reference file's shift for all)")
    ap.add_argument("--targets", type=str, default=None,
                    help="comma-separated subset of target filenames to process")
    ap.add_argument("--force-bak", action="store_true",
                    help="allow overwriting existing .bak files")
    args = ap.parse_args()

    override = None
    if args.shift:
        parts = args.shift.split(",")
        if len(parts) != 2:
            sys.exit("--shift expects two comma-separated numbers, e.g. -15,18")
        override = (float(parts[0]), float(parts[1]))

    # Decide the applied shift
    if override is not None:
        applied_shift = override
        print(f"Using manual shift: {applied_shift}")
    elif args.per_file:
        applied_shift = (0.0, 0.0)  # unused
        print("Using per-file detected shift")
    else:
        ref_path = ICONSET / REFERENCE
        ref_img = Image.open(ref_path)
        ref_dx, ref_dy, _, _, _ = compute_shift(ref_img)
        applied_shift = (ref_dx, ref_dy)
        print(f"Using reference ({REFERENCE}) shift: ({applied_shift[0]:+.1f}, {applied_shift[1]:+.1f})")

    if args.out_dir:
        args.out_dir.mkdir(parents=True, exist_ok=True)

    if args.targets:
        targets = [t.strip() for t in args.targets.split(",")]
    else:
        targets = TARGETS

    ok_all = True
    for name in targets:
        ok = process(
            ICONSET / name, args.dry_run, args.out_dir,
            applied_shift, args.force_bak, args.per_file
        )
        ok_all = ok_all and ok

    print()
    sys.exit(0 if ok_all else 1)


if __name__ == "__main__":
    main()
