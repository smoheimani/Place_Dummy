"""
detect_pdf_plants.py -- Detect plant symbols on a PDF-only floor plan.

Renders the PDF, finds circular symbols using cv2.HoughCircles, excludes
detections that fall inside the schedule region, clusters detections by
radius, and writes data files for the MAXScript caller.

Outputs (under <out_dir>):
  detections.csv     -- per-detection: x,y,radius,group_id
  groups.csv         -- per-group: group_id,radius,count,symbol_png
  summary.txt        -- image_width,image_height,dpi,schedule bbox
  pdf_symbols/group_NNN.png  -- cropped sample of each group
  _pdf_plants_preview.png    -- annotated plan for user review

Usage:  python detect_pdf_plants.py <pdf_path> <out_dir>

Notes:
* PDF is rendered at 300 DPI to balance speed and detection quality.
* If pytesseract + Tesseract are available the script tries to locate the
  PLANT SCHEDULE region and excludes any circles inside it. If not, it
  proceeds without exclusion.
* HoughCircles params are tuned for typical landscape symbols; tweak if a
  particular project undercounts / overcounts.
"""

import json
import os
import sys
import traceback
from collections import defaultdict


def find_tesseract():
    candidates = [
        r"C:\Program Files\Tesseract-OCR\tesseract.exe",
        r"C:\Program Files (x86)\Tesseract-OCR\tesseract.exe",
        os.path.join(
            os.environ.get("USERPROFILE", ""),
            r"AppData\Local\Programs\Tesseract-OCR\tesseract.exe",
        ),
    ]
    for p in candidates:
        if p and os.path.exists(p):
            return p
    from shutil import which
    return which("tesseract")


def locate_schedule_region(img, pytesseract):
    """Return (left, top, right, bottom) bbox of schedule, or None."""
    try:
        data = pytesseract.image_to_data(
            img, config="--psm 6", output_type=pytesseract.Output.DICT
        )
    except Exception:
        return None
    texts = data["text"]
    lefts = data["left"]
    tops = data["top"]

    sched_top = None
    sched_left = None
    for i, t in enumerate(texts):
        if not t:
            continue
        up = t.upper().strip(" .,:;")
        if up == "PLANT":
            for j in range(i + 1, min(i + 4, len(texts))):
                up2 = texts[j].upper().strip(" .,:;")
                if up2 in ("SCHEDULE", "LIST"):
                    sched_top = max(0, tops[i] - 80)
                    sched_left = max(0, lefts[i] - 120)
                    break
            if sched_top is not None:
                break
    if sched_top is None:
        return None
    end_tokens = ("FURNITURE", "AMENITIES", "MANUFACTURER",
                  "WEBSITE", "MODEL", "PET")
    sched_bottom = img.size[1]
    for i, t in enumerate(texts):
        if not t or tops[i] <= sched_top + 80:
            continue
        up = t.upper()
        if any(end in up for end in end_tokens):
            sched_bottom = max(tops[i] - 30, sched_top + 300)
            break
    return (sched_left, sched_top, img.size[0], sched_bottom)


