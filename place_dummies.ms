-- place_dummies.ms
-- 1. Opens placedummy.max
-- 2. Imports LandscapeArea.dwg
-- 3. For every plant-block insertion (TREE-*, SHRUB-*, PALM-*) creates a Dummy at the insertion point
-- 4. Names the dummy "<BLOCKTYPE>_NNN" and stores it on a "Plants" layer
-- 5. Deletes all imported source geometry (keeps only the dummies)
-- 6. Translates the whole set so the bounding box centre sits near the origin
-- 7. Saves the .max file back to disk
-- 8. Writes a CSV report listing block-type, count, and sample position
--
-- Run from a shell:
--    "C:\Program Files\Autodesk\3ds Max 2023\3dsmaxbatch.exe" "D:\Utilities\Place_Dummy\place_dummies.ms"

(
    maxPath  = @"D:\Utilities\Place_Dummy\placedummy.max"
    dwgPath  = @"D:\Utilities\Place_Dummy\LandscapeArea.dwg"
    csvPath  = @"D:\Utilities\Place_Dummy\_work\dummy_report.csv"
    logPath  = @"D:\Utilities\Place_Dummy\_work\place_dummies.log"

    logFile = createFile logPath
    fn logln s f = ( format "%\n" s to:f )

    logln "=== place_dummies.ms start ===" logFile
    logln ("scene file: " + maxPath) logFile
    logln ("dwg file  : " + dwgPath) logFile

    -- 1) Load the scene
    if not (doesFileExist maxPath) then (
        logln "ERROR: placedummy.max not found - aborting" logFile
        close logFile
        quitMax #noprompt
    )
    loadMaxFile maxPath useFileUnits:true quiet:true
    logln ("scene loaded; existing objects: " + (objects.count as string)) logFile

    preCount = objects.count
    preSet = #()
    for o in objects do append preSet o

    -- 2) Import the DWG
    okImp = false
    try (
        okImp = importFile dwgPath #noPrompt
    ) catch (
        logln ("IMPORT EXCEPTION: " + (getCurrentException())) logFile
    )
    logln ("import returned: " + (okImp as string) + "; total objects now: " + (objects.count as string)) logFile

    -- 3) Identify imported objects (not in preSet)
    imported = #()
    for o in objects do (
        if findItem preSet o == 0 do append imported o
    )
    logln ("imported objects: " + (imported.count as string)) logFile

    -- Helper: strip "Block:" prefix and any XREF "...$0$" nesting; return only the innermost block name
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

    -- Helper: is this string one of the plant-block prefixes?
    plantPrefixes = #("TREE-PALM", "TREE-DCID", "TREE-EVGR", "TREE-SIMP", "SHRUB-LRG", "SHRUB-TROP", "SHRUB-")
    fn isPlantBlock bname = (
        local hit = false
        for p in plantPrefixes while (not hit) do (
            if matchPattern bname pattern:(p + "*") do hit = true
        )
        hit
    )

    -- 4) Ensure a "Plants" layer
    plantsLayer = LayerManager.getLayerFromName "Plants"
    if plantsLayer == undefined do plantsLayer = LayerManager.newLayerFromName "Plants"

    -- 5) Walk every imported LinkComposite, create dummy if its block name is a plant
    typeCounts = #()
    typeNames  = #()
    dummies    = #()

    for o in imported do (
        if classOf o == LinkComposite do (
            local bn = extractBlockName o.name
            if isPlantBlock bn do (
                local idx = findItem typeNames bn
                if idx == 0 then ( append typeNames bn; append typeCounts 1 )
                else typeCounts[idx] += 1
                local serial = typeCounts[if idx == 0 then typeNames.count else idx]
                local safeBn = substituteString bn "-" "_"
                local d = Dummy pos:o.pos boxsize:[24,24,24]
                d.name = safeBn + "_" + (formattedPrint serial format:"03d")
                plantsLayer.addNode d
                append dummies d
            )
        )
    )
    logln ("dummies created: " + (dummies.count as string)) logFile
    logln ("distinct block types: " + (typeNames.count as string)) logFile

    -- 6) Delete the imported source geometry (keep only the dummies)
    -- Build a delete list = imported - dummies
    delList = #()
    for o in imported do (
        if findItem dummies o == 0 do append delList o
    )
    -- Also delete any of the empty layers/groups that survive
    if delList.count > 0 do (
        delete delList
        logln ("deleted imported source nodes: " + (delList.count as string)) logFile
    )

    -- 7) Translate so the dummy bounding-box centre is at origin
    if dummies.count > 0 do (
        local xs = #(); local ys = #(); local zs = #()
        for d in dummies do (
            append xs d.pos.x; append ys d.pos.y; append zs d.pos.z
        )
        local cx = (amin xs + amax xs) * 0.5
        local cy = (amin ys + amax ys) * 0.5
        local cz = amin zs    -- keep the ground plane at 0
        local offset = [cx, cy, cz]
        logln ("translating by -" + (offset as string)) logFile
        for d in dummies do d.pos = d.pos - offset
    )

    -- 8) Save the .max file
    saveMaxFile maxPath quiet:true
    logln ("saved: " + maxPath) logFile

    -- 9) CSV report
    csv = createFile csvPath
    format "block_type,count,sample_x,sample_y,sample_z\n" to:csv
    for i = 1 to typeNames.count do (
        -- find first dummy whose name starts with this type
        local sample = undefined
        for d in dummies while (sample == undefined) do (
            if matchPattern d.name pattern:(((substituteString typeNames[i] "-" "_")) + "_*") do sample = d
        )
        if sample != undefined then
            format "%,%,%,%,%\n" typeNames[i] typeCounts[i] sample.pos.x sample.pos.y sample.pos.z to:csv
        else
            format "%,%,,,\n" typeNames[i] typeCounts[i] to:csv
    )
    close csv
    logln ("csv report: " + csvPath) logFile

    logln "=== done ===" logFile
    close logFile
    quitMax #noprompt
)

