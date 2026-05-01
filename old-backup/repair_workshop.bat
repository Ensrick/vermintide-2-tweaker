@echo off
set "DST=C:\Program Files (x86)\Steam\steamapps\workshop\content\552500\3704660429"
set "SRC=C:\Users\danjo\source\repos\vermintide-2-tweaker\tweaker\.build\OUT"
echo Wiping old Workshop files...
del /q "%DST%\*.mod_bundle"
del /q "%DST%\*.mod"
echo Injecting fresh build...
copy /y "%SRC%\tweaker.mod" "%DST%\tweaker.mod"
for %%F in ("%SRC%\*") do (
    if not "%%~xF" == ".mod" (
        copy /y "%%F" "%DST%\%%~nF.mod_bundle"
        echo Copied: %%~nxF as %%~nF.mod_bundle
    )
)
echo REPAIR COMPLETE.