def main():
    if len(sys.argv) < 3:
        sys.stderr.write(
            "usage: detect_pdf_plants.py <pdf_path> <out_dir> "
            "[sensitivity=5] [min_radius=14] [max_radius=50] [min_group=5]\n"
        )
        sys.exit(2)
    pdf_path = sys.argv[1]
    out_dir = sys.argv[2]

    # Optional tuning args
    sensitivity = 5
    user_min_radius = 14
    user_max_radius = 50
    user_min_group = 5
    if len(sys.argv) >= 4:
        try: sensitivity = max(1, min(10, int(sys.argv[3])))
        except: pass
    if len(sys.argv) >= 5:
        try: user_min_radius = max(4, int(sys.argv[4]))
        except: pass
    if len(sys.argv) >= 6:
        try: user_max_radius = max(user_min_radius + 5, int(sys.argv[5]))
        except: pass
    if len(sys.argv) >= 7:
        try: user_min_group = max(1, int(sys.argv[6]))
        except: pass
    # Sensitivity 1 = very strict (param2 = 70, few hits)
    # Sensitivity 10 = very loose (param2 = 22, many hits)
    hough_param2 = int(round(72 - sensitivity * 5))   # 67 at 1, 22 at 10
    # Default 5 -> param2 = 47

    os.makedirs(out_dir, exist_ok=True)
    sym_dir = os.path.join(out_dir, "pdf_symbols")
    os.makedirs(sym_dir, exist_ok=True)

    detections_csv = os.path.join(out_dir, "detections.csv")
    groups_csv = os.path.join(out_dir, "groups.csv")
    summary_txt = os.path.join(out_dir, "summary.txt")
    preview_path = os.path.join(out_dir, "_pdf_plants_preview.png")

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

    # Try to locate the PLANT SCHEDULE so we can exclude it from detection
    sched_bbox = None
    try:
        import pytesseract
        tess = find_tesseract()
        if tess:
            pytesseract.pytesseract.tesseract_cmd = tess
            sched_bbox = locate_schedule_region(img_pil, pytesseract)
    except ImportError:
        pass

    # HoughCircles on grayscale image (blurred to reduce noise sensitivity)
    gray = cv2.cvtColor(img_arr, cv2.COLOR_RGB2GRAY)
    gray = cv2.GaussianBlur(gray, (5, 5), 1.5)
    try:
        circles = cv2.HoughCircles(
            gray,
            cv2.HOUGH_GRADIENT,
            dp=1.5,
            minDist=max(user_min_radius * 2, 30),   # avoid duplicates near each other
            param1=120,
            param2=hough_param2,
            minRadius=user_min_radius,
            maxRadius=user_max_radius,
        )
    except Exception as e:
        write_error(f"HoughCircles failed: {e}")
        sys.exit(1)

    detections = []
    if circles is not None:
        for (x, y, r) in circles[0]:
            x_i, y_i, r_i = int(round(x)), int(round(y)), int(round(r))
            # Exclude circles inside the schedule bbox
            if sched_bbox is not None:
                if (sched_bbox[0] <= x_i <= sched_bbox[2]
                        and sched_bbox[1] <= y_i <= sched_bbox[3]):
                    continue
            detections.append((x_i, y_i, r_i))

    # Cluster by radius bucket
    BUCKET = 3
    by_bucket = defaultdict(list)
    for d in detections:
        b = (d[2] // BUCKET) * BUCKET
        by_bucket[b].append(d)

    # Filter groups with fewer than MIN_GROUP_SIZE detections (noise)
    MIN_GROUP_SIZE = user_min_group
    valid_buckets = sorted(
        [b for b, items in by_bucket.items() if len(items) >= MIN_GROUP_SIZE]
    )
    group_ids = {b: i + 1 for i, b in enumerate(valid_buckets)}

    # Build final detection list with group ids
    final_detections = []
    for (x, y, r) in detections:
        b = (r // BUCKET) * BUCKET
        if b not in group_ids:
            continue
        final_detections.append((x, y, r, group_ids[b]))

    # Save cropped symbol PNG per group
    groups_info = []
    for b in valid_buckets:
        gid = group_ids[b]
        items = by_bucket[b]
        x, y, r = items[0]
        margin = 6
        crop = img_pil.crop((
            max(0, x - r - margin),
            max(0, y - r - margin),
            min(img_pil.size[0], x + r + margin),
            min(img_pil.size[1], y + r + margin),
        ))
        rel_path = f"pdf_symbols/group_{gid:03d}.png"
        crop.save(os.path.join(out_dir, rel_path))
        groups_info.append((gid, b, len(items), rel_path))

    # Write detections.csv
    with open(detections_csv, "w") as f:
        f.write("x,y,radius,group_id\n")
        for (x, y, r, gid) in final_detections:
            f.write(f"{x},{y},{r},{gid}\n")

    # Write groups.csv
    with open(groups_csv, "w") as f:
        f.write("group_id,radius,count,symbol_png\n")
        for (gid, b, count, rel_path) in groups_info:
            f.write(f"{gid},{b},{count},{rel_path}\n")

    # Write summary.txt
    with open(summary_txt, "w") as f:
        f.write(f"image_width\t{img_arr.shape[1]}\n")
        f.write(f"image_height\t{img_arr.shape[0]}\n")
        f.write(f"dpi\t{dpi}\n")
        if sched_bbox:
            f.write(f"schedule_bbox\t{sched_bbox[0]},{sched_bbox[1]},{sched_bbox[2]},{sched_bbox[3]}\n")
        f.write(f"detection_count\t{len(final_detections)}\n")
        f.write(f"group_count\t{len(groups_info)}\n")

    # Annotated preview
    preview = img_arr.copy()
    palette = [(255, 60, 60), (60, 200, 60), (60, 60, 255),
               (255, 200, 0), (255, 60, 200), (60, 200, 200),
               (200, 100, 50), (100, 200, 100), (150, 0, 200),
               (200, 0, 100), (60, 150, 200), (200, 150, 60)]
    if sched_bbox is not None:
        cv2.rectangle(
            preview, (sched_bbox[0], sched_bbox[1]),
            (sched_bbox[2], sched_bbox[3]), (255, 200, 0), 6
        )
    for (x, y, r, gid) in final_detections:
        c = palette[(gid - 1) % len(palette)]
        cv2.circle(preview, (x, y), r, c, 3)
        cv2.putText(
            preview, str(gid), (x - 8, y + 6),
            cv2.FONT_HERSHEY_SIMPLEX, 0.6, c, 2,
        )
    Image.fromarray(preview).save(preview_path)

    print(
        f"detected {len(final_detections)} symbols in "
        f"{len(groups_info)} groups -> {out_dir}"
    )


if __name__ == "__main__":
    main()
