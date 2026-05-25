--==============================================================
-- 07_rename_areas.ms
-- Reads _work/area_to_species_MAPPING.csv and:
--   1. Renames each Area_<CLUSTER>_NNN to <SPECIES>_AREA_NNN
--   2. Moves it onto a per-species layer Plants_Area_<SPECIES>
--   3. Sets the layer's wirecolor distinctly so categories are easy to scan
--   4. Backs up placedummy.max first
--
-- CSV format (header on first line):
--   area_name,species_code,notes
-- Rows with blank species_code are SKIPPED (left as-is on Plant_Areas layer).
--
-- HOW TO RUN: Scripting > Run Script... > this file.
--==============================================================

(
    local maxPath    = @"D:\Utilities\Place_Dummy\placedummy.max"
    local mapPath    = @"D:\Utilities\Place_Dummy\_work\area_to_species_MAPPING.csv"
    local reportPath = @"D:\Utilities\Place_Dummy\_work\area_rename_report.csv"
    local logPath    = @"D:\Utilities\Place_Dummy\_work\area_rename.log"
    local backupPath = @"D:\Utilities\Place_Dummy\_work\placedummy_BACKUP_pre_area_rename.max"

    if doesFileExist logPath do (try (deleteFile logPath) catch ())
    local logf = createFile logPath
    if logf == undefined do (
        messageBox "Could not create log file -- close any other Max instances."
        return undefined
    )
    fn logln s f = ( format "%\n" s to:f; flush f )

    logln "=== 07_rename_areas.ms start ===" logf

    if doesFileExist maxPath do (
        copyFile maxPath backupPath
        logln ("backup -> " + backupPath) logf
    )

    if not (loadMaxFile maxPath useFileUnits:true quiet:true) do (
        logln "ERROR loading scene" logf; close logf
        messageBox "Couldn't load placedummy.max"
        return undefined
    )
    logln ("loaded; objects=" + (objects.count as string)) logf

    -- Parse CSV (first two columns)
    if not doesFileExist mapPath do (
        logln "ERROR mapping CSV missing" logf; close logf
        messageBox "area_to_species_MAPPING.csv not found"
        return undefined
    )
    local fIn = openFile mapPath mode:"r"
    local areaKeys = #()
    local speciesVals = #()
    local firstLine = true
    while not eof fIn do (
        local line = readLine fIn
        if line == undefined do exit
        if firstLine then ( firstLine = false; continue )
        local c1 = findString line ","
        if c1 == undefined do continue
        local f1 = trimRight (substring line 1 (c1 - 1)) " \t"
        local rest = substring line (c1 + 1) -1
        local c2 = findString rest ","
        local f2 = if c2 != undefined then (substring rest 1 (c2 - 1)) else rest
        f2 = trimLeft (trimRight f2 " \t") " \t"
        if f1 == "" do continue
        append areaKeys f1
        append speciesVals f2
    )
    close fIn
    logln ("csv rows: " + (areaKeys.count as string)) logf

    -- Distinct wirecolors per species so categories are visually obvious
    fn colorForSpecies sp = (
        case sp of (
            "POM": (color 0 200 0)
            "PSY": (color 150 200 0)
            "HAM": (color 200 80 0)
            "CHR": (color 200 0 100)
            "CES": (color 120 120 200)
            "CAA": (color 0 180 180)
            "PHI": (color 100 220 180)
            "ZAM": (color 80 60 180)
            "FIC": (color 220 180 0)
            "GLA": (color 220 120 0)
            "HEL": (color 200 60 200)
            "ILV": (color 60 160 60)
            "JUP": (color 0 200 200)
            "SAL": (color 200 200 60)
            "TRA": (color 0 130 130)
            "MUH": (color 180 200 0)
            "FAK": (color 180 180 0)
            "TRF": (color 100 200 60)
            "HYM": (color 60 180 200)
            "MULCH": (color 120 90 60)
            "SOD": (color 80 200 80)
            "POD": (color 180 0 180)
            "SER": (color 60 60 200)
            default: (color 180 180 180)
        )
    )

    local renamed = 0
    local skipped_blank = 0
    local skipped_missing = 0
    local report = #()
    local perSpeciesCount = #()
    local perSpeciesKey = #()

    for i = 1 to areaKeys.count do (
        local aname = areaKeys[i]
        local sp = speciesVals[i]
        if sp == "" do ( skipped_blank += 1; append report #(aname, "", "(blank)") ; continue )
        local node = getNodeByName aname exact:true
        if node == undefined do ( skipped_missing += 1; append report #(aname, sp, "(node not found)"); continue )

        local idx = findItem perSpeciesKey sp
        if idx == 0 then ( append perSpeciesKey sp; append perSpeciesCount 1 )
        else perSpeciesCount[idx] += 1
        local serial = (if idx == 0 then perSpeciesCount[perSpeciesKey.count] else perSpeciesCount[idx])

        local layerName = "Plants_Area_" + sp
        local L = LayerManager.getLayerFromName layerName
        if L == undefined do L = LayerManager.newLayerFromName layerName
        try ( L.wirecolor = colorForSpecies sp ) catch ()

        local newName = sp + "_AREA_" + (formattedPrint serial format:"03d")
        node.name = newName
        L.addNode node
        node.wirecolor = colorForSpecies sp
        renamed += 1
        append report #(aname, newName, layerName)
    )
    logln ("renamed: " + (renamed as string)) logf
    logln ("blank rows skipped: " + (skipped_blank as string)) logf
    logln ("missing nodes: " + (skipped_missing as string)) logf

    -- Save
    saveMaxFile maxPath quiet:true
    logln ("saved: " + maxPath) logf

    -- Report
    if doesFileExist reportPath do (try (deleteFile reportPath) catch ())
    local rf = createFile reportPath
    format "old_name,new_name,layer_or_note\n" to:rf
    for e in report do format "%,%,%\n" e[1] e[2] e[3] to:rf
    close rf
    logln ("report -> " + reportPath) logf

    logln "" logf
    logln "=== per-species ===" logf
    for i = 1 to perSpeciesKey.count do (
        logln (perSpeciesKey[i] + "  " + (perSpeciesCount[i] as string)) logf
    )

    flush logf; close logf

    local summary = ""
    for i = 1 to perSpeciesKey.count do (
        summary += "  " + perSpeciesKey[i] + ": " + (perSpeciesCount[i] as string) + "\n"
    )
    messageBox ("Renamed " + (renamed as string) + " areas across " + (perSpeciesKey.count as string) +
                " species.\n\n" + summary +
                (if skipped_blank > 0 then "\n" + (skipped_blank as string) + " rows blank (left as-is).\n" else "") +
                (if skipped_missing > 0 then (skipped_missing as string) + " names not found in scene.\n" else ""))
)
