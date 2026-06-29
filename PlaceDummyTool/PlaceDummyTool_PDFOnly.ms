--==============================================================
-- PlaceDummyTool_PDFOnly.ms
--
-- Experimental PDF-only flow: when there's no DWG, detect plant
-- symbols (circles) directly from the PDF and place dummies on the
-- detections. Groups dummies by symbol size, so same-size symbols
-- become the same group (U1, U2, ...).
--
-- Buttons:
--   [1] Pick PDF File (.pdf)
--   [2] Detect Plants from PDF    -- runs detect_pdf_plants.py
--   [3] Show Preview              -- opens the annotated preview image
--   [4] Place Dummies from Detection
--                                 -- creates dummies from detections.csv
--   [Select Group]                -- type U1, U2, ... and click to select
--                                    all dummies of that group
--   [Pick Surface] / [Project Dummies]
--                                 -- same as the main tool: snap dummies
--                                    onto a terrain/plane and bottom-pivot
--
-- The DWG-based tool (PlaceDummyTool.ms) is left untouched and is
-- still the preferred path when a DWG is available.
--==============================================================

(
    try ( destroyDialog ::PlaceDummyToolPDFOnly ) catch ()
    global PlaceDummyToolPDFOnly

    rollout PlaceDummyToolPDFOnly "Place Dummy Toolkit -- PDF Only" width:380 height:560
    (
        local pdfPath = undefined
        local detectionDir = undefined      -- <pdf_dir>/_work/
        local imgWidth = 0
        local imgHeight = 0
        local surfaceNode = undefined
        local lgBaseY = undefined
        local lgX = undefined
        local lgRowSpacing = undefined
        local lgLabelOffsetX = undefined
        local lgTextSize = undefined

        button btnPdf    "1. Pick PDF File (.pdf)"           width:370 height:28 align:#center
        label  lblPdf    "(none)"                            width:370 align:#center

        groupbox gbTune "Detection tuning (lower sensitivity if too many false hits):" width:370 height:80 align:#center
        spinner spSens   "Sensitivity (1-10):" pos:[20,125] fieldWidth:50 range:[1,10,5] type:#integer
        spinner spMinR   "Min radius (px):"    pos:[20,148] fieldWidth:50 range:[4,40,14] type:#integer
        spinner spMaxR   "Max radius (px):"    pos:[200,148] fieldWidth:50 range:[15,150,50] type:#integer

        button btnDetect "2. Detect Plants from PDF"         pos:[5,180] width:370 height:32 align:#center
        label  lblDetect "(no detection yet)"                pos:[5,215] width:370 align:#center
        button btnPreview "3. Show Preview Image"            pos:[5,234] width:370 height:24 align:#center
        button btnPlace  "4. Place Dummies from Detection"   pos:[5,262] width:370 height:38 align:#center
        label  lblPlaceHint "1 px = 1 Max unit. Scale dummies later if needed." pos:[5,303] width:370 align:#center

        ----- Project to surface (same as main tool) -----
        groupBox gbSurface "5. (optional) Project dummies onto a surface" pos:[5,335] width:370 height:90
        label lblSurfaceInfo "Surface: (none)" pos:[20,355] width:340 align:#left
        button btnPickSurface "Pick Surface in viewport" pos:[20,375] width:170 height:25
        button btnProject "Project Dummies"              pos:[200,375] width:170 height:25
        label lblProjHint "Ray-casts down; sets pivot to bottom of dummy." pos:[20,403] width:340 align:#left

        label hintSel "Select dummies of a group:" pos:[20,438] width:340
        edittext edtLetter "Label (U1, U2, ...):"  pos:[20,458] fieldWidth:150 labelOnTop:false
        button   btnSelect "Select Group"          pos:[240,456] width:130 height:25

        label lblStatus "Ready."  pos:[15,505] width:370 align:#center

        ----- helpers -----
        fn projectPaths pf = (
            local pdfDir  = getFilenamePath pf
            local maxOut  = pdfDir + "placedummy.max"
            local workDir = pdfDir + "_work\\"
            makeDir workDir all:true
            #(pdfDir, maxOut, workDir)
        )
        fn startsWith s prefix = (
            if prefix.count > s.count then false
            else ((substring s 1 prefix.count) == prefix)
        )
        fn getOrMakeLayer name = (
            local L = LayerManager.getLayerFromName name
            if L == undefined do L = LayerManager.newLayerFromName name
            L
        )
        fn parseSummary path = (
            -- returns #(imgW, imgH, dpi, errorMsg)
            local errMsg = undefined
            local w = 0; local h = 0; local dpi = 300
            if not (doesFileExist path) do (
                return #(0, 0, 0, "summary.txt not found")
            )
            local f = openFile path mode:"r"
            while not eof f do (
                local line = readLine f
                if line == undefined do exit
                if (startsWith line "ERROR") do (
                    errMsg = substring line 7 -1
                    continue
                )
                local tabIdx = findString line "\t"
                if tabIdx == undefined do continue
                local key = substring line 1 (tabIdx - 1)
                local val = substring line (tabIdx + 1) -1
                if key == "image_width"  do (try ( w = val as integer ) catch ())
                if key == "image_height" do (try ( h = val as integer ) catch ())
                if key == "dpi"          do (try ( dpi = val as integer ) catch ())
            )
            close f
            #(w, h, dpi, errMsg)
        )

        ----- 2. Detect Plants from PDF -----
        fn runDetect = (
            if pdfPath == undefined or (not (doesFileExist pdfPath)) do (
                messageBox "Pick a PDF first."
                return undefined
            )
            local pyScript = @"D:\Utilities\PlaceDummyTool\detect_pdf_plants.py"
            if not (doesFileExist pyScript) do (
                messageBox ("Detection script missing:\n" + pyScript)
                return undefined
            )
            local pp = projectPaths pdfPath
            detectionDir = pp[3]

            lblStatus.text = "Detecting plants in PDF (30-60s)..."
            windows.processPostedMessages()

            -- Strip trailing backslash so Windows cmd doesn't escape the closing quote
            local cleanDir = detectionDir
            while cleanDir.count > 0 and cleanDir[cleanDir.count] == "\\" do
                cleanDir = substring cleanDir 1 (cleanDir.count - 1)

            -- Capture Python stdout+stderr so we can show real errors
            local stdoutPath = detectionDir + "_python_stdout.txt"
            if doesFileExist stdoutPath do (try (deleteFile stdoutPath) catch ())

            local sensVal = spSens.value as integer
            local minRVal = spMinR.value as integer
            local maxRVal = spMaxR.value as integer
            local cmd = "python \"" + pyScript + "\" \"" + pdfPath + "\" \"" + cleanDir + "\" " + \
                        (sensVal as string) + " " + (minRVal as string) + " " + (maxRVal as string) + \
                        " > \"" + stdoutPath + "\" 2>&1"
            HiddenDOSCommand cmd

            local summaryPath = detectionDir + "summary.txt"
            local s = parseSummary summaryPath
            if s[4] != undefined then (
                lblStatus.text = "Detection FAILED -- see popup"
                local stdoutTail = ""
                if doesFileExist stdoutPath do (
                    local sf = openFile stdoutPath mode:"r"
                    local lines = #()
                    while not eof sf do (
                        local L = readLine sf
                        if L == undefined do exit
                        append lines L
                    )
                    close sf
                    -- Take last 10 lines for the popup
                    local startIdx = (amax #(1, lines.count - 9))
                    for k = startIdx to lines.count do
                        stdoutTail += lines[k] + "\n"
                )
                messageBox ("Detection failed:\n" + s[4] +
                            (if stdoutTail.count > 0 then "\n\nPython stdout/stderr (last 10 lines):\n" + stdoutTail else "") +
                            "\n\nFull log: " + stdoutPath)
                return undefined
            )
            imgWidth = s[1]
            imgHeight = s[2]
            if imgWidth == 0 do (
                messageBox "summary.txt missing image dimensions. Did the script run?"
                return undefined
            )

            -- Read group count from groups.csv
            local groupCount = 0
            local detCount = 0
            local groupsPath = detectionDir + "groups.csv"
            if doesFileExist groupsPath do (
                local f = openFile groupsPath mode:"r"
                local first = true
                while not eof f do (
                    local line = readLine f
                    if line == undefined do exit
                    if first then ( first = false; continue )
                    if line.count > 0 do groupCount += 1
                )
                close f
            )
            local detPath = detectionDir + "detections.csv"
            if doesFileExist detPath do (
                local f = openFile detPath mode:"r"
                local first = true
                while not eof f do (
                    local line = readLine f
                    if line == undefined do exit
                    if first then ( first = false; continue )
                    if line.count > 0 do detCount += 1
                )
                close f
            )

            lblDetect.text = "Detected " + (detCount as string) + " symbols in " + \
                              (groupCount as string) + " groups"
            lblStatus.text = "Detection done. Click Show Preview to verify, then Place Dummies."
        )

        ----- 3. Show Preview -----
        fn runPreview = (
            if detectionDir == undefined do (
                messageBox "Run Detect Plants first."; return undefined
            )
            local preview = detectionDir + "_pdf_plants_preview.png"
            if not (doesFileExist preview) do (
                messageBox ("Preview image missing:\n" + preview)
                return undefined
            )
            try ( shellLaunch preview "" ) catch ()
        )

        ----- 4. Place Dummies from Detection -----
        fn runPlace = (
            if detectionDir == undefined do (
                messageBox "Run Detect Plants first."; return undefined
            )
            if imgWidth == 0 do (
                messageBox "Image dimensions unknown -- re-run Detect Plants."
                return undefined
            )
            local detPath = detectionDir + "detections.csv"
            local grpPath = detectionDir + "groups.csv"
            if not (doesFileExist detPath) do (
                messageBox ("detections.csv missing:\n" + detPath)
                return undefined
            )

            -- Clear scene + create category layers
            resetMaxFile #noprompt
            local plantsLayer = getOrMakeLayer "Plants_Detected"

            -- Parse detections.csv
            local dets = #()    -- array of #(x, y, radius, gid)
            local groupCounts = #()
            local groupMaxIdx = 0
            local f = openFile detPath mode:"r"
            local first = true
            while not eof f do (
                local line = readLine f
                if line == undefined do exit
                if first then ( first = false; continue )
                if line.count == 0 do continue
                local parts = filterString line ","
                if parts.count < 4 do continue
                local x = 0; local y = 0; local r = 0; local gid = 0
                try ( x = parts[1] as integer ) catch ()
                try ( y = parts[2] as integer ) catch ()
                try ( r = parts[3] as integer ) catch ()
                try ( gid = parts[4] as integer ) catch ()
                if gid > 0 do (
                    append dets #(x, y, r, gid)
                    if gid > groupMaxIdx do groupMaxIdx = gid
                )
            )
            close f

            if dets.count == 0 do (
                messageBox "No detections to place."
                return undefined
            )

            -- Initialize per-group counter
            local counters = #()
            for i = 1 to groupMaxIdx do append counters 0

            -- Create dummies
            -- Pixel-to-world: 1 px = 1 unit. PDF Y is top-down, Max Y is bottom-up, so flip Y.
            local boxSize = 24.0
            local dummies = #()
            for d in dets do (
                local x = d[1]; local y = d[2]; local r = d[3]; local gid = d[4]
                counters[gid] += 1
                local serial = counters[gid]
                local du = Dummy pos:[x as float, ((imgHeight - y) as float), 0] boxsize:[boxSize, boxSize, boxSize]
                du.name = "U" + (gid as string) + "_" + (formattedPrint serial format:"03d")
                plantsLayer.addNode du
                append dummies du
            )

            -- Center dummies around origin
            if dummies.count > 0 do (
                local xs=#(); local ys=#()
                for du in dummies do ( append xs du.pos.x; append ys du.pos.y )
                local cx = (amin xs + amax xs) * 0.5
                local cy = (amin ys + amax ys) * 0.5
                for du in dummies do du.pos = [du.pos.x - cx, du.pos.y - cy, du.pos.z]
            )

            -- Build legend column on the right with one PDF symbol per group
            local legendLayer = getOrMakeLayer "Plants_Legend"
            try ( legendLayer.wirecolor = (color 240 200 50) ) catch ()
            local dxs=#(); local dys=#()
            for du in dummies do ( append dxs du.pos.x; append dys du.pos.y )
            local sceneMaxX = amax dxs
            local sceneMaxY = amax dys
            local sceneMinY = amin dys
            local sceneSpanY = sceneMaxY - sceneMinY
            if sceneSpanY < 1 do sceneSpanY = 1000
            local rowSpacing = sceneSpanY / (amax #(groupMaxIdx, 1) + 1)
            if rowSpacing < 200 do rowSpacing = 200
            local legendX = sceneMaxX + rowSpacing * 1.5
            local labelOffsetX = -(rowSpacing * 0.7)
            local textSize = rowSpacing * 0.6
            lgBaseY = sceneMaxY
            lgX = legendX
            lgRowSpacing = rowSpacing
            lgLabelOffsetX = labelOffsetX
            lgTextSize = textSize

            -- Parse groups.csv to know each group's symbol_png path
            local symPathByGid = #()
            for i = 1 to groupMaxIdx do append symPathByGid ""
            local fg = openFile grpPath mode:"r"
            local firstG = true
            while not eof fg do (
                local line = readLine fg
                if line == undefined do exit
                if firstG then ( firstG = false; continue )
                if line.count == 0 do continue
                local parts = filterString line ","
                if parts.count < 4 do continue
                local gid = 0
                try ( gid = parts[1] as integer ) catch ()
                if gid > 0 and gid <= groupMaxIdx do
                    symPathByGid[gid] = detectionDir + parts[4]
            )
            close fg

            for gid = 1 to groupMaxIdx do (
                local rowY = sceneMaxY - (gid - 1) * rowSpacing
                local label = "U" + (gid as string)

                -- Text label
                local txt = text text:label size:textSize pos:[legendX + labelOffsetX, rowY, 0]
                txt.name = "LegendLabel_" + label
                try ( txt.wirecolor = (color 255 220 60) ) catch ()
                try ( legendLayer.addNode txt ) catch ()

                -- Symbol plane (PDF crop)
                local symPath = symPathByGid[gid]
                if symPath != "" and (doesFileExist symPath) do (
                    local sz = rowSpacing * 0.9
                    local pl = plane width:sz length:sz pos:[legendX, rowY, 0]
                    if pl != undefined do (
                        pl.widthsegs = 1; pl.lengthsegs = 1
                        local bmap = bitmaptexture filename:symPath
                        local mat = standardmaterial()
                        mat.diffuseMap = bmap
                        mat.selfIllumAmount = 100
                        pl.material = mat
                        try ( showTextureMap mat true ) catch ()
                        try ( mat.showInViewport = true ) catch ()
                        pl.name = "LegendSymbol_" + label
                        try ( legendLayer.addNode pl ) catch ()
                    )
                )
            )

            -- Save
            local pp = projectPaths pdfPath
            saveMaxFile pp[2] quiet:true

            lblStatus.text = "Placed " + (dummies.count as string) + " dummies (" + \
                              (groupMaxIdx as string) + " groups)."
            messageBox ("Placed " + (dummies.count as string) + " dummies across " +
                        (groupMaxIdx as string) + " groups.\n\n" +
                        "Pixel coords used directly as Max units (1 px = 1 unit).\n" +
                        "Saved: " + pp[2])
        )

        ----- handlers -----
        on btnPdf pressed do (
            local p = getOpenFileName caption:"Pick PDF file" \
                          types:"PDF (*.pdf)|*.pdf|All Files|*.*"
            if p != undefined do (
                pdfPath = p
                lblPdf.text = filenameFromPath pdfPath
                lblStatus.text = "PDF picked."
                try ( shellLaunch pdfPath "" ) catch ()
            )
        )
        on btnDetect  pressed do ( runDetect() )
        on btnPreview pressed do ( runPreview() )
        on btnPlace   pressed do ( runPlace() )

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
                messageBox "Click 'Pick Surface' first."
                return undefined
            )
            local dummies = #()
            for o in objects do ( if (classOf o) == Dummy do append dummies o )
            if dummies.count == 0 do (
                messageBox "No dummies. Run Place Dummies first."
                return undefined
            )
            local castFromZ = 100000.0
            try ( castFromZ = surfaceNode.max.z + 10000.0 ) catch ()
            local projected = 0
            local missed = 0
            for d in dummies do (
                local origin = [d.pos.x, d.pos.y, castFromZ]
                local downRay = Ray origin [0, 0, -1]
                local hit = undefined
                try ( hit = intersectRay surfaceNode downRay ) catch ()
                local halfH = 12.0
                try ( halfH = (d.boxsize.z) * 0.5 ) catch ()
                if hit != undefined then (
                    d.pos = [d.pos.x, d.pos.y, hit.pos.z + halfH]
                    projected += 1
                ) else (
                    missed += 1
                )
                try ( d.pivot = [d.pos.x, d.pos.y, d.pos.z - halfH] ) catch ()
            )
            if pdfPath != undefined do (
                local pp = projectPaths pdfPath
                if doesFileExist pp[2] do saveMaxFile pp[2] quiet:true
            )
            lblStatus.text = "Projected " + (projected as string) + "/" + (dummies.count as string)
            messageBox ("Projected " + (projected as string) + " dummies onto " + surfaceNode.name +
                        (if missed > 0 then ("\n" + (missed as string) + " missed (XY outside surface).") else ""))
        )

        on btnSelect pressed do (
            local raw = edtLetter.text
            if raw == "" do (
                messageBox "Type a label (U1, U2, ...) first."
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
                lblStatus.text = "No dummies match " + pattern
                messageBox ("No dummies found with prefix " + letter + "_")
            ) else (
                select matches
                lblStatus.text = "Selected " + (matches.count as string) + " dummies (group " + letter + ")"
            )
        )
    )

    createDialog PlaceDummyToolPDFOnly style:#(#style_titlebar, #style_sysmenu, #style_resizing, #style_minimizebox)
)
