# Place Dummy with PDF Markup — README

A 3ds Max tool that places dummy helpers based on **colored marks you draw on a PDF**.
When you don't have a CAD file, this is the most reliable way to get plants from a
landscape PDF into Max — you mark each plant manually with a colored dot, and the
tool finds those marks and places dummies grouped by color.

---

## What it does

1. You open the landscape PDF in any annotation tool and mark each plant with a colored dot.
2. Each plant species gets its own distinct color (Species A = red, B = blue, C = green, D = yellow, etc.).
3. You save the marked-up PDF.
4. The tool detects every colored mark on the PDF, groups them by hue, and places
   one dummy per mark in 3ds Max.
5. Dummies are named `U<group>_<serial>` (e.g., `U1_001`, `U1_002`, `U2_001`).
   Same color → same `U` number → same group.
6. Each dummy's **pivot is set to the bottom of its box** automatically (so it sits
   on a ground plane and rotates / scales around the ground contact point).

---

## Files

| File | Purpose |
|---|---|
| `PlaceDummyTool_PDFMarkup.ms` | The 3ds Max rollout (UI) |
| `detect_pdf_markups.py` | Python helper that renders the PDF and finds colored blobs |
| This README | What you're reading |

---

## Requirements

- 3ds Max (any version with MAXScript)
- Python 3 on PATH (any 3.7+)
- Python packages: `opencv-python`, `pymupdf`, `pillow`, `numpy`
  - Install with: `pip install opencv-python pymupdf pillow numpy`

---

## How to mark up the PDF

1. Open the landscape PDF in your annotation tool of choice
   (Adobe Acrobat / Reader, Foxit, Bluebeam, Preview, Microsoft Edge, etc.).
2. Use the freehand / pencil / dot annotation tool.
3. For each species, **pick one distinct color and use it for every instance of that species**.
4. **Make small, solid dots** (about 5–10 px across at view scale). Don't draw lines, swooshes, or strokes.
5. **Use saturated colors** — pure red, pure blue, pure green, pure yellow.
   Avoid pastels, near-grays, or very dark colors.
