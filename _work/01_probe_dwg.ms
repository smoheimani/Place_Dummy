--==============================================================
-- 01_probe_dwg.ms
-- Purpose:  Open a fresh 3ds Max scene, import the landscape DWG
--           preserving block hierarchy, then write every imported
--           node's name + insertion point to a CSV file so we know
--           exactly which AutoCAD blocks represent plants.
--
-- HOW TO RUN:
--   1. Open 3ds Max 2023.
--   2. File > New > New All  (or just keep an empty scene).
--   3. Scripting menu > Run Script...
--   4. Pick this file:  D:\Utilities\Place_Dummy\_work\01_probe_dwg.ms
--
-- IMPORTANT (one-time setup before running):
--   When the DWG import dialog appears, on the Geometry tab set
--      "Combine Objects by:"  =  "Layer, Blocks as Node Hierarchy"
--   and leave the rest at defaults, then click OK.
--   That setting makes each block instance arrive as its own node.
--==============================================================

clearListener()

dwgPath  = @"D:\Utilities\Place_Dummy\LandscapeArea.dwg"
csvPath  = @"D:\Utilities\Place_Dummy\_work\imported_objects.csv"

format "Importing %\n" dwgPath
-- noPrompt:false so the dialog appears (only this one time)
importFile dwgPath
format "Import done. Object count = %\n" objects.count

f = createFile csvPath
format "name,class,layer,wirecolor,x,y,z,isGroupHead\n" to:f

for o in objects do (
    nm  = o.name
    cls = (classOf o) as string
    lyr = try (o.layer.name) catch ("?")
    wc  = try (o.wirecolor as string) catch ("?")
    igh = (isGroupHead o)
    format "%,%,%,%,%,%,%,%\n" nm cls lyr wc o.pos.x o.pos.y o.pos.z igh to:f
)
close f

format "Wrote %\n" csvPath
format "Now look at the CSV (or share it) so we can identify plant blocks.\n"
