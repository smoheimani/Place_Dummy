# Place Dummy Tool — README

A 3ds Max tool that imports a landscape DWG, places a Dummy helper at every plant
block insertion, builds a legend column with each block's symbol + a `U1, U2, ...`
label, and adds a frozen CAD reference layer.

This is the **main** placement workflow — use it whenever you have the DWG file.
It is the most accurate of the toolkit because it reads real CAD coordinates and
real block names directly (no image detection guesses).

---

## Files

| File | Purpose |
|---|---|
| `PlaceDummyTool.ms` | The 3ds Max rollout (UI) |
| This README | What you're reading |

The script has no Python dependency.

---

## Requirements

- 3ds Max (any version that supports MAXScript and DWG import)
- AutoCAD `.dwg` file containing the landscape plant blocks

---

## What it does

1. Imports the DWG into a fresh scene.
2. Walks every block insertion and keeps the ones that look like plants:
   - Layer name contains one of: `TREE`, `SHRUB`, `SHRB`, `PALM`, `PLNT`, `PLANT`, `GRND`, `GROUND`
   - AND layer name does NOT contain: `ANNO`, `SCHD`, `LABEL`, `LEGEND`, `TEXT`, `DIM`, `MATCH`
   - OR the block's name contains `TREE`, `SHRUB`, or `PALM`
3. Excludes block names matching annotation patterns: `A$C*`, `*SCHEDULE*`,
   `*LABEL*`, `*MLABEL*`, `*PLANTLIST*`, `*PLANTSCHEDULE*`.
4. Categorizes each plant block (block-name hint first, layer fallback):
   - Contains `PALM` → `Plants_Palms`
   - Contains `SHRUB` / `SHRB` → `Plants_Shrubs`
   - Contains `TREE` → `Plants_Trees`
   - Contains `GRND` / `GROUND` → `Plants_Shrubs`
   - Otherwise → `Plants_Other`
5. Sorts groups: **Trees → Palms → Shrubs → Other**; within a category, by block name alphabetically.
6. Creates one Dummy at every plant insertion, names them `U<group>_<serial>`
   (e.g., `U1_001`, `U1_002`, `U2_001`).
7. Builds a legend column on the right of the scene: one DWG block symbol +
   one text label per group.
8. Translates the whole scene so the dummies' bbox centre is at the origin.
9. Re-imports the DWG and consolidates **all** the imported geometry onto a single
   frozen, gray `CAD_Reference` layer (deleting the auto-created per-layer Max
   layers and sweeping anything on layer `0`).
10. Saves the scene as `placedummy.max` next to the DWG.

---

## Workflow in 3ds Max

1. **Scripting → Run Script…** → pick `PlaceDummyTool.ms`
2. Click **1. Pick CAD File (.dwg)** — choose the DWG.
3. (Optional) Click **2. Pick PDF File (.pdf)** — opens the PDF in your default viewer
   for visual reference. Not used by placement.
4. Click **3. Place Dummies**.
   - Status bar updates as it imports, detects, and saves.
   - **If XREF popups appear** ("Resolve External Reference File"), click
     "Don't Resolve This File" on each — the placement still works from the
     main DWG; XREF-only geometry just won't show up.
   - Final popup tells you how many dummies were placed and across how many groups.
5. (Optional) **Project dummies onto a surface** (see next section).
6. Use **Select Group** (bottom of dialog) to grab all dummies of one group.
   Type the label (e.g., `U1`) and click the button.

---

## Project to surface (optional)

After Place Dummies, all dummies sit at Z=0. To snap them onto a terrain mesh or
plane:

1. **Merge / Import the surface** into the same `placedummy.max` (File → Merge…).
2. In the rollout, click **Pick Surface in viewport** → click the surface object.
3. Click **Project Dummies**.

For each dummy the tool:

- Casts a ray straight down from above the dummy's XY.
- Finds the hit point on the surface.
- Positions the dummy so the **bottom of its box** rests on that point.
- Moves the **pivot** to the bottom of the box (= the ground contact point).
  This way, scaling and rotating happen around the ground contact, which is what
  landscape work expects.

