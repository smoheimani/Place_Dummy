"""
ocr_schedule.py -- OCR helper for PlaceDummyTool.

Renders a PDF page, locates the plant schedule, OCRs it, and produces:
  * <out_txt> -- one line per species, format "Botanical / Common" (no section
                 headers, no codes, no quantities, no dimensions, no notes)
  * <out_dir>/symbols/symbol_NNN.png -- a cropped image of the SYMBOL column
                 for each species row, indexed in the same order as the txt lines
  * <out_dir>/symbols/index.txt -- "NNN <TAB> species_text" mapping

Usage:  python ocr_schedule.py <pdf_path> <output_txt_path>

The output dir for symbols is the same directory as <output_txt_path>.
"""

import os
import re
import sys
import traceback


SECTION_KEYWORDS = (
    "TREE", "TREES", "PALM", "PALMS", "SHRUB", "SHRUBS",
    "GROUND COVER", "GROUNDCOVER", "GROUND COVERS", "GROUNDCOVERS",
    "LAWN", "SOD", "MULCH", "AREA", "AREAS",
    "LOT TREE", "LOT TREES", "STREET TREE", "STREET TREES",
    "ACCENT TREE", "ACCENT TREES", "SPECIMEN TREE", "SPECIMEN TREES",
    "PLANT SCHEDULE", "PLANT LIST",
)

END_TOKENS = (
    "FURNITURE", "AMENITIES", "MANUFACTURER", "SUPPLIER", "WEBSITE",
    "WEBSITTE", "QUANTITY", "MODEL", "PET", "BENCH", "TRASH",
)

_BOILERPLATE_PATTERNS = [
    re.compile(r"©\s*\d{4}\s+[A-Z][A-Z\s\.\+]+(?:PARTNERS|ARCHITECTS?|ASSOC[A-Z\.]*)\.?", re.I),
    re.compile(r"THE DESIGN AND DRAWINGS HEREIN[^a-z]*", re.I),
    re.compile(r"LANDSCAPE ARCHITECT AND ARE PROTECTED", re.I),
    re.compile(r"UNDER THE COPYRIGHT PROTECTION ACT", re.I),
    re.compile(r"ALL RIGHTS RESERVED", re.I),
]


def find_tesseract():
    candidates = [
        r"C:\Program Files\Tesseract-OCR\tesseract.exe",
        r"C:\Program Files (x86)\Tesseract-OCR\tesseract.exe",
        os.path.join(os.environ.get("USERPROFILE", ""),
                     r"AppData\Local\Programs\Tesseract-OCR\tesseract.exe"),
    ]
    for p in candidates:
        if p and os.path.exists(p):
            return p
    from shutil import which
    return which("tesseract")


def strip_boilerplate(line: str) -> str:
    s = line
    for pat in _BOILERPLATE_PATTERNS:
        s = pat.sub(" ", s)
    return re.sub(r"\s+", " ", s).strip()


def is_section_header(text: str) -> bool:
    up = text.upper().strip()
    if not up:
        return False
    # Column header row of the schedule table
    if "BOTANICAL" in up and ("COMMON" in up or "NAME" in up):
        return True
    if "SYMBOL" in up and ("CODE" in up or "QTY" in up):
        return True
    if not any(k in up for k in SECTION_KEYWORDS):
        return False
    alpha_count = sum(1 for c in text if c.isalpha())
    lower_count = sum(1 for c in text if c.islower())
    if alpha_count == 0:
        return False
    return alpha_count <= 5 or (lower_count / alpha_count) <= 0.3


def is_botanical_line(text: str) -> bool:
    """A line that looks like a botanical name: 'Genus species' pattern."""
    return bool(re.match(r"^[A-Z][a-z]+\s+[a-z]+", text.strip()))


def looks_like_plant_name(text: str) -> bool:
    """A line that probably names a plant (botanical or common)."""
    t = text.strip()
    if not t:
        return False
    alpha = sum(1 for c in t if c.isalpha())
    if alpha < 4:
        return False
    if is_section_header(t):
        return False
    has_real_word = any(
        sum(1 for c in w if c.isalpha()) >= 4
        for w in t.split()
    )
    if not has_real_word:
        return False
    return True


def clean_name_line(line: str) -> str:
    """Extract plant-name tokens from a noisy OCR line."""
    tokens = re.findall(r"[A-Za-z][A-Za-z'\.\-]{2,}", line)
    drop = {"HT", "SPR", "CAL", "OC", "DBH", "MIN", "MAX", "TYP", "REQ",
            "TBD", "PPP", "OA", "GA", "GW", "ARE", "THE"}
    keep = [t for t in tokens if t.upper() not in drop]
    return " ".join(keep).strip()


