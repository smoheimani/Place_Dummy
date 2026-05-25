--==============================================================
-- 04_layer_dummies.ms
-- Moves every plant dummy in placedummy.max onto a category-based
-- layer (Plants_Trees, Plants_Palms, Plants_Shrubs).
--
-- Category is derived from each species' source block_type prefix
-- in block_to_species_MAPPING.csv:
--    TREE-PALM-*  -> Plants_Palms
--    TREE-*       -> Plants_Trees   (DCID / EVGR / SIMP)
--    SHRUB-*      -> Plants_Shrubs  (LRG / TROP)
--
-- Idempotent: re-running just re-assigns dummies to the correct
-- layer. A timestamped backup of placedummy.max is saved first.
--
-- HOW TO RUN:
--   In 3ds Max: Scripting > Run Script... > this file.
--==============================================================

(
    local logPath    = @"D:\Utilities\Place_Dummy\_work\layer_dummies.log"
    local maxPath    = @"D:\Utilities\Place_Dummy\placedummy.max"
    local mapPath    = @"D:\Utilities\Place_Dummy\_work\block_to_species_MAPPING.csv"
    local reportPath = @"D:\Utilities\Place_Dummy\_work\layer_report.csv"
    local backupPath = @"D:\Utilities\Place_Dummy\_work\placedummy_BACKUP_pre_layer.max"

    if doesFileExist logPath do ( try (deleteFile logPath) catch () )
    local logf = createFile logPath
    if logf == undefined do (
        messageBox "Could not create log file -- close any 3ds Max instances and retry."
        return undefined
    )
    fn logln s f = ( format "%\n" s to:f; flush f )

    logln "=== 04_layer_dummies.ms start ===" logf
    logln ("scene: " + maxPath) logf
    logln ("map  : " + mapPath) logf

    -- 1. Backup the .max
    if doesFileExist maxPath do (
        copyFile maxPath backupPath
        logln ("backup -> " + backupPath) logf
    )

    -- 2. Load the .max
    if not (loadMaxFile maxPath useFileUnits:true quiet:true) do (
        logln "ERROR loading scene" logf
        close logf
        messageBox "Couldn't load placedummy.max"
        return undefined
    )
    logln ("loaded; objects=" + (objects.count as string)) logf

    -- 3. Helper: block prefix -> category layer name
    fn categoryOf blockType = (
        if (matchPattern blockType pattern:"TREE-PALM-*") then "Plants_Palms"
        else if (matchPattern blockType pattern:"TREE-*")  then "Plants_Trees"
        else if (matchPattern blockType pattern:"SHRUB-*") then "Plants_Shrubs"
        else "Plants_Other"
    )

    -- 4. Parse mapping CSV: build species_code -> category
    local speciesKeys  = #()
    local speciesCats  = #()
    if not doesFileExist mapPath do (
        logln "ERROR mapping CSV missing" logf
        close logf
        messageBox "block_to_species_MAPPING.csv not found in _work\\"
        return undefined
    )
    local fIn = openFile mapPath mode:"r"
    local firstLine = true
    while not eof fIn do (
        local line = readLine fIn
        if line == undefined do exit
        if firstLine then ( firstLine = false; continue )
        local commaIdx = findString line ","
        if commaIdx == undefined do continue
        local f1 = trimRight (substring line 1 (commaIdx - 1)) " \t"
        local rest = substring line (commaIdx + 1) -1
        local commaIdx2 = findString rest ","
        local f2 = if commaIdx2 != undefined then (substring rest 1 (commaIdx2 - 1)) else rest
        f2 = trimRight f2 " \t"
        if f1 == "" or f2 == "" do continue
        local cat = categoryOf f1
        -- if species already mapped, keep the existing (first-wins) — both rows for CR/CG yield same cat anyway
        if (findItem speciesKeys f2) == 0 do (
            append speciesKeys f2
            append speciesCats cat
        )
    )
    close fIn
    logln ("species mapped: " + (speciesKeys.count as string)) logf

    -- 5. Ensure category layers exist
    local catLayerNames = #("Plants_Trees", "Plants_Palms", "Plants_Shrubs", "Plants_Other")
    local catLayers = #()
    for n in catLayerNames do (
        local L = LayerManager.getLayerFromName n
        if L == undefined do L = LayerManager.newLayerFromName n
        append catLayers L
    )
    fn getCatLayer name layerNames layers = (
        local i = findItem layerNames name
        if i == 0 then layers[4] else layers[i]
    )

    -- 6. Walk every dummy, look up species via name prefix, move to layer
    local dummyObjs = #()
    for o in objects do (
        if (classOf o) == Dummy do append dummyObjs o
    )
    logln ("dummies found: " + (dummyObjs.count as string)) logf

    local moved = 0
    local skipped = 0
    local perLayerCounts = #(0, 0, 0, 0)   -- Trees, Palms, Shrubs, Other
    local report = #()

    for d in dummyObjs do (
        local nm = d.name
        local lastU = -1
        for i = nm.count to 1 by -1 do (
            if (nm[i]) == "_" do ( lastU = i; exit )
        )
        if lastU == -1 do ( skipped += 1; continue )
        local sp = substring nm 1 (lastU - 1)
        local idx = findItem speciesKeys sp
        local cat = if idx == 0 then "Plants_Other" else speciesCats[idx]
        local L = getCatLayer cat catLayerNames catLayers
        L.addNode d
        local ci = findItem catLayerNames cat
        if ci != 0 do perLayerCounts[ci] += 1
        moved += 1
        append report #(nm, sp, cat)
    )

    logln ("moved: " + (moved as string)) logf
    logln ("skipped: " + (skipped as string)) logf
    logln "" logf
    logln "=== per-layer counts ===" logf
    for i = 1 to catLayerNames.count do (
        logln (catLayerNames[i] + "  " + (perLayerCounts[i] as string)) logf
    )

    -- 7. Write report CSV
    if doesFileExist reportPath do (try (deleteFile reportPath) catch ())
    local rf = createFile reportPath
    format "dummy_name,species_code,layer\n" to:rf
    for entry in report do (
        format "%,%,%\n" entry[1] entry[2] entry[3] to:rf
    )
    close rf
    logln ("report csv -> " + reportPath) logf

    -- 8. Save the .max
    saveMaxFile maxPath quiet:true
    logln ("saved: " + maxPath) logf

    logln "=== done ===" logf
    flush logf
    close logf

    local summary = ""
    for i = 1 to catLayerNames.count do (
        summary += catLayerNames[i] + ": " + (perLayerCounts[i] as string) + "\n"
    )
    messageBox ("Moved " + (moved as string) + " dummies into category layers.\n\n" + summary +
                "\nSee _work\\layer_report.csv for details.")
)
