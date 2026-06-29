"""
detect_pdf_markups.py -- Detect colored markups on a PDF.

User marks each plant with a colored dot/stroke directly on the PDF
(in any PDF editor or annotation tool). This script:
  1. Renders the PDF at high DPI.
  2. Masks pixels that are clearly colored (high saturation, not white/black).
  3. Finds connected blobs of colored pixels.
  4. Clusters blobs by hue -- each hue band becomes a group.
  5. Outputs a detection per blob, plus a color swatch per group.

Output files (under <out_dir>):
  detections.csv     -- x,y,area,group_id
  groups.csv         -- group_id,hue,count,symbol_png
  summary.txt        -- image_width,image_height,dpi,...
  pdf_symbols/group_NNN.png  -- color swatch per group
  _pdf_markups_preview.png   -- annotated preview

Usage:  python detect_pdf_markups.py <pdf_path> <out_dir>
            [min_area=20] [max_area=2000] [hue_bucket=15]
"""

import json
import os
import sys
import traceback
from collections import defaultdict


def main():
    if len(sys.argv) < 3:
        sys.stderr.write(
            "usage: detect_pdf_markups.py <pdf_path> <out_dir> "
            "[min_area=20] [max_area=2000] [hue_bucket=15]\n"
        )
        sys.exit(2)
    pdf_path = sys.argv[1]
    out_dir = sys.argv[2]

    min_area = 20
    max_area = 2000
    hue_bucket = 15
    if len(sys.argv) >= 4:
        try: min_area = max(1, int(sys.argv[3]))
        except: pass
    if len(sys.argv) >= 5:
        try: max_area = max(min_area + 10, int(sys.argv[4]))
        except: pass
    if len(sys.argv) >= 6:
        try: hue_bucket = max(5, min(60, int(sys.argv[5])))
        except: pass

    os.makedirs(out_dir, exist_ok=True)
    sym_dir = os.path.join(out_dir, "pdf_symbols")
    os.makedirs(sym_dir, exist_ok=True)

    detections_csv = os.path.join(out_dir, "detections.csv")
    groups_csv = os.path.join(out_dir, "groups.csv")
    summary_txt = os.path.join(out_dir, "summary.txt")
    preview_path = os.path.join(out_dir, "_pdf_markups_preview.png")

    def write_error(msg):
        with open(summary_txt, "w") as f:
            f.write("ERROR\t" + msg + "\n")

    if not os.path.exists(pdf_path):
        write_error(f"PDF not found: {pdf_path}")
        sys.exit(1)

    try:
        import cv2
        import numpy as np
        import fitz
        from PIL import Image
    except ImportError as e:
        write_error(f"Missing Python package: {e}\nInstall: pip install opencv-python pymupdf pillow numpy")
        sys.exit(1)

    try:
        doc = fitz.open(pdf_path)
        if doc.page_count == 0:
            write_error("PDF has no pages")
            sys.exit(1)
        page = doc[0]
        dpi = 300
        mat = fitz.Matrix(dpi / 72, dpi / 72)
        pix = page.get_pixmap(matrix=mat)
        img_pil = Image.frombytes("RGB", (pix.width, pix.height), pix.samples)
        img_arr = np.array(img_pil)
    except Exception as e:
        write_error(f"Render failed: {e}\n{traceback.format_exc()}")
        sys.exit(1)

    # HSV: pick saturated colored pixels (not gray/white/black)
    hsv = cv2.cvtColor(img_arr, cv2.COLOR_RGB2HSV)
    sat = hsv[:, :, 1]
    val = hsv[:, :, 2]
    color_mask = (sat > 90) & (val > 60) & (val < 245)

    if not color_mask.any():
        write_error("No colored markups detected. Make sure your markup color is saturated (not light pastel).")
        sys.exit(1)

    # Connected components on the colored-pixel mask
    mask_uint = color_mask.astype(np.uint8) * 255
    num_labels, labels, stats, centroids = cv2.connectedComponentsWithStats(
        mask_uint, connectivity=8
    )

    blobs = []
    for i in range(1, num_labels):
        area = int(stats[i, cv2.CC_STAT_AREA])
        if area < min_area or area > max_area:
            continue
        cx, cy = centroids[i]
        # Average HSV inside the blob to get its representative color
        blob_pixels = hsv[labels == i]
        avg = blob_pixels.mean(axis=0)
        blobs.append({
            "x": int(round(cx)),
            "y": int(round(cy)),
            "area": area,
            "h": int(avg[0]),
            "s": int(avg[1]),
            "v": int(avg[2]),
        })

    if not blobs:
        write_error(
            f"Found colored pixels but no blob within area range "
            f"[{min_area}, {max_area}]. Either your dots are too tiny / too big, "
            f"or noise filtered everything. Try lower min_area or higher max_area."
        )
        sys.exit(1)

    # Cluster blobs by hue bucket
    by_bucket = defaultdict(list)
    for b in blobs:
        bucket = (b["h"] // hue_bucket) * hue_bucket
        by_bucket[bucket].append(b)

    sorted_buckets = sorted(by_bucket.keys())
    group_ids = {bk: i + 1 for i, bk in enumerate(sorted_buckets)}

    final = []
    for b in blobs:
        bucket = (b["h"] // hue_bucket) * hue_bucket
        b["group_id"] = group_ids[bucket]
        final.append(b)

    # Save a color swatch per group
    groups_info = []
    for bucket in sorted_buckets:
        gid = group_ids[bucket]
        items = by_bucket[bucket]
        # Use mean color of the group for the swatch
        h = int(np.mean([it["h"] for it in items]))
        s = int(np.mean([it["s"] for it in items]))
        v = int(np.mean([it["v"] for it in items]))
        swatch_hsv = np.full((40, 60, 3), (h, s, v), dtype=np.uint8)
        swatch_rgb = cv2.cvtColor(swatch_hsv, cv2.COLOR_HSV2RGB)
        rel_path = f"pdf_symbols/group_{gid:03d}.png"
        Image.fromarray(swatch_rgb).save(os.path.join(out_dir, rel_path))
        groups_info.append((gid, h, len(items), rel_path))

    # Write detections.csv
    with open(detections_csv, "w") as f:
        f.write("x,y,area,group_id\n")
        for b in final:
            f.write(f"{b['x']},{b['y']},{b['area']},{b['group_id']}\n")

    # Write groups.csv
    with open(groups_csv, "w") as f:
        f.write("group_id,hue,count,symbol_png\n")
        for (gid, h, cnt, path) in groups_info:
            f.write(f"{gid},{h},{cnt},{path}\n")

    # Write summary.txt
    with open(summary_txt, "w") as f:
        f.write(f"image_width\t{img_arr.shape[1]}\n")
        f.write(f"image_height\t{img_arr.shape[0]}\n")
        f.write(f"dpi\t{dpi}\n")
        f.write(f"detection_count\t{len(final)}\n")
        f.write(f"group_count\t{len(groups_info)}\n")
        f.write(f"min_area\t{min_area}\n")
        f.write(f"max_area\t{max_area}\n")
        f.write(f"hue_bucket\t{hue_bucket}\n")

    # Annotated preview: draw each detection's bbox/centroid colored by group
    preview = img_arr.copy()
    palette = [(255, 60, 60), (60, 200, 60), (60, 60, 255),
               (255, 200, 0), (255, 60, 200), (60, 200, 200),
               (200, 100, 50), (100, 200, 100), (150, 0, 200),
               (200, 0, 100), (60, 150, 200), (200, 150, 60)]
    for b in final:
        c = palette[(b["group_id"] - 1) % len(palette)]
        cv2.circle(preview, (b["x"], b["y"]), 18, c, 4)
        cv2.putText(
            preview, str(b["group_id"]),
            (b["x"] - 8, b["y"] + 6),
            cv2.FONT_HERSHEY_SIMPLEX, 0.7, c, 2,
        )
    Image.fromarray(preview).save(preview_path)

    print(
        f"detected {len(final)} markups in {len(groups_info)} color groups "
        f"-> {out_dir}"
    )


if __name__ == "__main__":
    main()