def locate_schedule_region(img, pytesseract):
    data = pytesseract.image_to_data(
        img, config="--psm 6", output_type=pytesseract.Output.DICT
    )
    texts = data["text"]
    lefts, tops = data["left"], data["top"]
    schedule_top, schedule_left = None, None
    for i, t in enumerate(texts):
        if not t:
            continue
        up = t.upper().strip(" .,:;")
        if up == "PLANT":
            for j in range(i + 1, min(i + 4, len(texts))):
                up2 = texts[j].upper().strip(" .,:;")
                if up2 in ("SCHEDULE", "LIST"):
                    schedule_top = tops[i]
                    schedule_left = lefts[i]
                    break
            if schedule_top is not None:
                break
    if schedule_top is None:
        for i, t in enumerate(texts):
            if not t:
                continue
            up = t.upper()
            if up in ("TREES", "PALMS", "SHRUBS", "LAWN", "GROUND", "COVERS"):
                schedule_top = max(0, tops[i] - 60)
                schedule_left = max(0, lefts[i] - 60)
                break
    if schedule_top is None:
        return None
    schedule_bottom = img.size[1]
    for i, t in enumerate(texts):
        if not t or tops[i] <= schedule_top + 50:
            continue
        up = t.upper()
        if any(end in up for end in END_TOKENS):
            schedule_bottom = max(tops[i] - 30, schedule_top + 200)
            break
    return (
        max(0, schedule_left - 80),
        max(0, schedule_top - 40),
        img.size[0],
        schedule_bottom,
    )


def find_code_column_x(tokens):
    """Find the left edge of the CODE column by locating the 'CODE' header."""
    # Prefer the column header token "CODE"
    for t in tokens:
        if t["text"].upper().strip(" .,:;|") == "CODE":
            return t["left"]
    # Fallback: the BOTANICAL header tells us where the plant-name column starts;
    # the CODE column is to the left.
    for t in tokens:
        if t["text"].upper().strip(" .,:;|") == "BOTANICAL":
            return max(0, t["left"] - 350)
    return None


def find_botanical_column_x(tokens):
    """Find the left edge of the BOTANICAL/COMMON NAME column."""
    for t in tokens:
        if t["text"].upper().strip(" .,:;|") == "BOTANICAL":
            return t["left"]
    return None


