-- probe_dwg.ms : import the landscape DWG and dump structure to a log.
(
    logPath = @"D:\Utilities\Place_Dummy\_work\probe_dwg.log"
    dwgPath = @"D:\Utilities\Place_Dummy\LandscapeArea.dwg"

    logFile = createFile logPath
    fn logln s f = ( format "%\n" s to:f )

    logln "=== probe_dwg.ms start ===" logFile
    logln ("3ds Max version: " + (maxVersion() as string)) logFile
    logln ("System units: " + (units.SystemType as string) + " scale=" + (units.SystemScale as string)) logFile
    logln ("Display units: " + (units.DisplayType as string)) logFile

    resetMaxFile #noprompt

    logln ("DWG file exists: " + (doesFileExist dwgPath as string)) logFile

    okImport = false
    try (
        okImport = importFile dwgPath #noPrompt
    ) catch (
        logln ("IMPORT EXCEPTION: " + (getCurrentException())) logFile
    )
    logln ("importFile returned: " + (okImport as string)) logFile

    total = objects.count
    logln ("Total objects after import: " + (total as string)) logFile

    logln "" logFile
    logln ("=== Layers (count=" + (LayerManager.count as string) + ") ===") logFile
    for i = 0 to (LayerManager.count - 1) do (
        lyr = LayerManager.getLayer i
        logln ("  layer[" + (i as string) + "]: " + lyr.name) logFile
    )

    layerKeys = #()
    layerVals = #()
    for obj in objects do (
        k = obj.layer.name
        idx = findItem layerKeys k
        if idx == 0 then ( append layerKeys k; append layerVals 1 )
        else layerVals[idx] += 1
    )
    logln "" logFile
    logln "=== Per-layer object counts ===" logFile
    for i = 1 to layerKeys.count do (
        logln ((layerVals[i] as string) + "  " + layerKeys[i]) logFile
    )

    classKeys = #()
    classVals = #()
    for obj in objects do (
        k = (classOf obj) as string
        idx = findItem classKeys k
        if idx == 0 then ( append classKeys k; append classVals 1 )
        else classVals[idx] += 1
    )
    logln "" logFile
    logln "=== Per-class object counts ===" logFile
    for i = 1 to classKeys.count do (
        logln ((classVals[i] as string) + "  " + classKeys[i]) logFile
    )

    nameKeys = #()
    nameVals = #()
    for obj in objects do (
        k = obj.name
        idx = findItem nameKeys k
        if idx == 0 then ( append nameKeys k; append nameVals 1 )
        else nameVals[idx] += 1
    )
    logln "" logFile
    logln ("=== Distinct object names (" + (nameKeys.count as string) + " total) ===") logFile
    nMax = nameKeys.count
    if nMax > 500 do nMax = 500
    for i = 1 to nMax do (
        logln ((nameVals[i] as string) + "  " + nameKeys[i]) logFile
    )

    logln "" logFile
    logln "=== First 80 objects: name | class | layer | pos ===" logFile
    c = 0
    for obj in objects do (
        if c >= 80 do exit
        logln (obj.name + " | " + ((classOf obj) as string) + " | " + obj.layer.name + " | " + (obj.pos as string)) logFile
        c += 1
    )

    close logFile
    quitMax #noprompt
)
