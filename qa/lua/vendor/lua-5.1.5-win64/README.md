# Vendored Lua 5.1.5 runtime

This directory contains the minimal Windows x64 runtime selected from the
LuaBinaries `lua-5.1.5_Win64_bin.zip` distribution. It is committed so local
QA and GitHub Actions never download executable code during a test run.

- Upstream: https://luabinaries.sourceforge.net/download.html
- Archive: `lua-5.1.5_Win64_bin.zip`
- Archive SHA-256: `5F34CF7D40A20A587EA351482A4207D93B92EF6F1983E910A13338253819FE93`
- `lua5.1.exe` SHA-256: `C9BF063327F6A719AA2D2C25A13A6FB006EBA3F23B53BCD6A629DC04507C18B6`
- `lua5.1.dll` SHA-256: `0D620E2AC810A76CE6D43CC8EFBA7B2329611BE37A8B16D55BB58E09B059FC6C`

`check_lua_unit_tests.ps1` also pins both executable manifests and the two
redistributed CRT assembly files by SHA-256 before starting the interpreter.

The adjacent VC80 CRT assembly files are the redistribution payload shipped in
that archive and make the old interpreter self-contained on clean Windows CI
images. Unneeded tools (`luac`, `wlua`, `bin2c`) and C++/managed CRT libraries
are intentionally omitted.

Lua itself is Copyright (C) 1994-2012 Lua.org, PUC-Rio and distributed under
the MIT license in `LICENSE.txt`.
