--==============================================================
-- 03_rename_dummies.ms
-- Reads block_to_species_MAPPING.csv and renames every dummy in
-- placedummy.max from its block-type name to the mapped species
-- code (e.g. SHRUB_LRG_020_001 -> POM_001).
--
-- BEFORE RUNNING:
--   - Inspect/edit  D:\Utilities\Place_Dummy\_work\block_to_species_MAPPING.csv
--     if you disagree with any block_type -> species_code mapping.
--     The columns are CSV: block_type, species_code, confidence, reason, ...
--     Only the first two columns are used here -- the others are notes.
--
-- HOW TO RUN:
--   1. In 3ds Max: Scripting > Run Script... > this file.
--   2. The script opens placedummy.max, renames, saves, prints a summary.
--   3. A timestamped backup of the previous .max is saved to _work\.
--==============================================================

(
    local logPath = @"D:\Utilities\Place_Dummy\_work\rename_dummies.log"
    local maxPath = @"D:\Utilities\Place_Dummy\placedummy.max"
    local mapPath = @"D:\Utilities\Place_Dummy\_work\block_to_species_MAPPING.csv"
    local reportPath = @"D:\Utilities\Place_Dummy\_work\rename_report.csv"

    if doesFileExist logPath do ( try (deleteFile logPath) catch () )
    local logf = createFile logPath
    if logf == undefined do (
        messageBox "Could not create log file -- close any 3ds Max instances and retry."
        return undefined
    )
    fn logln s f = ( format "%\n" s to:f; flush f )

    logln "=== rename_dummies.ms start ===" logf
    logln ("scene : " + maxPath) logf
    logln ("csv   : " + mapPath) logf

    -- backup the .max
    if doesFileExist maxPath do (
        local stamp = (((localTime as string) as string))   -- non-essential timestamp text
        local bk = (getFilenamePath maxPath) + "placedummy_BACKUP_pre_rename.max"
        copyFile maxPath bk
        logln ("backup -> " + bk) logf
    )

    -- 1. Load the .max
    if not (loadMaxFile maxPath useFileUnits:true quiet:true) do (
        logln "ERROR loading scene" logf
        close logf
        messageBox "Couldn't load placedummy.max"
        return undefined
    )
    logln ("loaded; objects=" + (objects.count as string)) logf

    -- 2. Parse the CSV (first two columns only)
    local rawCsv = ""
    if not doesFileExist mapPath do (
        logln "ERROR mapping CSV missing" logf
        close logf
        messageBox "block_to_species_MAPPING.csv not found in _work\\"
        return undefined
    )
    local fIn = openFile mapPath mode:"r"
    local mapping = #()   -- array of #(blockTypeUnderscored, speciesCode)
    local firstLine = true
    while not eof fIn do (
        local line = readLine fIn
        if line == undefined do exit
        if firstLine then ( firstLine = false; continue )
        -- naive csv: split by comma, take first two fields
        local commaIdx = findString line ","
        if commaIdx == undefined do continue
        local f1 = trimRight (substring line 1 (commaIdx - 1)) " \t"
        local rest = substring line (commaIdx + 1) -1
        local commaIdx2 = findString rest ","
        local f2 = if commaIdx2 != undefined then (substring rest 1 (commaIdx2 - 1)) else rest
        f2 = trimRight f2 " \t"
        if f1 == "" or f2 == "" do continue
        -- replace - with _ to match dummy names
        local blockKey = (substituteString f1 "-" "_")
        append mapping #(blockKey, f2)
    )
    close fIn
    logln ("mapping entries: " + (mapping.count as string)) logf

    -- 3. Walk every dummy, look up its block prefix in mapping, rename
    local perSpeciesCount = #()
    local perSpeciesKeys  = #()
    local renamed = 0
    local skipped = 0
    local report = #()      -- array of #(oldName, newName, mappedBlock)

    -- Get only dummies (skip whatever else exists)
    local dummyObjs = #()
    for o in objects do (
        if (classOf o) == Dummy do append dummyObjs o
    )
    logln ("dummies found: " + (dummyObjs.count as string)) logf

    for d in dummyObjs do (
        local nm = d.name
        -- nm looks like  "TREE_SIMP_050_007"  -- last "_NNN" is the per-block serial
        local lastU = -1
        for i = nm.count to 1 by -1 do (
            if (nm[i]) == "_" do ( lastU = i; exit )
        )
        if lastU == -1 do ( skipped += 1; continue )
        local prefix = substring nm 1 (lastU - 1)
        -- find prefix in mapping
        local foundSpecies = undefined
        for m in mapping while (foundSpecies == undefined) do (
            if m[1] == prefix do foundSpecies = m[2]
        )
        if foundSpecies == undefined then (
            skipped += 1
            append report #(nm, nm, "(no mapping for prefix '" + prefix + "')")
        ) else (
            local idx = findItem perSpeciesKeys foundSpecies
            if idx == 0 then ( append perSpeciesKeys foundSpecies; append perSpeciesCount 1 )
            else perSpeciesCount[idx] += 1
            local serial = (if idx == 0 then perSpeciesCount[perSpeciesKeys.count] else perSpeciesCount[idx])
            local newName = foundSpecies + "_" + (formattedPrint serial format:"03d")
            d.name = newName
            append report #(nm, newName, prefix)
            renamed += 1
        )
    )

    logln ("renamed: " + (renamed as string)) logf
    logln ("skipped: " + (skipped as string)) logf

    -- Sort summary by species code for clean output
    logln "" logf
    logln "=== per-species renamed counts ===" logf
    for i = 1 to perSpeciesKeys.count do (
        logln (perSpeciesKeys[i] + "  " + (perSpeciesCount[i] as string)) logf
    )

    -- Write detailed report CSV
    if doesFileExist reportPath do (try (deleteFile reportPath) catch ())
    local rf = createFile reportPath
    format "old_name,new_name,block_prefix_used\n" to:rf
    for entry in report do (
        format "%,%,%\n" entry[1] entry[2] entry[3] to:rf
    )
    close rf
    logln ("report csv -> " + reportPath) logf

    -- Save the .max
    saveMaxFile maxPath quiet:true
    logln ("saved : " + maxPath) logf

    logln "=== done ===" logf
    flush logf
    close logf
    messageBox ("Renamed " + (renamed as string) + " dummies across " +
                (perSpeciesKeys.count as string) + " species. See _work\\rename_report.csv for details.")
)
