"""
Extract clean legend hatch swatches from the landscape PDF.

For each plant code listed in pdf_plant_text_positions.json, crops the SYMBOL
cell to the left of the code text (the cell contains the hatch pattern or
point-symbol for that species) and saves it as a PNG.

Output: _work/legend_swatches/<CODE>.png
        _work/legend_swatches/_index.json  (code -> bbox + pattern flag)

Uses the existing page_0_300dpi.png render (10200 x 6600).
"""

import json
import os
from PIL import Image, ImageDraw

BASE = r'd:/Utilities/Place_Dummy/_work'
PAGE_PNG = os.path.join(BASE, 'page_0_300dpi.png')
POS_JSON = os.path.join(BASE, 'pdf_plant_text_positions.json')
OUT_DIR = os.path.join(BASE, 'legend_swatches')
INDEX_JSON = os.path.join(OUT_DIR, '_index.json')
PREVIEW_PNG = os.path.join(BASE, 'legend_swatches_preview.png')

MB_W = 1584                    # unrotated mediabox width (points)
SCALE = 300.0 / 72.0           # 300 dpi render

# Display pixel = function of (unrotated cx, cy) for page rotation 270
def u2disp_px(cx, cy):
    return (cy * SCALE, (MB_W - cx) * SCALE)

# Swatch cell geometry (measured from probe): the SYMBOL cell sits ~150 px
# to the LEFT of the code-text center, and is ~130 wide x 65 tall.
SWATCH_DX     = -150            # offset from code-text X to swatch center X
SWATCH_DY     = 0               # same row
SWATCH_W      = 130
SWATCH_H      = 65

# Species sections (informational; everything gets cropped the same way)
HATCH_SPECIES = {
    'grasses':     ['HYM', 'MUH', 'FAK'],
    'groundcover': ['FIC', 'GLA', 'HEL', 'ILV', 'JUP', 'SAL', 'TRA'],
    'sod_mulch':   ['MULCH', 'SOD', 'TRF'],
    'shrub_hatch': ['CAA', 'CHR', 'CES', 'PHI', 'ZAM', 'HAM', 'POD', 'PSY', 'SER'],
}
ALL_AREA_CODES = sorted({c for v in HATCH_SPECIES.values() for c in v})

def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    with open(POS_JSON) as f:
        positions = json.load(f)

    # Build {code -> leftmost (px, py)}
    all_inst = {}
    for d in positions:
        px, py = u2disp_px(d['cx'], d['cy'])
        all_inst.setdefault(d['code'], []).append((px, py))
    left = {c: min(lst, key=lambda p: p[0]) for c, lst in all_inst.items()}

    page = Image.open(PAGE_PNG)

    index = {}
    annotated = page.copy()
    draw = ImageDraw.Draw(annotated)

    for code in ALL_AREA_CODES:
        if code not in left:
            print(f'  {code:6s}: NOT FOUND in text positions')
            continue
        cx, cy = left[code]
        swatch_cx = cx + SWATCH_DX
        swatch_cy = cy + SWATCH_DY
        x0 = int(swatch_cx - SWATCH_W / 2)
        y0 = int(swatch_cy - SWATCH_H / 2)
        x1 = int(swatch_cx + SWATCH_W / 2)
        y1 = int(swatch_cy + SWATCH_H / 2)

        # Clamp
        x0 = max(0, x0); y0 = max(0, y0)
        x1 = min(page.width, x1); y1 = min(page.height, y1)

        swatch = page.crop((x0, y0, x1, y1))
        out_path = os.path.join(OUT_DIR, f'{code}.png')
        swatch.save(out_path)
        index[code] = {
            'bbox': [x0, y0, x1, y1],
            'code_text_pixel': [int(cx), int(cy)],
            'category': next(k for k, v in HATCH_SPECIES.items() if code in v),
        }
        # Annotate
        draw.rectangle((x0, y0, x1, y1), outline='blue', width=2)
        draw.text((cx + 10, cy - 8), code, fill='red')
        print(f'  {code:6s}: bbox ({x0},{y0})-({x1},{y1})')

    with open(INDEX_JSON, 'w') as f:
        json.dump(index, f, indent=2)
    print(f'\nindex -> {INDEX_JSON}')

    # Crop a preview of the legend region with all swatch boxes drawn
    legend_crop = annotated.crop((0, 3200, 800, 5200))
    legend_crop.save(PREVIEW_PNG)
    print(f'preview -> {PREVIEW_PNG}  ({legend_crop.size})')

    # Build a contact-sheet of all extracted swatches stacked vertically with labels
    pad = 4
    label_h = 18
    sheet_w = SWATCH_W + 200
    sheet_h = sum(SWATCH_H + label_h + pad for _ in index)
    sheet = Image.new('RGB', (sheet_w, sheet_h), 'white')
    sdraw = ImageDraw.Draw(sheet)
    y = 0
    for code in sorted(index):
        sw = Image.open(os.path.join(OUT_DIR, f'{code}.png'))
        sheet.paste(sw, (0, y))
        sdraw.text((SWATCH_W + 10, y + 20), f'{code}  ({index[code]["category"]})', fill='black')
        y += SWATCH_H + label_h + pad
    sheet.save(os.path.join(BASE, 'legend_swatches_contact_sheet.png'))
    print(f'contact sheet -> legend_swatches_contact_sheet.png')

if __name__ == '__main__':
    main()