6. **Keep dots of different colors apart** (don't overlap).
   If dots of the same color are very close, they may merge into one detection.
7. **Save / export** the marked PDF (with annotations flattened or burned in is best).

---

## Workflow in 3ds Max

1. **Scripting → Run Script…** → pick `PlaceDummyTool_PDFMarkup.ms`
2. Click **1. Pick PDF File** — choose the marked-up PDF.
3. (Optional) Adjust the **tuning spinners** at the top of the dialog (see below).
4. Click **2. Detect Markups** — runs the Python script (10–30 seconds).
   The status line shows how many marks and groups were found.
5. Click **3. Show Preview Image** — opens an annotated picture of your PDF with every
   detection circled and labeled with its group number.
   **Always check the preview before placing.**
6. If the preview looks right, click **4. Place Dummies** — creates the dummies in the scene.
7. (Optional) Click **Pick Surface in viewport** + **Project Dummies** to snap dummies onto
   a terrain mesh. This also moves each dummy's pivot to the bottom of its box.
8. (Optional) Use the **Select Group** field to grab all dummies of one color
   (type `U1`, click Select Group, etc.).

---

## Parameters (the tuning spinners)

### Min Area (px) — default 20

The *minimum* number of colored pixels a blob must contain to count as a markup.

- **Low value** (e.g., **5**) → catches even **tiny dots**.
  Use this if some of your marks are very small or thin.
- **High value** (e.g., **100**) → **filters out small ink noise**.
  Use this if you see false positives from small inkblots / smudges / artifacts.

**Symptom → fix:**
- "Some of my dots aren't being detected" → **lower** Min Area
- "I see junk detections that aren't my marks" → **raise** Min Area

### Max Area (px) — default 2000

The *maximum* number of colored pixels a blob can have before it's ignored.

- **Low value** (e.g., **500**) → filters out **large highlighted regions** (long strokes, smears).
- **High value** (e.g., **8000**) → allows **larger marks** (big circles, fat marker dots).

**Symptom → fix:**
- "My larger dots aren't being detected" → **raise** Max Area
- "A whole highlighted area is becoming one detection" → **lower** Max Area

### Hue Bucket (degrees) — default 15

The width of the "hue bin" used to group colors. OpenCV's hue scale runs 0–180,
so the bucket is in degrees on that scale.

- **Low value** (e.g., **5°**) → **NARROW bucket** → better at **separating similar colors**.
  Each shade gets its own group.
- **High value** (e.g., **30°**) → **WIDE bucket** → similar shades **merge** into one group.

**Symptom → fix:**
- "I used 4 colors but tool only found 3 groups" → colors are merging → **lower** Hue Bucket
- "I used 4 colors but tool found 5 or 6 groups" → one color is splitting (e.g., light red and dark red treated separately) → **raise** Hue Bucket
- "I used 4 colors and tool found 4 groups" → Hue Bucket is right

**Quick reference:**
- Default 15° works for 4 well-spread colors (red, yellow, green, blue).
- For similar shades (red, orange, pink, magenta) try 8°.
- For very saturated, very distinct colors you can use 25–30° and still keep them apart.
- 180° divided by your Hue Bucket = roughly the max number of distinct color groups the tool can recognize.

---

## Output files

After running Detect Markups, the tool writes these to `<PDF folder>/_work/`:

| File | Contents |
|---|---|
| `detections.csv` | One row per detected mark: `x, y, area, group_id` |
| `groups.csv` | One row per color group: `group_id, hue, count, symbol_png` |
| `summary.txt` | Image dimensions, DPI, total counts |
| `pdf_symbols/group_NNN.png` | A color swatch for each group (used as the legend symbol) |
| `_pdf_markups_preview.png` | Annotated preview showing every detection circled |
| `_python_stdout.txt` | Python's stdout/stderr — useful for diagnosing failures |

---

## Coordinate mapping

The PDF is rendered at **300 DPI**, then:

- **1 PDF pixel = 1 Max unit**
- A 7200×5400 px PDF becomes a 7200×5400 unit scene
- The PDF Y axis is top-down, the Max Y axis is bottom-up, so the tool flips Y for you
- The dummy cloud is centered around the origin

If your project needs real-world dimensions (e.g., feet or meters), select all dummies
in Max after placement and scale them uniformly to the right size.

---

## Troubleshooting

**"Detection failed" popup**
- Check `_work/_python_stdout.txt` for the Python error message
- Make sure Python is on PATH (`python --version` from cmd should work)
- Make sure the packages are installed (`pip install opencv-python pymupdf pillow numpy`)

**"No colored markups detected"**
- Your marks aren't saturated enough — try drawing again with brighter / more vivid colors
- Make sure annotations are *embedded* in the saved PDF, not external annotation comments

**Way fewer dummies than marks**
- Lower Min Area (try 5)
- Raise Max Area (try 8000)
- Click Show Preview to see what's being detected vs missed
- If close dots are merging into one detection, space them further apart in the PDF and re-export

**Way more dummies than marks**
- Raise Min Area to filter ink noise
- Sometimes thin anti-aliased edges of one mark are being detected as separate tiny blobs — raise Min Area

**Wrong number of color groups**
- See "Hue Bucket" section above

**Dummies are at wrong scale**
- Pixels are mapped 1:1 to Max units. After placement, select all dummies and scale
  uniformly to whatever real-world scale you need.

---

## Naming convention

| Pattern | Meaning |
|---|---|
| `U1_001`, `U1_002`, ... | First color group (lowest hue in 0–180 range) |
| `U2_001`, `U2_002`, ... | Second color group |
| `LegendLabel_U1`, `LegendSymbol_U1`, ... | Legend column items |
| `Plants_Detected` (layer) | All detected dummies |
| `Plants_Legend` (layer) | The legend column on the right side of the scene |

---

## Related tools in this toolkit

| Script | When to use |
|---|---|
| `PlaceDummyTool.ms` | **Use this when you HAVE a DWG** — most accurate (real coordinates, real block names) |
| `PlaceDummyTool_PDFOnly.ms` | Auto-detects circular plant symbols from a PDF (no markup needed) — **less reliable**, fast for clean PDFs |
| `PlaceDummyTool_PDFMarkup.ms` | This one. **Use when no DWG is available** and you want full control over what gets a dummy. |

---

## Tips

- **Always test on a small marked area first** before marking up an entire plan.
- **Re-run Detect freely** — adjusting the spinners and clicking Detect again is fast.
- **Use the preview image** — it's the single best diagnostic tool. Open it side-by-side
  with your marked PDF to see exactly what the tool sees.
- **Save the PDF with annotations flattened** if your annotation tool offers that option —
  flattened annotations are most reliably rasterized in the rendered image.
- **Use the same color picker across markings** for one species — don't pick "red"
  from the dropdown for some and "color picker" for others, even if they look the
  same on screen.
