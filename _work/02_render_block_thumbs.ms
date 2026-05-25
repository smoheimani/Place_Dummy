--==============================================================
-- 02_render_block_thumbs.ms
-- Purpose:  Open a fresh scene, re-import the landscape DWG,
--           then for every distinct plant-block type (TREE-*, SHRUB-*,
--           PALM-*) save one viewport screenshot showing what that
--           block looks like. Output: ~23 BMPs in _work\block_thumbs\.
--
-- HOW TO RUN (inside 3ds Max 2023):
--   1. Scripting menu > Run Script...
--   2. Pick this file:
--        D:\Utilities\Place_Dummy\_work\02_render_block_thumbs.ms
--   3. When the DWG import dialog appears, set
--        Geometry tab > "Derive AutoCAD Primitives by:" =
--        "Layer, Blocks as Node Hierarchy"
--      and click OK (same setting you used last time).
--   4. The script will reset the scene to do its work --
--      it does NOT touch placedummy.max in any way.
--==============================================================

(
    local logPath = @"D:\Utilities\Place_Dummy\_work\thumb_blocks.log"
    local dwgPath = @"D:\Utilities\Place_Dummy\LandscapeArea.dwg"
    local outDir  = @"D:\Utilities\Place_Dummy\_work\block_thumbs\"

    makeDir outDir all:true
    local f = createFile logPath
    fn logln s logf = ( format "%\n" s to:logf )

    logln "=== render_block_thumbs.ms start ===" f

    resetMaxFile #noprompt

    units.SystemType = #inches
    units.DisplayType = #us

    logln "importing DWG..." f
    importFile dwgPath
    logln ("objects after import: " + (objects.count as string)) f

    -- Helper -- strip "Block:" prefix and nested xref "$0$" parts
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

    plantPrefixes = #("TREE-PALM", "TREE-DCID", "TREE-EVGR", "TREE-SIMP", "SHRUB-LRG", "SHRUB-TROP", "SHRUB-")
    fn isPlantBlock bname = (
        local hit = false
        for p in plantPrefixes while (not hit) do (
            if matchPattern bname pattern:(p + "*") do hit = true
        )
        hit
    )

    -- 1 instance per block type
    samplesByType = #()
    typeNames = #()
    for o in objects do (
        if classOf o == LinkComposite do (
            local bn = extractBlockName o.name
            if (isPlantBlock bn) and (findItem typeNames bn == 0) do (
                append typeNames bn
                append samplesByType o
            )
        )
    )
    logln ("distinct plant block types: " + (typeNames.count as string)) f

    -- Switch to top view, wireframe, hide grid
    actionMan.executeAction 0 "275"      -- Views: Top
    viewport.setLayout #layout_1
    viewport.activeViewport = 1
    viewport.SetShowGrids false
    viewport.SetRenderLevel #wireframe

    -- Loop: select the sample, zoom extents selected, screenshot
    for i = 1 to typeNames.count do (
        local samp = samplesByType[i]
        local bn = typeNames[i]
        try (
            clearSelection()
            select samp
            -- Zoom Extents Selected on active viewport
            max tool zoomextents
            actionMan.executeAction 0 "310"   -- Tools: Zoom Extents Selected (id may vary)
            redrawViews()
            local dib = gw.getViewportDib()
            local safe = (substituteString bn "-" "_")
            local outPath = (outDir + "blk_" + safe + ".bmp")
            dib.filename = outPath
            save dib
            logln ("rendered " + (i as string) + "/" + (typeNames.count as string) + ": " + outPath) f
        ) catch (
            logln ("ERROR rendering " + bn + " : " + (getCurrentException())) f
        )
    )

    -- Also write a list of types in order, so we know the mapping
    local idxFile = createFile (outDir + "_index.txt")
    for i = 1 to typeNames.count do (
        format "% % % %\n" i typeNames[i] samplesByType[i].pos.x samplesByType[i].pos.y to:idxFile
    )
    close idxFile

    logln "=== done ===" f
    close f
    -- do not quit; leave Max so user can inspect if desired
)