def main():
    if len(sys.argv) < 3:
        sys.stderr.write("usage: ocr_schedule.py <pdf_path> <output_txt_path>\n")
        sys.exit(2)
    pdf_path = sys.argv[1]
    out_path = sys.argv[2]

    def write_error(msg):
        with open(out_path, "w", encoding="utf-8") as f:
            f.write("ERROR: " + msg + "\n")

    if not os.path.exists(pdf_path):
        write_error(f"PDF not found: {pdf_path}")
        sys.exit(1)

    try:
        import pytesseract
    except ImportError:
        write_error("pytesseract not installed. pip install pytesseract")
        sys.exit(1)

    tess = find_tesseract()
    if tess is None:
        write_error("Tesseract not installed. winget install UB-Mannheim.TesseractOCR")
        sys.exit(1)
    pytesseract.pytesseract.tesseract_cmd = tess

    try:
        import fitz
        from PIL import Image
    except ImportError as e:
        write_error(f"Missing: {e}. pip install pymupdf pillow")
        sys.exit(1)

    try:
        doc = fitz.open(pdf_path)
        if doc.page_count == 0:
            write_error("PDF has no pages")
            sys.exit(1)
        page = doc[0]
        mat = fitz.Matrix(300 / 72, 300 / 72)
        pix = page.get_pixmap(matrix=mat)
        img = Image.frombytes("RGB", (pix.width, pix.height), pix.samples)
    except Exception as e:
        write_error(f"Render failed: {e}\n{traceback.format_exc()}")
        sys.exit(1)

    out_dir = os.path.dirname(out_path) or "."
    sym_dir = os.path.join(out_dir, "symbols")
    os.makedirs(sym_dir, exist_ok=True)
    # Clean previous symbols
    for fn in os.listdir(sym_dir):
        if fn.startswith("symbol_") or fn == "index.txt":
            try:
                os.remove(os.path.join(sym_dir, fn))
            except Exception:
                pass

    bbox = locate_schedule_region(img, pytesseract)
    if bbox is None:
        # Fall back to whole page
        crop = img
    else:
        crop = img.crop(bbox)

    # OCR cropped image with bounding boxes
    try:
        data = pytesseract.image_to_data(
            crop, config="--psm 6", output_type=pytesseract.Output.DICT
        )
    except Exception as e:
        write_error(f"OCR failed: {e}\n{traceback.format_exc()}")
        sys.exit(1)

    n = len(data["text"])
    tokens = []
    lines_by_key = {}   # (block, par, line) -> list of token dicts
    for i in range(n):
        text = data["text"][i].strip()
        if not text:
            continue
        tok = {
            "text": text,
            "left": data["left"][i],
            "top": data["top"][i],
            "right": data["left"][i] + data["width"][i],
            "bottom": data["top"][i] + data["height"][i],
        }
        tokens.append(tok)
        key = (data["block_num"][i], data["par_num"][i], data["line_num"][i])
        lines_by_key.setdefault(key, []).append(tok)

    code_x = find_code_column_x(tokens)
    botanical_x = find_botanical_column_x(tokens)
    if code_x is None:
        code_x = int(crop.size[0] * 0.10)
    # plant-name column starts at the BOTANICAL header (if found), else right
    # of CODE column by a reasonable amount
    if botanical_x is not None:
        text_x_min = botanical_x - 40   # small margin in case OCR offsets
    else:
        text_x_min = code_x + 150
    # SIZE column starts to the right of plant names; drop tokens past it so
    # we don't pick up dimensions
    size_x_min = None
    for t in tokens:
        if t["text"].upper().strip(" .,:;|") == "SIZE":
            size_x_min = t["left"]
            break
    if size_x_min is None:
        # Heuristic: SIZE typically begins about 700-800 px right of BOTANICAL
        size_x_min = (botanical_x or code_x or 0) + 700

    # Build species_rows from Tesseract's own line grouping
    species_rows = []
    for key in sorted(lines_by_key):
        row_tokens = sorted(lines_by_key[key], key=lambda t: t["left"])
        # Only tokens in the BOTANICAL/COMMON NAME column
        name_tokens = [
            t for t in row_tokens
            if text_x_min <= t["left"] < size_x_min
        ]
        if not name_tokens:
            continue
        text = " ".join(t["text"] for t in name_tokens)
        text = strip_boilerplate(text)
        if is_section_header(text):
            continue
        cleaned = clean_name_line(text)
        if not looks_like_plant_name(cleaned):
            continue
        species_rows.append({
            "text": cleaned,
            "top": min(t["top"] for t in name_tokens),
            "bottom": max(t["bottom"] for t in name_tokens),
        })

    # Pair consecutive species rows into "Botanical / Common"
    # Heuristic: if two rows are close together (within ~1.5 row heights),
    # pair them. If only one row, keep it alone.
    if not species_rows:
        with open(out_path, "w", encoding="utf-8") as f:
            f.write("")
        return

    # Pair a botanical line with the NEXT non-botanical line (the common name).
    # If two botanicals are consecutive, leave the first alone.
    paired = []
    i = 0
    while i < len(species_rows):
        cur = species_rows[i]
        if is_botanical_line(cur["text"]) and i + 1 < len(species_rows):
            nxt = species_rows[i + 1]
            if not is_botanical_line(nxt["text"]):
                paired.append({
                    "text": cur["text"] + " / " + nxt["text"],
                    "top": cur["top"],
                    "bottom": nxt["bottom"],
                })
                i += 2
                continue
        paired.append(cur)
        i += 1

    # Save symbol crops and write the index
    lines_out = []
    idx_lines = []
    for k, p in enumerate(paired, start=1):
        sym_top = max(0, p["top"] - 20)
        sym_bottom = min(crop.size[1], p["bottom"] + 20)
        sym_left = 0
        sym_right = max(20, code_x - 10)
        symbol = crop.crop((sym_left, sym_top, sym_right, sym_bottom))
        sym_path = os.path.join(sym_dir, f"symbol_{k:03d}.png")
        try:
            symbol.save(sym_path)
        except Exception:
            pass
        lines_out.append(p["text"])
        idx_lines.append(f"{k:03d}\t{p['text']}")

    with open(out_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines_out))
    with open(os.path.join(sym_dir, "index.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(idx_lines))

    print(
        f"OCR ok: {len(lines_out)} species lines + {len(lines_out)} symbol crops -> {out_path}"
    )


if __name__ == "__main__":
    main()
