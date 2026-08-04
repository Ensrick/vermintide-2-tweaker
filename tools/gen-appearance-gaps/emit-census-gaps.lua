-- emit-census-gaps.lua <repo_root>
--
-- Expands every registered appearance census to its full surface x edge matrix
-- and emits ONE deterministic tab-separated row per pair on stdout. The
-- expansion rule lives in tools/shared_lib/_lib_appearance_descriptor.lua and
-- is NOT reimplemented here: the report and the QA gate must agree by
-- construction, so both call M.expand_matrix.
--
-- Determinism: mods in M.CENSUS_FILES order, families sorted by name, surfaces
-- and edges in the canonical M.CELLS / M.EDGES order.
--
-- Row format:
--   mod \t mirror_of \t family \t surface \t edge \t state \t note
-- Header lines are prefixed with '#'.

local repo_root = ...
if type(repo_root) ~= "string" or repo_root == "" then
	io.stderr:write("usage: emit-census-gaps.lua <repo_root>\n")
	os.exit(2)
end

local D = dofile(repo_root .. "/tools/shared_lib/_lib_appearance_descriptor.lua")

local function clean(text)
	-- Notes are single-line prose; a stray tab or newline would corrupt the
	-- stream, so normalise rather than trusting the author.
	return (tostring(text or ""):gsub("[\t\r\n]+", " "))
end

io.write("#schema_version\t", tostring(D.CENSUS_SCHEMA_VERSION), "\n")
io.write("#surfaces\t", table.concat(D.CELLS, ","), "\n")
io.write("#edges\t", table.concat(D.EDGES, ","), "\n")

for _, entry in ipairs(D.CENSUS_FILES) do
	local path = repo_root .. "/" .. entry.path
	local census = dofile(path)
	if type(census) ~= "table" or type(census.families) ~= "table" then
		io.stderr:write(entry.mod .. ": census must return { families = { ... } }\n")
		os.exit(2)
	end
	if census.schema_version ~= D.CENSUS_SCHEMA_VERSION then
		io.stderr:write(entry.mod .. ": census schema_version must be "
			.. tostring(D.CENSUS_SCHEMA_VERSION) .. "\n")
		os.exit(2)
	end
	local names = {}
	for family in pairs(census.families) do names[#names + 1] = family end
	table.sort(names)
	for _, family in ipairs(names) do
		local decl = census.families[family]
		local matrix, errors = D.expand_matrix(decl.matrix, entry.mod .. "." .. family .. ".matrix")
		if not matrix then
			io.stderr:write(table.concat(errors, "\n") .. "\n")
			os.exit(2)
		end
		D.each_pair(matrix, function(surface, edge, state, note)
			io.write(table.concat({
				entry.mod, entry.mirror_of or "", family, surface, edge, state, clean(note),
			}, "\t"), "\n")
		end)
	end
end
