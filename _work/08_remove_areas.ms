--==============================================================
-- 08_remove_areas.ms
-- Removes the 30 plant-area boundary splines and the Plant_Areas
-- layer from placedummy.max, leaving only the dummies.
--
-- Backs up first to _work/placedummy_BACKUP_pre_remove_areas.max.
--
-- HOW TO RUN: Scripting > Run Script... > this file.
--==============================================================

(
    local maxPath    = @"D:\Utilities\Place_Dummy\placedummy.max"
    local backupPath = @"D:\Utilities\Place_Dummy\_work\placedummy_BACKUP_pre_remove_areas.max"
    local logPath    = @"D:\Utilities\Place_Dummy\_work\remove_areas.log"

    if doesFileExist logPath do (try (deleteFile logPath) catch ())
    local logf = createFile logPath
    fn logln s f = ( format "%\n" s to:f; flush f )

    logln "=== 08_remove_areas.ms start ===" logf

    if doesFileExist maxPath do (
        copyFile maxPath backupPath
        logln ("backup -> " + backupPath) logf
    )

    if not (loadMaxFile maxPath useFileUnits:true quiet:true) do (
        logln "ERROR loading scene" logf; close logf
        messageBox "Couldn't load placedummy.max"; return undefined
    )
    logln ("loaded; objects=" + (objects.count as string)) logf

    -- Collect any node whose name starts with "Area_" OR is on a Plant_Areas / Plants_Area_* layer
    local toDelete = #()
    for o in objects do (
        local nm = o.name
        local ln = "(none)"
        try ( ln = (o.layer).name ) catch ()
        local nameHit = (matchPattern nm pattern:"Area_*") or (matchPattern nm pattern:"*_AREA_*")
        local layerHit = (ln == "Plant_Areas") or (matchPattern ln pattern:"Plants_Area_*")
        if nameHit or layerHit do append toDelete o
    )
    logln ("to delete: " + (toDelete.count as string)) logf

    if toDelete.count > 0 do (
        delete toDelete
        logln "deleted." logf
    )

    -- Drop the (now-empty) Plant_Areas + Plants_Area_* layers
    local layerNamesToDrop = #("Plant_Areas")
    for i = 0 to LayerManager.count - 1 do (
        local L = LayerManager.getLayer i
        if L != undefined do (
            local n = L.name
            if (matchPattern n pattern:"Plants_Area_*") do appendIfUnique layerNamesToDrop n
        )
    )
    for n in layerNamesToDrop do (
        try ( LayerManager.deleteLayerByName n ) catch ()
    )
    logln ("dropped layers: " + (layerNamesToDrop.count as string)) logf

    saveMaxFile maxPath quiet:true
    logln ("saved: " + maxPath) logf
    logln "=== done ===" logf
    flush logf; close logf

    messageBox ("Removed " + (toDelete.count as string) + " area objects and " +
                (layerNamesToDrop.count as string) + " layers.\nScene now contains only dummies.")
)
