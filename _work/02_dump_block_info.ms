--==============================================================
-- 02_dump_block_info.ms
-- Purpose:  Open a fresh scene, import the landscape DWG,
--           then for every distinct plant-block type (TREE-*,
--           SHRUB-*, PALM-*) dump bounding-box dimensions, layer,
--           count, and one sample position to a CSV.
--           Plus: tries to render a thumbnail of each block via the
--           viewport screenshot (wrapped in try -- failure won't
--           crash the script). Output:
--             D:\Utilities\Place_Dummy\_work\block_info.csv
--             D:\Utilities\Place_Dummy\_work\block_thumbs\*.png   (if renders worked)
--             D:\Utilities\Place_Dummy\_work\dump_block_info.log
--
-- HOW TO RUN:
--   1. CLOSE any open instances of 3ds Max first (to free file locks).
--   2. Re-open 3ds Max.
--   3. Scripting > Run Script... -> this file.
--   4. DWG import dialog: same setting as before
--      ("Derive AutoCAD Primitives by: Layer, Blocks as Node Hierarchy").
--   5. Wait ~30s. Script will NOT modify placedummy.max.
--==============================================================

(
    local logPath = @"D:\Utilities\Place_Dummy\_work\dump_block_info.log"
    local csvPath = @"D:\Utilities\Place_Dummy\_work\block_info.csv"
    local dwgPath = @"D:\Utilities\Place_Dummy\LandscapeArea.dwg"
    local thumbDir= @"D:\Utilities\Place_Dummy\_work\block_thumbs\"

    -- Make sure thumb directory exists, harmless if already there
    try ( makeDir thumbDir all:true ) catch ()

    -- Defensively remove any previous log so re-runs don't fail on a lock
    if doesFileExist logPath do ( try (deleteFile logPath) catch () )
    if doesFileExist csvPath do ( try (deleteFile csvPath) catch () )

    local logf = createFile logPath
    if logf == undefined do (
        messageBox ("Could not create log at " + logPath + ". Close any 3ds Max instances and try again.")
        return undefined
    )
    fn logln s f = ( format "%\n" s to:f; flush f )

    logln "=== 02_dump_block_info.ms start ===" logf

    resetMaxFile #noprompt
    units.SystemType = #inches

    logln ("importing " + dwgPath) logf
    local okImp = false
    try ( okImp = importFile dwgPath ) catch ( logln ("IMPORT EXCEPTION: " + getCurrentException()) logf )
    logln ("import ok=" + (okImp as string) + "  objects=" + (objects.count as string)) logf

    -- helper -- strip "Block:" prefix and xref "$0$" nesting
    fn extractBlockName n = (
        local s = n
        if (substring s 1 6) == "Block:" do s = substring s 7 -1
        local i = findString s "$0$"
        while i != undefined do (
            s = substring s (i + 3) -1
            i = findString s "$0$"
        )
        s
    )

    local plantPrefixes = #("TREE-PALM", "TREE-DCID", "TREE-EVGR", "TREE-SIMP", "SHRUB-LRG", "SHRUB-TROP", "SHRUB-")
    fn isPlantBlock bname = (
        local hit = false
        for p in plantPrefixes while (not hit) do (
            if matchPattern bname pattern:(p + "*") do hit = true
        )
        hit
    )

    -- Collect: per block type -- count, sample obj, accumulate bbox sizes
    local typeNames     = #()
    local typeCounts    = #()
    local typeSamples   = #()      -- one node per type (for thumb + sample pos)
    local typeBBoxW     = #()      -- bbox X size of sample
    local typeBBoxH     = #()      -- bbox Y size of sample
    local typeLayer     = #()      -- layer of sample

    for o in objects do (
        if classOf o == LinkComposite do (
            local bn = extractBlockName o.name
            if isPlantBlock bn do (
                local idx = findItem typeNames bn
                if idx == 0 then (
                    append typeNames bn
                    append typeCounts 1
                    append typeSamples o
                    local mn = o.min
                    local mx = o.max
                    append typeBBoxW (mx.x - mn.x)
                    append typeBBoxH (mx.y - mn.y)
                    append typeLayer (try (o.layer.name) catch ("?"))
                ) else (
                    typeCounts[idx] += 1
                )
            )
        )
    )
    logln ("distinct plant block types: " + (typeNames.count as string)) logf

    -- Write CSV
    local csvf = createFile csvPath
    format "block_type,count,bbox_w,bbox_h,layer,sample_x,sample_y,sample_z\n" to:csvf
    for i = 1 to typeNames.count do (
        local s = typeSamples[i]
        format "%,%,%,%,%,%,%,%\n" typeNames[i] typeCounts[i] typeBBoxW[i] typeBBoxH[i] typeLayer[i] s.pos.x s.pos.y s.pos.z to:csvf
    )
    close csvf
    logln ("wrote csv: " + csvPath) logf

    -- Try to render a thumbnail of each block via viewport screenshot.
    -- Heavily wrapped so any failure just logs and keeps going.
    try (
        actionMan.executeAction 0 "275"      -- Views: Top
        viewport.setLayout #layout_1
        viewport.activeViewport = 1
        viewport.SetShowGrids false
        viewport.SetRenderLevel #wireframe
    ) catch ( logln ("viewport setup warn: " + getCurrentException()) logf )

    local renderedOK = 0
    for i = 1 to typeNames.count do (
        local samp = typeSamples[i]
        local bn   = typeNames[i]
        try (
            clearSelection()
            select samp
            max tool zoomextents
            actionMan.executeAction 0 "310"  -- Tools: Zoom Extents Selected
            redrawViews()
            local bm = gw.getViewportDib()
            local safe = (substituteString bn "-" "_")
            local outPath = (thumbDir + "blk_" + safe + ".png")
            bm.filename = outPath
            save bm
            close bm
            renderedOK += 1
        ) catch ( logln ("render warn for " + bn + ": " + getCurrentException()) logf )
    )
    logln ("rendered thumbnails: " + (renderedOK as string) + " of " + (typeNames.count as string)) logf

    logln "=== done ===" logf
    flush logf
    close logf
    messageBox "Done -- check D:\\Utilities\\Place_Dummy\\_work\\block_info.csv and \\block_thumbs\\"
)
