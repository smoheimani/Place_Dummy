--==============================================================
-- 05_probe_areas.ms
-- Imports LandscapeArea.dwg into a fresh scene and catalogs every
-- CLOSED SplineShape (candidate area-boundary). Output:
--   _work/area_probe.csv -- one row per closed spline
--   _work/area_probe.log -- summary
--
-- Columns in CSV:
--   name, layer, wirecolor_r, wirecolor_g, wirecolor_b,
--   num_splines, total_verts, bbox_min_x, bbox_min_y,
--   bbox_max_x, bbox_max_y, width, height, center_x, center_y, area_approx
--
-- The wirecolor + bbox area + position are what we use to figure
-- out whether species can be auto-identified (color-coded by
-- drafter?) or need a manual mapping pass.
--
-- HOW TO RUN: Scripting > Run Script... > this file. Wait for the
-- popup. DO NOT save the resulting scene -- it's just a probe.
--==============================================================

(
    local dwgPath = @"D:\Utilities\Place_Dummy\LandscapeArea.dwg"
    local csvPath = @"D:\Utilities\Place_Dummy\_work\area_probe.csv"
    local logPath = @"D:\Utilities\Place_Dummy\_work\area_probe.log"

    if doesFileExist logPath do ( try (deleteFile logPath) catch () )
    if doesFileExist csvPath do ( try (deleteFile csvPath) catch () )
    local logf = createFile logPath
    if logf == undefined do (
        messageBox "Could not create log file -- close any other Max instances and retry."
        return undefined
    )
    fn logln s f = ( format "%\n" s to:f; flush f )

    logln "=== 05_probe_areas.ms start ===" logf

    -- 1. Fresh scene
    resetMaxFile #noprompt
    logln "reset done" logf

    -- 2. Import the DWG
    local okImp = false
    try ( okImp = importFile dwgPath #noPrompt ) catch (
        logln ("IMPORT EXCEPTION: " + (getCurrentException())) logf
    )
    logln ("import returned: " + (okImp as string) + "; objects=" + (objects.count as string)) logf

    -- 3. Walk every SplineShape, keep closed ones, dump to CSV
    local csv = createFile csvPath
    format "name,layer,wc_r,wc_g,wc_b,num_splines,total_verts,bbmin_x,bbmin_y,bbmax_x,bbmax_y,width,height,center_x,center_y,area_approx\n" to:csv

    local kept = 0
    local skipped_open = 0
    local skipped_other = 0
    local layerCounts = #()
    local layerNames = #()

    for o in objects do (
        if (classOf o) != SplineShape do ( skipped_other += 1; continue )
        local ns = numSplines o
        if ns == 0 do ( skipped_other += 1; continue )
        -- Require at least one closed sub-spline to count as a candidate boundary
        local anyClosed = false
        local totalV = 0
        for s = 1 to ns do (
            if isClosed o s do anyClosed = true
            totalV += numKnots o s
        )
        if not anyClosed do ( skipped_open += 1; continue )

        local bb_min = o.min
        local bb_max = o.max
        local w = bb_max.x - bb_min.x
        local h = bb_max.y - bb_min.y
        local cx = (bb_min.x + bb_max.x) * 0.5
        local cy = (bb_min.y + bb_max.y) * 0.5
        local areaApprox = w * h
        local wc = o.wirecolor

        local layerName = "(unknown)"
        try ( layerName = (o.layer).name ) catch ()

        -- tally layer occurrences
        local li = findItem layerNames layerName
        if li == 0 then ( append layerNames layerName; append layerCounts 1 )
        else layerCounts[li] += 1

        format "%,%,%,%,%,%,%,%,%,%,%,%,%,%,%,%\n" \
            o.name layerName \
            (wc.r as integer) (wc.g as integer) (wc.b as integer) \
            ns totalV \
            bb_min.x bb_min.y bb_max.x bb_max.y \
            w h cx cy areaApprox \
            to:csv
        kept += 1
    )
    close csv
    logln ("closed splines written : " + (kept as string)) logf
    logln ("open splines skipped   : " + (skipped_open as string)) logf
    logln ("non-spline skipped     : " + (skipped_other as string)) logf

    logln "" logf
    logln "=== closed-spline counts by layer (top 30) ===" logf
    -- bubble-sort top 30 to keep things simple
    local idxs = #()
    for i = 1 to layerNames.count do append idxs i
    for i = 1 to idxs.count do (
        for j = i + 1 to idxs.count do (
            if layerCounts[idxs[j]] > layerCounts[idxs[i]] do (
                local tmp = idxs[i]; idxs[i] = idxs[j]; idxs[j] = tmp
            )
        )
    )
    local cap = idxs.count
    if cap > 30 do cap = 30
    for k = 1 to cap do (
        local ii = idxs[k]
        logln ((layerCounts[ii] as string) + "  " + layerNames[ii]) logf
    )

    logln "=== done ===" logf
    flush logf
    close logf

    messageBox ("Probe complete.\n" +
                "Closed splines: " + (kept as string) + "\n" +
                "Open splines  : " + (skipped_open as string) + "\n\n" +
                "See _work\\area_probe.csv and _work\\area_probe.log.\n" +
                "DO NOT SAVE this scene.")
)
