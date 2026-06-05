--==============================================================
-- PlaceDummyTool.ms
-- Visual-rename workflow:
--   [1] Pick CAD File (.dwg)
--   [2] Pick PDF File (.pdf)    -- optional, opens for reference
--   [3] Place Dummies            -- imports DWG, creates a dummy at every
--                                  plant block insertion, names them
--                                  A_001 / A_002 / ... B_001 / ... so each
--                                  block type is one letter group, writes a
--                                  letter-key CSV explaining what each
--                                  letter is, adds frozen CAD_Reference.
--   ... in Max viewport, right-click any dummy > Select Similar
--   [4] Type species + category in the fields, click Rename Selected.
--       All selected dummies get renamed <CommonName>_NNN and moved to
--       the legend-section layer.
--
-- Launch: Scripting > Run Script... > this file.
--==============================================================

(
    try ( destroyDialog ::PlaceDummyTool ) catch ()
    global PlaceDummyTool

    rollout PlaceDummyTool "Place Dummy Toolkit" width:400 height:680
    (
        local cadPath = undefined
        local pdfPath = undefined
        -- Legend layout (set by Place Dummies, used by Build Legend)
        local lgBaseY = undefined
        local lgX = undefined
        local lgRowSpacing = undefined
        local lgLabelOffsetX = undefined
        local lgTextSize = undefined

        ----- Top: file pickers + Place button -----
        button btnCad   "1. Pick CAD File (.dwg)"  width:370 height:28 align:#center
        label  lblCad   "(none)"                   width:370 align:#center
        button btnPdf   "2. Pick PDF File (.pdf)"  width:370 height:28 align:#center
        label  lblPdf   "(none, optional)"         width:370 align:#center
        button btnPlace "3. Place Dummies"         width:370 height:40 align:#center
        label  lblPlaceHint "Imports CAD, places dummies, builds initial legend column" width:370 align:#center

        ----- Schedule input + build legend -----
        groupBox gbSched "4. Plant Schedule (OCR from PDF or paste manually):" width:380 height:320 align:#center
        button btnOcr "OCR Schedule from PDF" pos:[20,210] width:360 height:28
        dotNetControl edtSchedule "System.Windows.Forms.TextBox" pos:[20,245] width:360 height:200
        button btnBuildLegend "5. Build Legend from Schedule" pos:[20,455] width:360 height:35

        ----- Optional: select group helper -----
        label hintSel "Select dummies of a group (optional, for manual fixing):" pos:[20,515] width:360
        edittext edtLetter "Label (U1, X1, ...):" pos:[20,535] fieldWidth:140 labelOnTop:false
        button   btnSelect "Select Group" pos:[230,533] width:150 height:25

        label lblStatus "Ready."  pos:[15,580] width:370 align:#center

        ----- helpers (top-level scope inside rollout) -----
        fn extractBlockName n = (
            local s = n
            if (substring s 1 6) == "Block:" do s = substring s 7 -1
            local i = findString s "$0$"
            while i != undefined do ( s = substring s (i + 3) -1; i = findString s "$0$" )
            s
        )
        fn containsCI big small = (
            (findString (toLower big) (toLower small)) != undefined
        )
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
            -- block-name hints take priority (most reliable)
            if (containsCI bn "PALM")  then "Plants_Palms"
            else if (containsCI bn "SHRUB") then "Plants_Shrubs"
            else if (containsCI bn "TREE")  then "Plants_Trees"
            -- fall back to the layer's plant-category keyword
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
        fn idxToLetter idx = (
            local alpha = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
            if idx <= 26 then (
                substring alpha idx 1
            ) else (
                local n = idx - 27
                local first = (n / 26) + 1
                local second = (mod n 26) + 1
                (substring alpha first 1) + (substring alpha second 1)
            )
        )
        fn sanitize s = (
            local out = ""
            for i = 1 to s.count do (
                local ch = s[i]
                local code = bit.charAsInt ch
                if (code >= bit.charAsInt "A" and code <= bit.charAsInt "Z") or \
                   (code >= bit.charAsInt "a" and code <= bit.charAsInt "z") or \
                   (code >= bit.charAsInt "0" and code <= bit.charAsInt "9") do
                    out += ch
            )
            out
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
            fn ll s f = (
                if f != undefined do ( format "%\n" s to:f; flush f )
            )
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
            local typeExemplar = #()  -- one LinkComposite per block type, used as the visual legend symbol
            local dummies    = #()
            local dummyTypeIdx = #()   -- parallel to dummies; original type index (pre-sort) for each dummy

            if doesFileExist skipPath do (try (deleteFile skipPath) catch ())
            local skipLog = undefined
            try ( skipLog = createFile skipPath ) catch ()
            if skipLog == undefined then (
                ll "WARN could not write skipped_blocks.csv (probably open in Excel)" logf
            ) else (
                format "block_name,layer,reason\n" to:skipLog
            )

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
                    append typeExemplar o   -- first instance becomes the legend symbol
                    idx = typeNames.count
                ) else (
                    typeCounts[idx] += 1
                )

                local d = Dummy pos:o.pos boxsize:[24,24,24]
                -- We'll name the dummy AFTER sorting block types by category, so
                -- letters appear in legend-PDF order (Trees -> Palms -> Shrubs -> Other).
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

            -- Sort block types by category in legend-PDF order, then alphabetical by name.
            -- This makes letter assignments match the PDF legend top-to-bottom structure:
            --   Trees first, then Palms, then Shrubs, then Other.
            if typeNames.count > 0 do (
                local catPriority = #("Plants_Trees", "Plants_Palms", "Plants_Shrubs", "Plants_Other")
                local order = #()
                for i = 1 to typeNames.count do append order i
                fn priorityFor c lst = (
                    local p = findItem lst c
                    if p == 0 then 99 else p
                )
                -- bubble sort (typeNames.count is small, usually < 50)
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
                -- Reorder all parallel arrays
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

                -- Build newIdxByOld[oldIdx] = newIdx for renaming dummies
                local newIdxByOld = #()
                for k = 1 to order.count do newIdxByOld[order[k]] = k

                -- Rename every dummy with a TEMP "U<idx>" prefix (Unidentified).
                -- Final "X<n>" labels (X1, X2, ...) get assigned in PDF order
                -- as the user identifies each species via Assign Next Letter.
                local serials = #()
                for k = 1 to typeNames.count do append serials 0
                for di = 1 to dummies.count do (
                    local newIdx = newIdxByOld[dummyTypeIdx[di]]
                    serials[newIdx] += 1
                    dummies[di].name = "U" + (newIdx as string) + "_" + (formattedPrint serials[newIdx] format:"03d")
                )
                ll "dummies have temp names U1, U2, ... (X labels assigned during Assign Next Letter)" logf
            )

            if dummies.count == 0 do (
                ll "ERROR no plant blocks detected" logf
                close logf
                lblStatus.text = "ERROR: no plant blocks found in DWG."
                messageBox ("No plant blocks detected.\nCheck _work\\skipped_blocks.csv to see what was rejected.")
                return undefined
            )

            -- Build keep-set: exemplars + all their descendants (the visible block geometry)
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

            -- Delete source geometry EXCEPT dummies and the exemplar keep set
            local delList = #()
            for o in objects do (
                if (findItem dummies o) != 0 do continue
                if (findItem keepSet o) != 0 do continue
                append delList o
            )
            if delList.count > 0 do delete delList

            -- Translate to origin; capture offset
            local offset = [0,0,0]
            if dummies.count > 0 do (
                local xs=#(); local ys=#(); local zs=#()
                for d in dummies do ( append xs d.pos.x; append ys d.pos.y; append zs d.pos.z )
                local cx = (amin xs + amax xs) * 0.5
                local cy = (amin ys + amax ys) * 0.5
                local cz = amin zs
                offset = [cx, cy, cz]
                for d in dummies do d.pos = d.pos - offset
                -- exemplars get the same translation so they line up with the scene before we re-place them
                for ex in typeExemplar do ( try ( ex.pos = ex.pos - offset ) catch () )
            )
            ll ("translation offset: " + (offset as string)) logf

            ----- Build legend column to the right of the scene -----
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

                -- Persist legend layout for later Rename/Reorder operations
                lgBaseY = sceneMaxY
                lgX = legendX
                lgRowSpacing = rowSpacing
                lgLabelOffsetX = labelOffsetX
                lgTextSize = textSize
                renamedOrder = #()

                for i = 1 to typeExemplar.count do (
                    local ex = typeExemplar[i]
                    if ex == undefined or (isDeleted ex) do continue
                    local tempLabel = "U" + (i as string)
                    local rowY = sceneMaxY - (i - 1) * rowSpacing

                    -- Move the exemplar (block geometry) to its legend slot
                    try ( ex.pos = [legendX, rowY, 0] ) catch ()
                    -- Tag the exemplar with a predictable name so later steps can find it
                    try ( ex.name = "LegendExemplar_" + tempLabel ) catch ()

                    -- Add a text shape with the temp label
                    local txt = text text:tempLabel size:textSize pos:[legendX + labelOffsetX, rowY, 0]
                    txt.name = "LegendLabel_" + tempLabel
                    try ( txt.wirecolor = (color 255 220 60) ) catch ()

                    -- Move exemplar + descendants + text onto Plants_Legend layer
                    local stack = #(ex)
                    while stack.count > 0 do (
                        local n = stack[stack.count]
                        deleteItem stack stack.count
                        try ( legendLayer.addNode n ) catch ()
                        for c in n.children do append stack c
                    )
                    try ( legendLayer.addNode txt ) catch ()
                )
                ll ("legend column placed at x=" + (legendX as string) + " with " + (typeExemplar.count as string) + " symbols") logf
            )

            saveMaxFile maxOut quiet:true

            -- Write letter key CSV (gracefully handle Excel holding it open)
            if doesFileExist keyPath do (try (deleteFile keyPath) catch ())
            local kf = undefined
            try ( kf = createFile keyPath ) catch ()
            if kf == undefined then (
                ll ("WARN could not write letter_key.csv (probably open in Excel)") logf
                lblStatus.text = "Placement OK but letter_key.csv is locked by Excel."
                messageBox ("Could not write:\n" + keyPath +
                            "\n\nClose Excel (or whatever has it open) and click Place Dummies again to refresh the CSV." +
                            "\n\nPlacement itself succeeded -- " + (dummies.count as string) + " dummies on the scene.")
            ) else (
                format "temp_label,block_type,count,layer_in_dwg,category_guess,sample_x,sample_y\n" to:kf
                for i = 1 to typeNames.count do (
                    local sp = typeSample[i]
                    format "U%,%,%,%,%,%,%\n" \
                        i typeNames[i] typeCounts[i] typeLayers[i] typeCats[i] \
                        (sp[1] - offset.x) (sp[2] - offset.y) to:kf
                )
                close kf
            )

            ----- Re-import DWG as CAD reference, collapse to single frozen layer -----
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

            local layerNames = #()
            for i = 0 to (LayerManager.count - 1) do (
                local L = LayerManager.getLayer i
                if L != undefined do append layerNames L.name
            )
            fn isKeepLayer n = (
                if n == "0" or n == "Default" do return true
                if n == "CAD_Reference" do return true
                if startsWith n "Plants_" do return true
                false
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

            -- mop-up layer 0
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

            -- Open the letter-key CSV
            try ( shellLaunch keyPath "" ) catch ()

            lblStatus.text = "Placed " + (dummies.count as string) + " dummies (" + \
                              (typeNames.count as string) + " letter groups). Key CSV opened."
            messageBox ("Placement complete.\n\n" +
                        (dummies.count as string) + " dummies placed across " +
                        (typeNames.count as string) + " block types.\n\n" +
                        "Each block type is labeled with a letter (A, B, C, ...).\n" +
                        "See _work\\letter_key.csv (just opened) for letter -> block_type mapping.\n\n" +
                        "Next: right-click a dummy in Max > Select Similar,\n" +
                        "then enter species + category and click Rename Selected.")
        )

        ----- Build Legend from pasted schedule -----
        fn runBuildLegend = (
            if lgX == undefined do (
                messageBox "Run Place Dummies first."; return undefined
            )
            if cadPath == undefined do (
                messageBox "Pick CAD file first."; return undefined
            )
            local raw = ""
            try ( raw = edtSchedule.Text ) catch ()
            if raw == "" do (
                messageBox "Paste schedule text or click OCR Schedule from PDF first."
                return undefined
            )

            local pp = projectPaths cadPath
            local workDir = pp[3]
            local symbolsDir = workDir + "symbols\\"

            -- Split text into lines
            local lines = #()
            local current = ""
            for i = 1 to raw.count do (
                local c = raw[i]
                if c == "\n" or c == "\r" then (
                    if current.count > 0 do append lines current
                    current = ""
                ) else (
                    current += c
                )
            )
            if current.count > 0 do append lines current

            local entries = #()
            for ln in lines do (
                local t = trimRight (trimLeft ln " \t") " \t"
                if t.count > 0 do append entries t
            )
            if entries.count == 0 do (
                messageBox "No lines found in the schedule text."
                return undefined
            )

            -- Wipe any previously-built legend nodes (labels, symbol planes,
            -- and the DWG-exemplar legend that Place Dummies created).
            local toDel = #()
            for o in objects do (
                local nm = o.name
                if nm.count > 12 and (substring nm 1 12) == "LegendLabel_" do append toDel o
                if nm.count > 13 and (substring nm 1 13) == "LegendSymbol_" do append toDel o
                if nm.count > 15 and (substring nm 1 15) == "LegendExemplar_" do append toDel o
            )
            if toDel.count > 0 do delete toDel

            local legendLayer = LayerManager.getLayerFromName "Plants_Legend"
            if legendLayer == undefined do
                legendLayer = LayerManager.newLayerFromName "Plants_Legend"

            local placedSymbols = 0
            local placedLabels = 0
            local spacing = lgRowSpacing

            for i = 1 to entries.count do (
                local txtStr = entries[i]
                local rowY = lgBaseY - (i - 1) * spacing

                -- Species name text label
                local txt = text text:txtStr size:lgTextSize pos:[lgX + lgLabelOffsetX, rowY, 0]
                txt.name = "LegendLabel_" + (formattedPrint i format:"03d")
                try ( legendLayer.addNode txt ) catch ()
                try ( txt.wirecolor = (color 255 220 60) ) catch ()
                placedLabels += 1

                -- PDF symbol as a textured plane (if symbol PNG exists)
                local symPath = symbolsDir + "symbol_" + (formattedPrint i format:"03d") + ".png"
                if doesFileExist symPath do (
                    local sz = spacing * 0.9
                    local pl = plane width:sz length:(sz * 0.6) pos:[lgX, rowY, 0]
                    if pl != undefined do (
                        pl.widthsegs = 1
                        pl.lengthsegs = 1
                        local bmap = bitmaptexture filename:symPath
                        local mat = standardmaterial()
                        mat.diffuseMap = bmap
                        mat.selfIllumAmount = 100
                        pl.material = mat
                        try ( showTextureMap mat true ) catch ()
                        try ( mat.showInViewport = true ) catch ()
                        pl.name = "LegendSymbol_" + (formattedPrint i format:"03d")
                        try ( legendLayer.addNode pl ) catch ()
                        placedSymbols += 1
                    )
                )
            )

            if doesFileExist pp[2] do saveMaxFile pp[2] quiet:true

            lblStatus.text = "Legend built: " + (placedLabels as string) +
                             " species names, " + (placedSymbols as string) + " PDF symbols."
        )

        ----- Legacy Rename Selected (no longer wired to a button, kept for reference) -----
        fn runRename = (
            local sel = selection as array
            if sel.count == 0 do (
                messageBox "Select some dummies first (use Select Group button or right-click > Select Similar)."
                return undefined
            )
            local dummiesSel = #()
            for o in sel do (
                if (classOf o) == Dummy do append dummiesSel o
            )
            if dummiesSel.count == 0 do (
                messageBox "No dummies in current selection."
                return undefined
            )

            -- Capture the OLD letter prefix (so we can update its legend label after rename)
            local firstSel = dummiesSel[1]
            local oldNm = firstSel.name
            local underIdx = findString oldNm "_"
            local oldLetter = ""
            if underIdx != undefined and underIdx > 1 do
                oldLetter = substring oldNm 1 (underIdx - 1)

            local commonRaw = edtCommon.text
            local catRaw    = edtCategory.text
            if commonRaw == "" do (
                messageBox "Type a species name in the 'Species' field first."
                return undefined
            )
            local commonName = sanitize commonRaw
            if commonName == "" do (
                messageBox "Species name became empty after stripping punctuation. Please enter letters."
                return undefined
            )

            -- Determine layer name; allow blank category -> Plants_Other
            local cat = catRaw
            if cat.count >= 7 and (substring cat 1 7) == "Plants_" do
                cat = substring cat 8 -1
            cat = substituteString cat " " "_"
            local layerName = (if cat == "" then "Plants_Other" else "Plants_" + cat)

            local L = LayerManager.getLayerFromName layerName
            local isNewLayer = (L == undefined)
            if isNewLayer do L = LayerManager.newLayerFromName layerName
            if isNewLayer do (
                -- Assign a fresh color cycling through a palette
                local palette = #(
                    (color 230 130 220), (color 100 200 80), (color 70 150 240),
                    (color 240 180 60),  (color 220 100 60), (color 200 200 60),
                    (color 80 220 200),  (color 150 200 0),  (color 200 80 150),
                    (color 100 100 240), (color 0 200 180),  (color 240 100 100)
                )
                try ( L.wirecolor = palette[((random 1 palette.count) as integer)] ) catch ()
            )

            -- Determine the NEW X-label for this identification.
            -- - If the user selected dummies from a temp group (e.g. U3), assign the next
            --   sequential X-label (X1 first identification, X2 second, etc.).
            -- - If the user selected an already-assigned X group, re-use that label
            --   (re-identification just updates species + category + label text).
            local newLetter = ""
            local isReidentify = false
            local existingSlot = findItem renamedOrder oldLetter
            if existingSlot != 0 then (
                newLetter = oldLetter   -- already a final X-label; user is updating
                isReidentify = true
            ) else (
                newLetter = "X" + ((renamedOrder.count + 1) as string)
            )

            -- Rename ALL dummies that currently have the old prefix to the new letter prefix.
            -- Collect first (mutating mid-iteration would be risky if we relied on objects[]).
            local groupDummies = #()
            local oldPrefixDot = oldLetter + "_"
            for d in objects do (
                if (classOf d) != Dummy do continue
                if startsWith d.name oldPrefixDot do append groupDummies d
            )
            -- Sort by trailing number for clean sequential naming
            for i = 1 to groupDummies.count do (
                for j = i + 1 to groupDummies.count do (
                    if groupDummies[j].name < groupDummies[i].name do (
                        local tmp = groupDummies[i]; groupDummies[i] = groupDummies[j]; groupDummies[j] = tmp
                    )
                )
            )

            local newPrefix = newLetter + "_"
            for k = 1 to groupDummies.count do (
                groupDummies[k].name = newPrefix + (formattedPrint k format:"03d")
                try ( L.addNode groupDummies[k] ) catch ()
                try ( groupDummies[k].wirecolor = L.wirecolor ) catch ()
            )

            -- Update legend exemplar + label: rename them too, then re-layout the column.
            local exNode = getNodeByName ("LegendExemplar_" + oldLetter)
            if exNode != undefined and not isReidentify do
                try ( exNode.name = "LegendExemplar_" + newLetter ) catch ()
            local labelNode = getNodeByName ("LegendLabel_" + oldLetter)
            if labelNode == undefined do
                labelNode = getNodeByName ("LegendLabel_" + newLetter)
            if labelNode != undefined then (
                if not isReidentify do
                    try ( labelNode.name = "LegendLabel_" + newLetter ) catch ()
                try ( labelNode.text = newLetter + " - " + commonRaw ) catch ()
            )

            -- Track in renamedOrder
            if not isReidentify do append renamedOrder newLetter

            -- Re-layout the legend column:
            -- identified (renamedOrder) at top in PDF order, unidentified (X1..) below
            if lgX != undefined and lgRowSpacing != undefined do (
                local allEx = #(); local allLetters = #()
                for o in objects do (
                    local nm = o.name
                    if nm.count > 15 and (substring nm 1 15) == "LegendExemplar_" do (
                        append allEx o
                        append allLetters (substring nm 16 -1)
                    )
                )
                -- order: renamedOrder first, then anything left (X-prefixed) sorted by X-number
                local layoutOrder = #()
                for l in renamedOrder do (
                    if (findItem allLetters l) != 0 do append layoutOrder l
                )
                local leftover = #()
                for l in allLetters do (
                    if (findItem layoutOrder l) == 0 do append leftover l
                )
                -- sort leftover (U1, U2, ...) by trailing number
                for i = 1 to leftover.count do (
                    for j = i + 1 to leftover.count do (
                        local ni = 0; local nj = 0
                        try ( ni = (substring leftover[i] 2 -1) as integer ) catch ()
                        try ( nj = (substring leftover[j] 2 -1) as integer ) catch ()
                        if nj < ni do (
                            local tmp = leftover[i]; leftover[i] = leftover[j]; leftover[j] = tmp
                        )
                    )
                )
                for l in leftover do append layoutOrder l

                for k = 1 to layoutOrder.count do (
                    local lab = layoutOrder[k]
                    local rowY = lgBaseY - (k - 1) * lgRowSpacing
                    local ex = getNodeByName ("LegendExemplar_" + lab)
                    if ex != undefined do try ( ex.pos = [lgX, rowY, 0] ) catch ()
                    local lbl = getNodeByName ("LegendLabel_" + lab)
                    if lbl != undefined do try ( lbl.pos = [lgX + lgLabelOffsetX, rowY, 0] ) catch ()
                )
            )

            if cadPath != undefined do (
                local pp = projectPaths cadPath
                local maxOut = pp[2]
                if doesFileExist maxOut do saveMaxFile maxOut quiet:true
            )

            lblStatus.text = oldLetter + " -> " + newLetter + " (" + commonRaw + ") -- " + (groupDummies.count as string) + " dummies on " + layerName
            -- clear species, keep category (typically the same for the next species in same section)
            edtCommon.text = ""
        )

        ----- Reorder Legend pipeline -----
        fn runReorder = (
            if renamedOrder.count == 0 do (
                messageBox "Nothing has been renamed yet. Rename some letter groups first, then click Reorder Legend."
                return undefined
            )
            if lgX == undefined do (
                messageBox "Legend layout is not known. Run Place Dummies first in this session."
                return undefined
            )
            -- Renamed exemplars go to top, in renamedOrder sequence.
            -- Then unrenamed exemplars get stacked below them, in their original alphabetical order.
            -- Find all LegendExemplar_* and LegendLabel_* nodes
            local exemplars = #()
            local labels = #()
            local exemplarLetters = #()
            for o in objects do (
                local nm = o.name
                if nm.count > 16 and (substring nm 1 16) == "LegendExemplar_" do (
                    append exemplars o
                    append exemplarLetters (substring nm 16 -1)
                )
                if nm.count > 13 and (substring nm 1 13) == "LegendLabel_" do
                    append labels o
            )
            -- Build the new ordering: renamedOrder first, then leftover letters alphabetically
            local newOrder = #()
            for l in renamedOrder do (
                if (findItem exemplarLetters l) != 0 do append newOrder l
            )
            local leftover = #()
            for l in exemplarLetters do (
                if (findItem newOrder l) == 0 do append leftover l
            )
            -- sort leftover alphabetically
            for i = 1 to leftover.count do (
                for j = i + 1 to leftover.count do (
                    if leftover[j] < leftover[i] do (
                        local tmp = leftover[i]; leftover[i] = leftover[j]; leftover[j] = tmp
                    )
                )
            )
            for l in leftover do append newOrder l

            -- Re-position exemplars and labels according to newOrder
            for k = 1 to newOrder.count do (
                local letter = newOrder[k]
                local rowY = lgBaseY - (k - 1) * lgRowSpacing
                -- exemplar
                local exIdx = findItem exemplarLetters letter
                if exIdx != 0 do (
                    local ex = exemplars[exIdx]
                    try ( ex.pos = [lgX, rowY, 0] ) catch ()
                )
                -- label
                local labelNode = getNodeByName ("LegendLabel_" + letter)
                if labelNode != undefined do (
                    try ( labelNode.pos = [lgX + lgLabelOffsetX, rowY, 0] ) catch ()
                )
            )

            if cadPath != undefined do (
                local pp = projectPaths cadPath
                local maxOut = pp[2]
                if doesFileExist maxOut do saveMaxFile maxOut quiet:true
            )

            lblStatus.text = "Legend reordered. " + (renamedOrder.count as string) + " renamed at top, " + (leftover.count as string) + " unrenamed below."
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
        on btnPlace        pressed do ( runPlacement() )
        on btnBuildLegend  pressed do ( runBuildLegend() )
        on btnOcr pressed do (
            if pdfPath == undefined or (not (doesFileExist pdfPath)) do (
                messageBox "Pick a PDF file (button 2) first."
                return undefined
            )
            local pyScript = @"D:\Utilities\PlaceDummyTool\ocr_schedule.py"
            if not (doesFileExist pyScript) do (
                messageBox ("OCR script missing:\n" + pyScript)
                return undefined
            )
            local outPath = (getFilenamePath pdfPath) + "_ocr_output.txt"

            lblStatus.text = "Running OCR (30-60 seconds)... please wait"
            windows.processPostedMessages()

            local cmd = "python \"" + pyScript + "\" \"" + pdfPath + "\" \"" + outPath + "\""
            HiddenDOSCommand cmd

            if not (doesFileExist outPath) then (
                lblStatus.text = "OCR FAILED - no output file"
                messageBox ("OCR did not produce output.\n\nLikely cause: Python is not on PATH.\n" +
                            "Open a command prompt and try: python --version\n\nCommand attempted:\n" + cmd)
                return undefined
            )

            -- Read output
            local fIn = openFile outPath mode:"r"
            local ocrText = ""
            while not eof fIn do (
                local line = readLine fIn
                if line == undefined do exit
                ocrText += line + "\r\n"
            )
            close fIn

            if (substring ocrText 1 6) == "ERROR:" then (
                lblStatus.text = "OCR error - see popup"
                messageBox ocrText
                return undefined
            )

            try ( edtSchedule.Text = ocrText ) catch ()
            lblStatus.text = "OCR done (" + (ocrText.count as string) + " chars). Edit text, then Build Legend."
        )
        on btnSelect pressed do (
            local raw = edtLetter.text
            if raw == "" do (
                messageBox "Type a letter (A, B, C, ...) in the Letter field first."
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

        on PlaceDummyTool open do (
            -- Configure the schedule textbox as a multiline scrollable input
            try (
                edtSchedule.Multiline = true
                edtSchedule.AcceptsReturn = true
                edtSchedule.AcceptsTab = false
                edtSchedule.WordWrap = true
                edtSchedule.ScrollBars = (dotNetClass "System.Windows.Forms.ScrollBars").Vertical
            ) catch ()
        )
    )

    createDialog PlaceDummyTool style:#(#style_titlebar, #style_sysmenu, #style_resizing, #style_minimizebox)
)
