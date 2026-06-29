--==============================================================
-- PlaceDummyTool.ms  (minimal version: Place + Select Group)
--
-- Buttons:
--   [1] Pick CAD File (.dwg)
--   [2] Pick PDF File (.pdf)  -- optional, opens in default viewer
--   [3] Place Dummies          -- imports DWG, creates a dummy at every
--                                 plant block insertion, names them
--                                 U1_001 / U2_001 / ... so each block
--                                 type is one group, builds a legend
--                                 column with each block's symbol +
--                                 a "U1", "U2", ... text label, adds a
--                                 frozen CAD_Reference layer, and
--                                 saves placedummy.max next to the DWG.
--
-- Helper:
--   [Select Group]  type a label (U1, U2, ...) and click to select
--                   every dummy of that group in the viewport.
--
-- Launch: Scripting > Run Script... > this file.
--==============================================================

(
    try ( destroyDialog ::PlaceDummyTool ) catch ()
    global PlaceDummyTool

    rollout PlaceDummyTool "Place Dummy Toolkit" width:380 height:440
    (
        local cadPath = undefined
        local pdfPath = undefined
        local surfaceNode = undefined
        local lgBaseY = undefined
        local lgX = undefined
        local lgRowSpacing = undefined
        local lgLabelOffsetX = undefined
        local lgTextSize = undefined

        button btnCad   "1. Pick CAD File (.dwg)"  width:370 height:28 align:#center
        label  lblCad   "(none)"                   width:370 align:#center
        button btnPdf   "2. Pick PDF File (.pdf)"  width:370 height:28 align:#center
        label  lblPdf   "(none, optional)"         width:370 align:#center
        button btnPlace "3. Place Dummies"         width:370 height:40 align:#center
        label  lblPlaceHint "Builds legend column with symbol + U1, U2, ..." width:370 align:#center

        ----- Project to surface -----
        groupBox gbSurface "4. (optional) Project dummies onto a surface" pos:[5,235] width:370 height:90
        label lblSurfaceInfo "Surface: (none)" pos:[20,255] width:340 align:#left
        button btnPickSurface "Pick Surface in viewport" pos:[20,275] width:170 height:25
        button btnProject "Project Dummies"              pos:[200,275] width:170 height:25
        label lblProjHint "Casts a ray down from each dummy's XY onto the surface." pos:[20,303] width:340 align:#left

        label hintSel "Select dummies of a group:" pos:[20,340] width:340
        edittext edtLetter "Label (U1, U2, ...):"  pos:[20,360] fieldWidth:150 labelOnTop:false
        button   btnSelect "Select Group"          pos:[240,358] width:130 height:25

        label lblStatus "Ready."  pos:[15,400] width:370 align:#center

        ----- helpers -----
        fn extractBlockName n = (
            local s = n
            if (substring s 1 6) == "Block:" do s = substring s 7 -1
            local i = findString s "$0$"
            while i != undefined do ( s = substring s (i + 3) -1; i = findString s "$0$" )
            s
        )
        fn containsCI big small = ( (findString (toLower big) (toLower small)) != undefined )
        fn isPlantLayer ln = (
            local pos = (containsCI ln "TREE") or (containsCI ln "SHRUB") or \
                        (containsCI ln "SHRB") or (containsCI ln "PALM") or \
                        (containsCI ln "PLNT") or (containsCI ln "PLANT") or \
                        (containsCI ln "GRND") or (containsCI ln "GROUND")
            if not pos do return false
            if (containsCI ln "ANNO") do return false
            if (containsCI ln "SCHD") do return false
            if (containsCI ln "LABEL") do return false
            if (containsCI ln "LEGEND") do return false
            if (containsCI ln "TEXT") do return false
            if (containsCI ln "DIM") do return false
            if (containsCI ln "MATCH") do return false
            true
        )
        fn isPlantBlockName bn = (
            (containsCI bn "TREE") or (containsCI bn "SHRUB") or (containsCI bn "PALM")
        )
        fn isExcluded bn = (
            if (substring bn 1 3) == "A$C" do return true
            if (findString bn "SCHEDULE") != undefined do return true
            if (findString bn "LABEL")    != undefined do return true
            if (findString bn "MLABEL")   != undefined do return true
            if (findString bn "PLANTLIST")!= undefined do return true
            if (findString bn "PLANTSCHEDULE")!= undefined do return true
            false
        )
        fn categoryOf bn ln = (
            if (containsCI bn "PALM")  then "Plants_Palms"
            else if (containsCI bn "SHRUB") then "Plants_Shrubs"
            else if (containsCI bn "TREE")  then "Plants_Trees"
            else if (containsCI ln "PALM")  then "Plants_Palms"
            else if (containsCI ln "SHRUB") or (containsCI ln "SHRB") then "Plants_Shrubs"
            else if (containsCI ln "TREE") then "Plants_Trees"
            else if (containsCI ln "GRND") or (containsCI ln "GROUND") then "Plants_Shrubs"
            else "Plants_Other"
        )
        fn getOrMakeLayer name = (
            local L = LayerManager.getLayerFromName name
            if L == undefined do L = LayerManager.newLayerFromName name
            L
        )
        fn endsWith big small = (
            if small.count > big.count then false
            else ((substring big (big.count - small.count + 1) small.count) == small)
        )
        fn startsWith s prefix = (
            if prefix.count > s.count then false
            else ((substring s 1 prefix.count) == prefix)
        )
        fn projectPaths cp = (
            local dwgDir  = getFilenamePath cp
            local maxOut  = dwgDir + "placedummy.max"
            local workDir = dwgDir + "_work\\"
            makeDir workDir all:true
            #(dwgDir, maxOut, workDir)
        )

        ----- Place Dummies pipeline -----
        fn runPlacement = (
            if cadPath == undefined or (not (doesFileExist cadPath)) do (
                messageBox "Pick a valid CAD (.dwg) file first."
                return undefined
            )
            local pp = projectPaths cadPath
            local dwgDir = pp[1]; local maxOut = pp[2]; local workDir = pp[3]
            local logPath = workDir + "place_dummy_tool.log"
            local keyPath = workDir + "letter_key.csv"
            local skipPath = workDir + "skipped_blocks.csv"

            if doesFileExist logPath do (try (deleteFile logPath) catch ())
            local logf = undefined
            try ( logf = createFile logPath ) catch ()
            fn ll s f = ( if f != undefined do ( format "%\n" s to:f; flush f ) )
            ll "=== Place Dummies start ===" logf

            lblStatus.text = "Importing DWG..."
            windows.processPostedMessages()

            resetMaxFile #noprompt
            local okImp = false
            try ( okImp = importFile cadPath #noPrompt ) catch (
                ll ("IMPORT EXCEPTION: " + (getCurrentException())) logf
            )
            ll ("import returned: " + (okImp as string) + "; objects: " + (objects.count as string)) logf

            local trees  = getOrMakeLayer "Plants_Trees"
            local shrubs = getOrMakeLayer "Plants_Shrubs"
            local palms  = getOrMakeLayer "Plants_Palms"
            local other  = getOrMakeLayer "Plants_Other"

            local typeCounts = #()
            local typeNames  = #()
            local typeCats   = #()
            local typeSample = #()
            local typeLayers = #()
            local typeExemplar = #()
            local dummies    = #()
            local dummyTypeIdx = #()

            if doesFileExist skipPath do (try (deleteFile skipPath) catch ())
            local skipLog = undefined
            try ( skipLog = createFile skipPath ) catch ()
            if skipLog != undefined do format "block_name,layer,reason\n" to:skipLog

            lblStatus.text = "Detecting plant blocks..."
            windows.processPostedMessages()

            for o in objects do (
                if (classOf o) != LinkComposite do continue
                local ln = "(none)"
                try ( ln = (o.layer).name ) catch ()
                local bn = extractBlockName o.name

                local layerOk = isPlantLayer ln
                local nameOk  = isPlantBlockName bn
                if not (layerOk or nameOk) do (
                    if skipLog != undefined do format "%,%,not-a-plant\n" bn ln to:skipLog
                    continue
                )
                if isExcluded bn do (
                    if skipLog != undefined do format "%,%,excluded-pattern\n" bn ln to:skipLog
                    continue
                )

                local idx = findItem typeNames bn
                if idx == 0 then (
                    append typeNames bn
                    append typeCounts 1
                    append typeCats (categoryOf bn ln)
                    append typeSample [o.pos.x, o.pos.y, o.pos.z]
                    append typeLayers ln
                    append typeExemplar o
                    idx = typeNames.count
                ) else (
                    typeCounts[idx] += 1
                )

                local d = Dummy pos:o.pos boxsize:[24,24,24]
                d.name = "_pending_" + (idx as string)

                local L = other
                case typeCats[idx] of (
                    "Plants_Trees":  L = trees
                    "Plants_Shrubs": L = shrubs
                    "Plants_Palms":  L = palms
                )
                L.addNode d
                append dummies d
                append dummyTypeIdx idx
            )
            if skipLog != undefined do close skipLog
            ll ("dummies created: " + (dummies.count as string)) logf
            ll ("distinct block types: " + (typeNames.count as string)) logf

            -- Sort block types by category (Trees -> Palms -> Shrubs -> Other), then by block name.
            if typeNames.count > 0 do (
                local catPriority = #("Plants_Trees", "Plants_Palms", "Plants_Shrubs", "Plants_Other")
                local order = #()
                for i = 1 to typeNames.count do append order i
                fn priorityFor c lst = (
                    local p = findItem lst c
                    if p == 0 then 99 else p
                )
                for i = 1 to order.count do (
                    for j = i + 1 to order.count do (
                        local pa = priorityFor typeCats[order[i]] catPriority
                        local pb = priorityFor typeCats[order[j]] catPriority
                        local needSwap = false
                        if pb < pa then needSwap = true
                        else if pb == pa do (
                            if typeNames[order[j]] < typeNames[order[i]] do needSwap = true
                        )
                        if needSwap do (
                            local tmp = order[i]; order[i] = order[j]; order[j] = tmp
                        )
                    )
                )
                local nT = #(); local nC = #(); local nA = #(); local nS = #(); local nL = #(); local nE = #()
                for k = 1 to order.count do (
                    append nT typeNames[order[k]]
                    append nC typeCounts[order[k]]
                    append nA typeCats[order[k]]
                    append nS typeSample[order[k]]
                    append nL typeLayers[order[k]]
                    append nE typeExemplar[order[k]]
                )
                typeNames = nT; typeCounts = nC; typeCats = nA
                typeSample = nS; typeLayers = nL; typeExemplar = nE

                local newIdxByOld = #()
                for k = 1 to order.count do newIdxByOld[order[k]] = k

                -- Rename dummies with U-prefix in sorted order
                local serials = #()
                for k = 1 to typeNames.count do append serials 0
                for di = 1 to dummies.count do (
                    local newIdx = newIdxByOld[dummyTypeIdx[di]]
                    serials[newIdx] += 1
                    dummies[di].name = "U" + (newIdx as string) + "_" + (formattedPrint serials[newIdx] format:"03d")
                )
            )

            if dummies.count == 0 do (
                ll "ERROR no plant blocks detected" logf
                if logf != undefined do close logf
                lblStatus.text = "ERROR: no plant blocks found in DWG."
                messageBox ("No plant blocks detected.\nCheck _work\\skipped_blocks.csv to see what was rejected.")
                return undefined
            )

            -- Build keep set: exemplars + descendants (used by the legend)
            local keepSet = #()
            for ex in typeExemplar do (
                append keepSet ex
                local stack = #(ex)
                while stack.count > 0 do (
                    local n = stack[stack.count]
                    deleteItem stack stack.count
                    for c in n.children do (
                        append keepSet c
                        append stack c
                    )
                )
            )

            -- Delete source geometry except dummies and exemplar keep set
            local delList = #()
            for o in objects do (
                if (findItem dummies o) != 0 do continue
                if (findItem keepSet o) != 0 do continue
                append delList o
            )
            if delList.count > 0 do delete delList

            -- Translate to origin; capture offset for re-import alignment
            local offset = [0,0,0]
            if dummies.count > 0 do (
                local xs=#(); local ys=#(); local zs=#()
                for d in dummies do ( append xs d.pos.x; append ys d.pos.y; append zs d.pos.z )
                local cx = (amin xs + amax xs) * 0.5
                local cy = (amin ys + amax ys) * 0.5
                local cz = amin zs
                offset = [cx, cy, cz]
                for d in dummies do d.pos = d.pos - offset
                for ex in typeExemplar do ( try ( ex.pos = ex.pos - offset ) catch () )
            )
            ll ("offset: " + (offset as string)) logf

            ----- Build the legend column to the right of the scene -----
            local legendLayer = getOrMakeLayer "Plants_Legend"
            try ( legendLayer.wirecolor = (color 240 200 50) ) catch ()

            if dummies.count > 0 and typeExemplar.count > 0 do (
                local dxs=#(); local dys=#()
                for d in dummies do ( append dxs d.pos.x; append dys d.pos.y )
                local sceneMaxX = amax dxs
                local sceneMaxY = amax dys
                local sceneMinY = amin dys
                local sceneSpanY = sceneMaxY - sceneMinY
                if sceneSpanY < 1 do sceneSpanY = 1000
                local rowSpacing = sceneSpanY / (amax #(typeExemplar.count, 1) + 1)
                if rowSpacing < 200 do rowSpacing = 200
                local legendX = sceneMaxX + rowSpacing * 1.5
                local labelOffsetX = -(rowSpacing * 0.7)
                local textSize = rowSpacing * 0.6

                lgBaseY = sceneMaxY
                lgX = legendX
                lgRowSpacing = rowSpacing
                lgLabelOffsetX = labelOffsetX
                lgTextSize = textSize

                for i = 1 to typeExemplar.count do (
                    local ex = typeExemplar[i]
                    if ex == undefined or (isDeleted ex) do continue
                    local label = "U" + (i as string)
                    local rowY = sceneMaxY - (i - 1) * rowSpacing

                    try ( ex.pos = [legendX, rowY, 0] ) catch ()
                    try ( ex.name = "LegendExemplar_" + label ) catch ()

                    local txt = text text:label size:textSize pos:[legendX + labelOffsetX, rowY, 0]
                    txt.name = "LegendLabel_" + label
                    try ( txt.wirecolor = (color 255 220 60) ) catch ()

                    -- Move exemplar + descendants + label onto Plants_Legend
                    local stack = #(ex)
                    while stack.count > 0 do (
                        local n = stack[stack.count]
                        deleteItem stack stack.count
                        try ( legendLayer.addNode n ) catch ()
                        for c in n.children do append stack c
                    )
                    try ( legendLayer.addNode txt ) catch ()
                )
            )

            saveMaxFile maxOut quiet:true
            ll ("saved placedummy: " + maxOut) logf

            -- letter_key CSV
            if doesFileExist keyPath do (try (deleteFile keyPath) catch ())
            local kf = undefined
            try ( kf = createFile keyPath ) catch ()
            if kf != undefined do (
                format "temp_label,block_type,count,layer_in_dwg,category_guess,sample_x,sample_y\n" to:kf
                for i = 1 to typeNames.count do (
                    local sp = typeSample[i]
                    format "U%,%,%,%,%,%,%\n" \
                        i typeNames[i] typeCounts[i] typeLayers[i] typeCats[i] \
                        (sp[1] - offset.x) (sp[2] - offset.y) to:kf
                )
                close kf
            )

            ----- Re-import DWG as a frozen CAD_Reference layer -----
            lblStatus.text = "Adding CAD_Reference layer..."
            windows.processPostedMessages()
            local preExisting = #()
            for o in objects do append preExisting o
            try ( importFile cadPath #noPrompt ) catch ()
            local imported = #()
            for o in objects do (
                if (findItem preExisting o) == 0 do append imported o
            )
            for o in imported do ( try ( o.pos = o.pos - offset ) catch () )

            local refLayer = getOrMakeLayer "CAD_Reference"
            try ( refLayer.wirecolor = (color 110 110 110) ) catch ()
            try ( refLayer.isFrozen = false ) catch ()
            for o in imported do (
                try ( refLayer.addNode o ) catch ()
                try ( o.wirecolor = (color 110 110 110) ) catch ()
            )

            fn isKeepLayer n = (
                if n == "0" or n == "Default" do return true
                if n == "CAD_Reference" do return true
                if startsWith n "Plants_" do return true
                false
            )

            local layerNames = #()
            for i = 0 to (LayerManager.count - 1) do (
                local L = LayerManager.getLayer i
                if L != undefined do append layerNames L.name
            )
            for n in layerNames do (
                if isKeepLayer n do continue
                local L = LayerManager.getLayerFromName n
                if L == undefined do continue
                local arr = #()
                try ( L.nodes &arr ) catch ()
                for o in arr do (
                    if o != undefined and (isDeleted o) == false do (
                        try ( refLayer.addNode o ) catch ()
                        try ( o.wirecolor = (color 110 110 110) ) catch ()
                    )
                )
            )
            local toDelete = #()
            for n in layerNames do ( if not (isKeepLayer n) do append toDelete n )
            fn lenCmp a b = (b.count - a.count)
            qsort toDelete lenCmp
            for n in toDelete do ( try ( LayerManager.deleteLayerByName n ) catch () )

            -- Mop-up layer 0 (any straggler CAD nodes go to CAD_Reference)
            for o in objects do (
                if (classOf o) == Dummy do continue
                local ln = "(none)"
                try ( ln = (o.layer).name ) catch ()
                if ln == "0" or ln == "Default" do (
                    try ( refLayer.addNode o; o.wirecolor = (color 110 110 110) ) catch ()
                )
            )

            try ( refLayer.isFrozen = true ) catch ()
            saveMaxFile maxOut quiet:true
            if logf != undefined do close logf

            lblStatus.text = "Placed " + (dummies.count as string) + " dummies (" +
                              (typeNames.count as string) + " groups). See _work\\letter_key.csv."
            messageBox ("Placement complete.\n\n" +
                        (dummies.count as string) + " dummies placed across " +
                        (typeNames.count as string) + " block types.\n\n" +
                        "Legend column on the right shows each block's symbol with a U1, U2, ... label.\n" +
                        "Use 'Select Group' (type a label like U1) to grab all dummies of a group.")
        )

        ----- handlers -----
        on btnCad pressed do (
            local p = getOpenFileName caption:"Pick CAD file" \
                          types:"AutoCAD Drawing (*.dwg)|*.dwg|All Files|*.*"
            if p != undefined do (
                cadPath = p
                lblCad.text = filenameFromPath cadPath
                lblStatus.text = "CAD picked."
            )
        )
        on btnPdf pressed do (
            local p = getOpenFileName caption:"Pick PDF file" \
                          types:"PDF (*.pdf)|*.pdf|All Files|*.*"
            if p != undefined do (
                pdfPath = p
                lblPdf.text = filenameFromPath pdfPath
                lblStatus.text = "PDF picked (opens in default viewer)."
                try ( shellLaunch pdfPath "" ) catch ()
            )
        )
        on btnPlace pressed do ( runPlacement() )

        on btnPickSurface pressed do (
            local s = pickObject prompt:"Click the surface (terrain/plane) you want to project dummies onto..."
            if s == undefined or not (isValidNode s) then (
                lblStatus.text = "No surface picked."
            ) else (
                surfaceNode = s
                lblSurfaceInfo.text = "Surface: " + s.name
                lblStatus.text = "Surface picked: " + s.name
            )
        )

        on btnProject pressed do (
            if surfaceNode == undefined or not (isValidNode surfaceNode) do (
                messageBox "Click 'Pick Surface' first and pick the terrain/plane in the viewport."
                return undefined
            )

            local dummies = #()
            for o in objects do (
                if (classOf o) == Dummy do append dummies o
            )
            if dummies.count == 0 do (
                messageBox "No dummies found. Run 'Place Dummies' first."
                return undefined
            )

            -- Cast from well above the surface bbox; fall back to scene bbox if surface.max fails
            local castFromZ = 100000.0
            try (
                castFromZ = surfaceNode.max.z + 10000.0
            ) catch ()

            local projected = 0
            local missed = 0
            for d in dummies do (
                local origin = [d.pos.x, d.pos.y, castFromZ]
                local downRay = Ray origin [0, 0, -1]
                local hit = undefined
                try ( hit = intersectRay surfaceNode downRay ) catch ()

                -- Half-height of the dummy box (boxsize is the full extent on each axis)
                local halfH = 12.0
                try ( halfH = (d.boxsize.z) * 0.5 ) catch ()

                if hit != undefined then (
                    -- Position so the BOTTOM of the box sits on the surface (center is half-height above)
                    d.pos = [d.pos.x, d.pos.y, hit.pos.z + halfH]
                    projected += 1
                ) else (
                    missed += 1
                )

                -- Move the pivot to the bottom of the dummy box. node.pivot sets pivot in
                -- world space while leaving the geometry in place, so the box keeps resting
                -- on the surface and only the pivot indicator shifts.
                try ( d.pivot = [d.pos.x, d.pos.y, d.pos.z - halfH] ) catch ()
            )

            if cadPath != undefined do (
                local pp = projectPaths cadPath
                if doesFileExist pp[2] do saveMaxFile pp[2] quiet:true
            )

            lblStatus.text = "Projected " + (projected as string) + " / " + (dummies.count as string) + " dummies onto " + surfaceNode.name
            if missed > 0 then (
                messageBox ("Projected " + (projected as string) + " dummies onto " + surfaceNode.name +
                            ".\n" + (missed as string) + " dummies were outside the surface's XY extent " +
                            "(left at original position).")
            ) else (
                messageBox ("Projected all " + (projected as string) + " dummies onto " + surfaceNode.name + ".")
            )
        )

        on btnSelect pressed do (
            local raw = edtLetter.text
            if raw == "" do (
                messageBox "Type a label (U1, U2, ...) in the Label field first."
                return undefined
            )
            local letter = toUpper raw
            local pattern = letter + "_*"
            local matches = #()
            for o in objects do (
                if (classOf o) == Dummy and (matchPattern o.name pattern:pattern) do
                    append matches o
            )
            if matches.count == 0 then (
                lblStatus.text = "No dummies match pattern " + pattern
                messageBox ("No dummies found with prefix " + letter + "_")
            ) else (
                select matches
                lblStatus.text = "Selected " + (matches.count as string) + " dummies (group " + letter + ")"
            )
        )
    )

    createDialog PlaceDummyTool style:#(#style_titlebar, #style_sysmenu, #style_resizing, #style_minimizebox)
)
