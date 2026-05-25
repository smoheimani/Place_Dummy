--==============================================================
-- 06_extract_areas.ms
-- Adds 30 plant-area boundary splines from LandscapeArea.dwg into
-- placedummy.max on a new "Plant_Areas" layer, with the same
-- translation offset that the dummies received in Phase 1.
--
-- Each boundary is named: Area_<CLUSTER>_<NNN>
--   where CLUSTER is one of Site, TH4..TH8, Villa4..Villa6
--   (derived from the source XREF block name).
--
-- A template mapping CSV is also written for the next step:
--   _work/area_to_species_MAPPING.csv
--     area_name, species_code   (species_code blank -- you fill in)
--
-- The species rename pass will use that CSV (script 07, separate).
--
-- HOW TO RUN:
--   In 3ds Max: Scripting > Run Script... > this file.
--==============================================================

(
    local maxPath    = @"D:\Utilities\Place_Dummy\placedummy.max"
    local dwgPath    = @"D:\Utilities\Place_Dummy\LandscapeArea.dwg"
    local csvPath    = @"D:\Utilities\Place_Dummy\_work\plant_areas_report.csv"
    local mapPath    = @"D:\Utilities\Place_Dummy\_work\area_to_species_MAPPING.csv"
    local logPath    = @"D:\Utilities\Place_Dummy\_work\plant_areas.log"
    local backupPath = @"D:\Utilities\Place_Dummy\_work\placedummy_BACKUP_pre_areas.max"

    if doesFileExist logPath do (try (deleteFile logPath) catch ())
    local logf = createFile logPath
    if logf == undefined do (
        messageBox "Could not create log file -- close any other Max instances and retry."
        return undefined
    )
    fn logln s f = ( format "%\n" s to:f; flush f )

    logln "=== 06_extract_areas.ms start ===" logf

    -- 1. Backup the .max
    if doesFileExist maxPath do (
        copyFile maxPath backupPath
        logln ("backup -> " + backupPath) logf
    )

    -- 2. Load placedummy.max (already has 2554 renamed/layered dummies)
    if not (loadMaxFile maxPath useFileUnits:true quiet:true) do (
        logln "ERROR loading scene" logf
        close logf
        messageBox "Couldn't load placedummy.max"
        return undefined
    )
    logln ("loaded; objects=" + (objects.count as string)) logf

    -- Snapshot pre-existing scene objects (the dummies)
    local preExisting = #()
    for o in objects do append preExisting o

    -- 3. Import the DWG (adds objects on top of existing scene)
    local okImp = false
    try ( okImp = importFile dwgPath #noPrompt ) catch (
        logln ("IMPORT EXCEPTION: " + (getCurrentException())) logf
    )
    logln ("import returned: " + (okImp as string) + "; objects now: " + (objects.count as string)) logf

    -- 4. Compute the bbox-center offset of imported plant block insertions
    --    (mirrors the translation applied in place_dummies.ms so the new
    --    splines line up with the dummies)
    local plantPrefixes = #("TREE-PALM", "TREE-DCID", "TREE-EVGR", "TREE-SIMP", "SHRUB-LRG", "SHRUB-TROP", "SHRUB-")
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
    fn isPlantBlock bname pfxes = (
        local hit = false
        for p in pfxes while (not hit) do (
            if matchPattern bname pattern:(p + "*") do hit = true
        )
        hit
    )

    local xs = #(); local ys = #(); local zs = #()
    local importedAll = #()
    for o in objects do (
        if (findItem preExisting o) == 0 do append importedAll o
    )
    logln ("imported objects: " + (importedAll.count as string)) logf

    for o in importedAll do (
        if (classOf o) == LinkComposite do (
            local bn = extractBlockName o.name
            if isPlantBlock bn plantPrefixes do (
                append xs o.pos.x; append ys o.pos.y; append zs o.pos.z
            )
        )
    )
    if xs.count == 0 do (
        logln "ERROR no plant blocks found to derive offset" logf
        close logf
        messageBox "No plant blocks found in DWG import -- aborting"
        return undefined
    )
    local offsetX = (amin xs + amax xs) * 0.5
    local offsetY = (amin ys + amax ys) * 0.5
    local offsetZ = amin zs
    local offset = [offsetX, offsetY, offsetZ]
    logln ("computed offset: " + (offset as string)) logf

    -- 5. Find LP-SHAR-BRDR-CONT splines among imported
    local areaSplines = #()
    for o in importedAll do (
        if (classOf o) == SplineShape do (
            local ln = "(none)"
            try ( ln = (o.layer).name ) catch ()
            if (findString ln "LP-SHAR-BRDR-CONT") != undefined do (
                append areaSplines o
            )
        )
    )
    logln ("LP-SHAR-BRDR-CONT splines found: " + (areaSplines.count as string)) logf

    -- 6. Ensure Plant_Areas layer
    local areasLayer = LayerManager.getLayerFromName "Plant_Areas"
    if areasLayer == undefined do areasLayer = LayerManager.newLayerFromName "Plant_Areas"

    fn clusterOf layerName = (
        if (findString layerName "Villa4") != undefined then "Villa4"
        else if (findString layerName "Villa5") != undefined then "Villa5"
        else if (findString layerName "Villa6") != undefined then "Villa6"
        else if (findString layerName "TH4") != undefined then "TH4"
        else if (findString layerName "TH5") != undefined then "TH5"
        else if (findString layerName "TH6") != undefined then "TH6"
        else if (findString layerName "TH7") != undefined then "TH7"
        else if (findString layerName "TH8") != undefined then "TH8"
        else "Site"
    )

    -- 7. Copy each boundary, detach, translate, name, layer
    local clusterKeys = #()
    local clusterCounts = #()
    local createdAreas = #()
    local report = #()

    for o in areaSplines do (
        local ln = "(none)"
        try ( ln = (o.layer).name ) catch ()
        local cl = clusterOf ln
        local idx = findItem clusterKeys cl
        if idx == 0 then ( append clusterKeys cl; append clusterCounts 1; idx = clusterKeys.count )
        else clusterCounts[idx] += 1
        local serial = clusterCounts[idx]
        local newName = "Area_" + cl + "_" + (formattedPrint serial format:"03d")

        -- duplicate, detach from any XREF parent, translate, layer, rename
        local dupes = #()
        maxOps.cloneNodes (#(o)) cloneType:#copy newNodes:&dupes
        if dupes.count == 0 do (
            logln ("ERROR cloning " + o.name) logf
            continue
        )
        local cpy = dupes[1]
        try ( cpy.parent = undefined ) catch ()    -- detach; preserves world xform in modern Max
        cpy.pos = cpy.pos - offset
        cpy.name = newName
        areasLayer.addNode cpy
        cpy.wirecolor = (color 0 255 0)           -- bright green so they're easy to see
        append createdAreas cpy

        local bb_min = cpy.min
        local bb_max = cpy.max
        local w = bb_max.x - bb_min.x
        local h = bb_max.y - bb_min.y
        local ccx = (bb_min.x + bb_max.x) * 0.5
        local ccy = (bb_min.y + bb_max.y) * 0.5
        append report #(newName, cl, ln, w, h, ccx, ccy)
    )
    logln ("areas created: " + (createdAreas.count as string)) logf

    -- 8. Delete all originally-imported objects (keep dummies + our new copies)
    local delList = #()
    for o in importedAll do (
        if (findItem createdAreas o) == 0 do append delList o
    )
    if delList.count > 0 do (
        delete delList
        logln ("deleted imported source nodes: " + (delList.count as string)) logf
    )

    -- 9. Save the .max
    saveMaxFile maxPath quiet:true
    logln ("saved: " + maxPath) logf

    -- 10. Report CSV
    if doesFileExist csvPath do (try (deleteFile csvPath) catch ())
    local rf = createFile csvPath
    format "area_name,cluster,source_layer,width,height,center_x,center_y\n" to:rf
    for entry in report do (
        format "%,%,%,%,%,%,%\n" entry[1] entry[2] entry[3] entry[4] entry[5] entry[6] entry[7] to:rf
    )
    close rf
    logln ("report csv: " + csvPath) logf

    -- 11. Template mapping CSV (only if it doesn't already exist; don't overwrite user edits)
    if not (doesFileExist mapPath) do (
        local mf = createFile mapPath
        format "area_name,species_code,notes\n" to:mf
        for entry in report do (
            format "%,,\n" entry[1] to:mf
        )
        close mf
        logln ("template mapping csv: " + mapPath) logf
    )

    logln "=== done ===" logf
    flush logf
    close logf

    local sumStr = ""
    for i = 1 to clusterKeys.count do (
        sumStr += "  " + clusterKeys[i] + ": " + (clusterCounts[i] as string) + "\n"
    )
    messageBox ("Created " + (createdAreas.count as string) + " plant-area boundaries on layer 'Plant_Areas'.\n\n" +
                "By cluster:\n" + sumStr + "\n" +
                "Fill species codes in:\n  _work\\area_to_species_MAPPING.csv\n" +
                "then run the rename pass.")
)