Dummies whose XY falls outside the surface's footprint are left where they are
and counted as "missed" in the result popup.

---

## Naming convention

| Pattern | Meaning |
|---|---|
| `U1_001`, `U1_002`, ... | First group (first Tree block type, alphabetically) |
| `U2_001`, `U2_002`, ... | Second group |
| `LegendExemplar_U1`, `LegendLabel_U1` | Legend column items for group 1 |
| Layer `Plants_Trees` | All `U`-prefixed dummies that were categorised as trees |
| Layer `Plants_Palms` | Palms |
| Layer `Plants_Shrubs` | Shrubs |
| Layer `Plants_Other` | Anything that didn't match Trees / Palms / Shrubs (e.g. custom block names) |
| Layer `Plants_Legend` | The legend column (one symbol + one label per group) |
| Layer `CAD_Reference` | Everything else from the DWG, frozen and gray |
| Layer `0` | Default — kept untouched |

---

## Output files

After Place Dummies the tool writes:

| File | Contents |
|---|---|
| `<DWG folder>/placedummy.max` | The scene |
| `<DWG folder>/_work/letter_key.csv` | `temp_label, block_type, count, layer, category_guess, sample_x, sample_y` — which U-number is which DWG block |
| `<DWG folder>/_work/skipped_blocks.csv` | Blocks that were rejected, with the reason (`not-a-plant`, `excluded-pattern`) |
| `<DWG folder>/_work/place_dummy_tool.log` | Debug log |

---

## Tips

- **`letter_key.csv` is the most useful artifact** — open it in Excel after placement
  to see exactly which block_type is U1, U2, U3, etc., and how many of each.
- **`skipped_blocks.csv` is the debugging artifact** — if a real plant is missing
  from the scene, search this file to see if it was rejected and why.
- **XREF-only geometry is missing on purpose** — if you click "Don't Resolve This File"
  during DWG import, blocks that live inside an unresolved XREF won't import.
  The plant blocks in the main DWG still work fine.
- **Re-running Place Dummies resets the scene** — `placedummy.max` is overwritten.
  Save your work to a separate file before re-running if you've made manual edits.
- **The CAD_Reference layer is frozen** — you can't accidentally select or move it.
  Unfreeze in the Layer Explorer if you ever need to edit it.

---

## Troubleshooting

**"No plant blocks found in DWG" popup**
- Check `_work/skipped_blocks.csv` — every block in the DWG appears there with the
  rejection reason. If your plant blocks are listed as `not-a-plant`, the layer
  filter is missing your project's naming convention. Tell me what your layer
  names look like and I'll widen the filter.

**Way fewer dummies than the schedule says**
- The DWG only contains a subset of the plants (some live on XREF sheets you
  declined). Check `letter_key.csv` to see per-block counts.

**Way more dummies than expected**
- Some block was wrongly included. Find it in `letter_key.csv` (it'll be a
  high-count group). Tell me the block name and I'll add an exclusion.

**Dummies are tiny / huge in viewport**
- Dummy box size is hardcoded at `24x24x24` Max units. Select all dummies after
  placement and scale uniformly to fit your project scale.

**"MAXScript FileIn Exception" pop-up when you Run Script**
- Always reload the rollout fresh — `try ( destroyDialog ::PlaceDummyTool ) catch ()`
  is at the top of the script so re-running just refreshes the dialog. If you
  get a real syntax error, paste the line number and we'll patch.

---

## Related tools in this toolkit

| Script | When to use |
|---|---|
| `PlaceDummyTool.ms` | **This one. Use whenever you have a DWG.** Most accurate. |
| `PlaceDummyTool_PDFOnly.ms` | No DWG, but the PDF has reliably-drawn circular plant symbols. Auto-detects via HoughCircles. Less reliable. |
| `PlaceDummyTool_PDFMarkup.ms` | No DWG. You mark each plant on the PDF with a colored dot. Most reliable PDF-only mode. See `README_PlaceDummy_PDF_MarkedUp.md` for details. |
