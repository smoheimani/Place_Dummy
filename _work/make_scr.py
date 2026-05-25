script = (
    "FILEDIA\n0\n"
    "CMDDIA\n0\n"
    "-DXFOUT\n"
    r"D:\Utilities\Place_Dummy\_work\LandscapeArea.dxf" + "\n"
    "V\n2018\n16\n"
    "QUIT\nY\n"
)
with open(r"D:\Utilities\Place_Dummy\_work\dwg2dxf_v3.scr", "wb") as f:
    f.write(script.replace("\n", "\r\n").encode("ascii"))

import os
print(os.path.getsize(r"D:\Utilities\Place_Dummy\_work\dwg2dxf_v3.scr"), "bytes")
