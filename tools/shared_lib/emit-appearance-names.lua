-- emit-appearance-names.lua <repo_root>
--
-- Emits the canonical appearance name table as deterministic tab-separated
-- rows on stdout so a PowerShell gate can read the SAME authority the Lua
-- census gates read. Same mechanism as
-- tools/gen-appearance-gaps/emit-census-gaps.lua: the pinned vendored Lua 5.1
-- host runs this, PowerShell parses the rows. No vocabulary is reimplemented
-- on the PowerShell side, because a second copy is exactly the drift this
-- authority exists to kill.
--
-- Row format:
--   axis \t name \t kind \t canonical \t reason
-- axis is surface | edge | concern; kind is canonical | alias | refinement |
-- census-gap | contract-only. Header lines are prefixed with '#'.
--
-- Exit codes: 0 = emitted, 2 = the authority contradicts the descriptor.

local repo_root = ...
if type(repo_root) ~= "string" or repo_root == "" then
	io.stderr:write("usage: emit-appearance-names.lua <repo_root>\n")
	os.exit(2)
end

local D = dofile(repo_root .. "/tools/shared_lib/_lib_appearance_descriptor.lua")
local A = dofile(repo_root .. "/tools/shared_lib/_lib_appearance_name_authority.lua")

local ok, errors = A.validate(D)
if not ok then
	io.stderr:write("appearance name authority is invalid:\n"
		.. table.concat(errors, "\n") .. "\n")
	os.exit(2)
end

local function clean(text)
	-- Reasons are single-line prose; a stray tab or newline would corrupt the
	-- stream, so normalise rather than trusting the author.
	return (tostring(text or ""):gsub("[\t\r\n]+", " "))
end

io.write("#schema_version\t", tostring(D.CENSUS_SCHEMA_VERSION), "\n")
io.write("#authority\ttools/shared_lib/_lib_appearance_name_authority.lua\n")

for _, row in ipairs(A.rows(D)) do
	io.write(table.concat({
		row.axis, row.name, row.kind, row.canonical, clean(row.reason),
	}, "\t"), "\n")
end
