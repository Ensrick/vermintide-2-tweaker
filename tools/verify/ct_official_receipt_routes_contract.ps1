# #1815: exact public CT receipt routes; offline source/behavior proof only.
# Dot-sourced by live_test_contract.ps1. No publication or gameplay authority.
function Test-VtCtOfficialReceiptRoutesContract {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Root)
    $ErrorActionPreference='Stop'
    if(-not(Get-Command Get-VtCardEvidenceErrors -ErrorAction SilentlyContinue)){
        throw 'Load lifecycle_method_policy.ps1 before the CT receipt contract.'
    }
    $exceptions=Import-PowerShellDataFile (Join-Path $Root 'tools/verify/live_test_contract_exceptions.psd1')
    $rows=@($exceptions.ReceiptRouteOverrides|Where-Object{[string]$_.ModId -ceq 'ct'})
    $oracle=@(
        ,@('chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/_ct_diag_official_apply_evidence.lua','[ct:60] APPLY_OBSERVED settled census; queued/marked != removed | %s',$true)
        ,@('chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/_ct_diag_official_apply_evidence.lua','[ct:107] APPLY_OBSERVED filtered application request (not native retained-state proof) | %s',$true)
        ,@('chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/_ct_diag_official_apply_evidence.lua','[ct:146] APPLY_OBSERVED Citadel node applied/read back | %s',$true)
        ,@('chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/_ct_diag_official_apply_evidence.lua','[ct:252] APPLY_OBSERVED same-tier prompt applied/read back (not purchase proof) | %s',$true)
        ,@('chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/_ct_diag_official_apply_evidence.lua','[ct:256] APPLY_OBSERVED refresh clamp applied/read back | %s',$true)
        ,@('chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/_ct_diag_official_apply_evidence.lua','[ct:288] APPLY_OBSERVED registry applied/read back | %s',$true)
        ,@('chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/_ct_diag_official_apply_evidence.lua','[ct:288] APPLY_OBSERVED registry restored/read back | %s',$true)
        ,@('chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/_ct_diag_official_apply_evidence.lua','[ct:288] APPLY_OBSERVED post-native add active readback: %s | %s',$true)
        ,@('chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/_ct_diag_official_apply_evidence.lua','[ct:460] APPLY_OBSERVED difficulty getter return | %s',$true)
        ,@('chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/_ct_diag_official_apply_evidence.lua','[ct:460coin] APPLY_OBSERVED coin multiplier return | %s',$true)
        ,@('chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/_ct_diag_official_apply_evidence.lua','[ct:460credit] APPLY_OBSERVED native coin credit readback | %s',$true)
        ,@('chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/_ct_diag_official_apply_evidence.lua','[ct:471] APPLY_OBSERVED placement return (not enemy-spawn/completion proof) | %s',$true)
        ,@('chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/_ct_diag_official_apply_evidence.lua','[ct:471] APPLY_OBSERVED native placement threw (no completion claim) | %s',$true)
        ,@('chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/_ct_official_boon_repairs.lua','[ct:288] add parent=%s child=%s stat=%s mult=%s event=%s n=%d',$false)
        ,@('chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/_ct_progressive_modifier_runtime.lua','[ct:289] stack %d/%d node=%s curse=%s extra=%s completed=%s ladder=%s extras=%s list=%d',$true)
        ,@('chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/_ct_progressive_elite_runtime.lua','[ct:323] apply %d/%d breed=%s recipe=%s spawn=%s completed=%d rate=%d',$true)
        ,@('chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/_ct_miasma.lua','[ct:361] ',$false)
        ,@('chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/_ct_boon_pricing_runtime.lua','[ct:467] purchase accepted boon=%s price=%d tier=%s',$true)
        ,@('chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/_ct_official_chest_rescue.lua','[ct:299] key=%s %s move-before-free retained=%s corrections=%d',$false)
        ,@('chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/_ct_dev_mission.lua','[ct:505] single_mission_load level=%s diff=%s progress=%s curse=%s mod1=%s mod2=%s starting_boons=%d belakor=%s',$false)
        ,@('chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/_ct_dev_mission.lua','[ct:505] single_mission_load FAILED level=%s err=%s',$false)
        ,@('chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/_ct_tab_collectibles_layout.lua','[ct:533] deus collectibles build failed source=%s (pane remains vanilla): %s',$false)
        ,@('chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/_ct_tab_collectibles_layout.lua','[ct:533] Tab-hold collectibles -> deus counters source=%s (Chests of Trials + Pilgrim''s Coins); adventure tome/grim/dice counters suppressed',$false)
        ,@('chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/_ct_tab_collectibles_layout.lua','[ct:571] native collectible offsets count=%d rows=%d offsets=[%s] right=%.1f available=%.1f fit=%s source=IngamePlayerListUI._setup_mission_data',$false)
    )
    $checks=0
    $assert={param([bool]$Value,[string]$Message)
        if(-not$Value){throw "CT receipt contract: $Message"}
    }
    $shape={param($Items)
        & $assert (@($Items).Count -eq 24) 'exact24 route census changed'
        for($i=0;$i -lt 24;$i++){
            $row=$Items[$i];$spec=$oracle[$i]
            & $assert ([string]$row.Source -ceq $spec[0] -and [string]$row.Signature -ceq $spec[1]) "route$i source/signature changed"
            & $assert ([bool]$row.AddRoute -eq [bool]$spec[2]) "route$i constructed/discovered ownership changed"
            & $assert (@($row.ActionCommands|Where-Object{$_}).Count -eq 0) "route$i automatic evidence acquired command ownership"
        }
    }
    & $shape $rows;$checks+=73
    $trees=@($rows.ModTree|Sort-Object -Unique)
    & $assert ($trees.Count -eq 1 -and $trees[0] -cmatch '^[0-9a-f]{40}$') 'routes disagree on one canonical tree'
    $tree=[string]$trees[0];$checks++
    $modRoot='chaos_wastes_tweaker/scripts/mods'
    $documents=@(Get-ChildItem -LiteralPath (Join-Path $Root $modRoot) -Filter '*.lua' -Recurse -File|ForEach-Object{
        $path=$_.FullName.Substring($Root.TrimEnd([char[]]'\/').Length).TrimStart([char[]]'\/') -replace '\\','/'
        $text=[IO.File]::ReadAllText($_.FullName)
        [pscustomobject]@{RelativePath=$path;Content=$text;Tokens=@(Get-VtLuaTokens -Content $text)}
    })
    $baseRoutes=New-Object 'System.Collections.Generic.List[object]'
    $commands=New-Object 'System.Collections.Generic.List[object]'
    foreach($document in $documents){
        $scan=Get-VtDirectLuaCallRoutes -Document $document
        foreach($route in @($scan.ReceiptRoutes)){$baseRoutes.Add($route)}
        foreach($command in @($scan.CommandRoutes)){$commands.Add($command)}
        & $assert (-not(Test-VtLuaMutatesGlobalPrintf -Tokens $document.Tokens)) ('global printf mutation: '+$document.RelativePath)
    }
    foreach($route in @(Get-VtInjectedReceiptRoutes -ModDir 'chaos_wastes_tweaker' -Documents $documents)){$baseRoutes.Add($route)}
    Set-VtStructuralReceiptBounds -Documents $documents -Routes $baseRoutes
    $apply={param($Items=$rows,$Docs=$documents,[string]$Tree=$tree)
        $actual=New-Object 'System.Collections.Generic.List[object]'
        foreach($route in $baseRoutes){$actual.Add($route.PSObject.Copy())}
        Set-VtReceiptOverrideBounds -ModId 'ct' -ModTree $Tree -Documents $Docs -Routes $actual -CommandRoutes $commands -Exceptions @{ReceiptRouteOverrides=@($Items)}
        return ,$actual
    }
    $actual=& $apply
    foreach($row in $rows){
        $matches=@($actual|Where-Object{[string]$_.Source -ceq $row.Source -and [string]$_.Signature -ceq $row.Signature})
        & $assert ($matches.Count -eq 1 -and [bool]$matches[0].Bound) ('actual route not uniquely bounded: '+$row.Signature)
        $checks++
    }
    $reject={param([scriptblock]$Action,[string]$Needle,[string]$Label)
        $errorText=$null;try{& $Action|Out-Null}catch{$errorText=$_.Exception.Message}
        & $assert ($errorText -and $errorText -like ('*'+$Needle+'*')) ("negative did not fail closed: "+$Label+" result="+$errorText)
    }
    & $reject {& $apply -Tree ('0'*40)} 'tree drift' 'wrong immutable tree';$checks++
    foreach($index in 0..23){
        $copy=@($rows|ForEach-Object{$_.Clone()});$copy[$index].Source='missing/owner.lua'
        & $reject {& $apply -Items $copy} 'source missing' ("wrong source"+$index);$checks++
        $copy=@($rows|ForEach-Object{$_.Clone()});$copy[$index].EmitterAnchors=@('nonexistent_ct_1815_emitter()')
        & $reject {& $apply -Items $copy} 'emitter anchor drift' ("wrong emitter"+$index);$checks++
        $copy=@($rows|ForEach-Object{$_.Clone()});$copy[$index].GuardAnchors=@('nonexistent_ct_1815_guard()')
        & $reject {& $apply -Items $copy} 'guard anchor drift' ("wrong guard"+$index);$checks++
    }
    $copy=@($rows|ForEach-Object{$_.Clone()});$copy[0].ActionCommands=@('/missing_ct_1815_command')
    & $reject {& $apply -Items $copy} 'unregistered action command' 'invented action';$checks++
    $copy=@($rows|ForEach-Object{$_.Clone()});$copy[0].ActionCommands=@('/verify_ct_chest_cap')
    & $reject {& $shape $copy} 'command ownership' 'registered manual action cannot own automatic60';$checks++
    & $reject {& $apply -Items @($rows+$rows[0])} 'Duplicate receipt-route' 'duplicate exact route';$checks++
    foreach($change in @(
        @('_ct_diag_official_apply_evidence.lua','if used >= 24 then return end','if used >= 25 then return end'),
        @('_ct_diag_official_apply_evidence.lua','if last[feature] and last[feature].signature == signature then return end','if false then return end'),
        @('_ct_diag_official_apply_evidence.lua','scope, last, budgets = key, {}, {}','scope = key'),
        @('_ct_miasma.lua','if log_count >= 32 then return end','if log_count >= 33 then return end'),
        @('_ct_boon_pricing_runtime.lua','if report_count >= 24 then return end','if report_count >= 25 then return end'),
        @('_ct_progressive_modifier_runtime.lua','LOG_CAP = 12','LOG_CAP = 13'),
        @('_ct_progressive_elite_runtime.lua','LOG_CAP = 12','LOG_CAP = 13')
    )){
        $changed=$false;$altered=@($documents|ForEach-Object{
            if($_.RelativePath.EndsWith('/'+$change[0],[StringComparison]::Ordinal)){
                & $assert ($_.Content.Contains($change[1])) ('mutation preimage missing: '+$change[0]);$changed=$true
                $text=$_.Content.Replace($change[1],$change[2])
                [pscustomobject]@{RelativePath=$_.RelativePath;Content=$text;Tokens=@(Get-VtLuaTokens -Content $text)}
            }else{$_}
        })
        & $assert $changed 'mutation document missing'
        & $reject {& $apply -Docs $altered} 'guard anchor drift' ('real cap/context mutation '+$change[0]);$checks++
    }
    $targets=@([pscustomobject]@{ReceiptRoutes=@($actual.ToArray())})
    foreach($text in @(
        '[ct:60] APPLY_OBSERVED settled census; queued/marked != removed',
        '[ct:107] APPLY_OBSERVED filtered application request (not native retained-state proof)',
        '[ct:146] APPLY_OBSERVED Citadel node applied/read back',
        '[ct:252] APPLY_OBSERVED same-tier prompt applied/read back (not purchase proof)',
        '[ct:256] APPLY_OBSERVED refresh clamp applied/read back',
        '[ct:288] rows',
        '[ct:289] stack',
        '[ct:299] key=... ... move-before-free retained=true corrections=...',
        '[ct:323] apply',
        '[ct:361] rows',
        '[ct:460] APPLY_OBSERVED difficulty getter return',
        '[ct:460coin] APPLY_OBSERVED coin multiplier return',
        '[ct:460credit] APPLY_OBSERVED native coin credit readback',
        '[ct:467] purchase accepted',
        '[ct:471] APPLY_OBSERVED placement return (not enemy-spawn/completion proof)',
        '[ct:505] single_mission_load',
        '[ct:533] Tab-hold collectibles',
        '[ct:533] deus collectibles build failed',
        '[ct:571] native collectible offsets'
    )){
        $card='Expected: '+[char]96+$text+[char]96
        & $assert (@(Get-VtCardEvidenceErrors -Card $card -Authority ([pscustomobject]@{Kind='source-only-fixture'}) -Targets $targets).Count -eq 0) ('exact selector rejected: '+$text)
        $checks++
    }
    foreach($case in @(
        @('[ct:256] rows','diagnostic-evidence-not-bounded:'),
        @('[ct:460] rows','diagnostic-evidence-not-bounded:'),
        @('[ct:467] rows','diagnostic-evidence-not-bounded:'),
        @('[ct:470] backfill row','diagnostic-evidence-not-in-selected-build:'),
        @('[ct:ct_chest_cap] rows','diagnostic-evidence-not-in-selected-build:'),
        @('[ct:299] retained move-before-free PASS','diagnostic-evidence-signature-not-source-registered:'),
        @('[ct:533] construction source','diagnostic-evidence-signature-not-source-registered:')
    )){
        $errors=@(Get-VtCardEvidenceErrors -Card ('Expected: '+[char]96+$case[0]+[char]96) -Authority ([pscustomobject]@{Kind='source-only-fixture'}) -Targets $targets)
        & $assert (@($errors|Where-Object{$_ -like ($case[1]+'*')}).Count -gt 0) ('unsafe selector admitted: '+$case[0]);$checks++
    }
    # Run actual installed helper bytes, not a copied implementation/ready stub.
    $lua=Join-Path $Root 'qa/lua/vendor/lua-5.1.5-win64/lua5.1.exe'
    & $assert ((Get-FileHash -LiteralPath $lua -Algorithm SHA256).Hash -ceq 'C9BF063327F6A719AA2D2C25A13A6FB006EBA3F23B53BCD6A629DC04507C18B6') 'vendored Lua executable changed'
    $program=@'
local root=assert(arg[1]):gsub("\\","/")
local path=root.."/chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/_ct_diag_official_apply_evidence.lua"
local count=0
local function check(value,why) assert(value,why);count=count+1 end
local function fixture()
 local f={rows={},commands={},checks={},level="mission",run=1,rc={}}
 local env=setmetatable({},{__index=_G});env._G=env;f.env=env
 env.printf=function(fmt,...) f.rows[#f.rows+1]=string.format(fmt,...) end
 f.rc.get_run_id=function()return f.run end
 env.LevelHelper={current_level_settings=function()return{level_id=f.level}end}
 env.Managers={player={is_server=true},state={},mechanism={game_mechanism=function()return{get_deus_run_controller=function()return f.rc end}end}}
 local mod={};f.mod=mod
 function mod:command(name,_,fn) assert(not f.commands[name]);f.commands[name]=fn end
 function mod:echo()end
 local chunk=assert(loadfile(path));setfenv(chunk,env)
 f.E=chunk()(mod,{effective_setting=function()return false end,runtime={},rt_register=function(name,fn)f.checks[name]=fn end})
 function f.n(marker)local n=0;for _,s in ipairs(f.rows)do if s:sub(1,#marker)==marker then n=n+1 end end;return n end
 return f
end
local f=fixture()
f.E.record("60","settled census; queued/marked != removed",{n=1})
f.E.record("60","settled census; queued/marked != removed",{n=1})
check(f.n("[ct:60]")==1,"identical receipt must deduplicate")
for i=2,40 do f.E.record("60","settled census; queued/marked != removed",{n=i})end
check(f.n("[ct:60]")==24,"feature60 absolute context cap")
f.E.record("107","filtered application request (not native retained-state proof)",{n=1})
check(f.n("[ct:107]")==1,"separate feature budget")
f.level="next";f.E.record("60","settled census; queued/marked != removed",{n=1})
check(f.n("[ct:60]")==25,"level invalidates budget")
f.run=2;f.E.record("60","settled census; queued/marked != removed",{n=1})
check(f.n("[ct:60]")==26,"run invalidates budget")
f.rc._ct_evidence_generation=2;f.E.record("60","settled census; queued/marked != removed",{n=1})
check(f.n("[ct:60]")==27,"setup generation invalidates budget")
f.E.record("252","same-tier prompt applied/read back (not purchase proof)",{text="x|\n"..string.rep("z",200),bad={}})
check(not f.rows[#f.rows]:find("bad=",1,true) and not f.rows[#f.rows]:find("\n",1,true),"scalar-only sanitized payload")
local history=f.commands.verify_ct_altar_reroll()
check(history.status=="SKIP" and f.n("[ct:ct_altar_reroll]")==1,"historical receipt cannot become live PASS")
f.mod._ct_official_chest_cap={inspect=function()return{status="PASS",reason="fresh census",fields={count=3}}end}
local summary=f.commands.verify_ct_chest_cap()
check(summary.status=="PASS" and f.n("[ct:ct_chest_cap]")==1 and f.n("[ct:60]")==27,"manual summary marker is not automatic60")
f.mod._ct_official_chest_cap.inspect=function()error("owner unavailable")end
check(f.commands.verify_ct_chest_cap().status=="SKIP","throwing live owner fails closed")
local tries=0;f.env.printf=function()tries=tries+1;error("printer")end
for i=1,40 do f.E.record("471","placement return (not enemy-spawn/completion proof)",{n=i})end
check(tries==24,"throwing printer still consumes bounded attempts")
f=fixture()
local hero,left,right={},{},{}
local ext={_current_ammo=4,_available_ammo=8,_shots_fired=0,_max_ammo=20,_ammo_per_clip=6,ammo_count=function()return 4 end,clip_size=function()return 6 end}
local inv={get_slot_data=function()return{left_unit_1p=left,right_unit_1p=right}end}
f.env.Managers.player.local_player=function()return{player_unit=hero}end
f.env.Unit={alive=function()return true end}
f.env.ScriptUnit={has_extension=function(u,system)if u==hero then return inv else return ext end end}
check(f.commands.verify_ct_ammo_bounds().status=="PASS" and f.n("[ct:256]")==2 and f.n("[ct:ct_ammo_bounds]")==1,"two current ammo details plus distinct command summary")
f.checks.ct_meta_ammo_current_floor_256()
check(f.n("[ct:256]")==4 and f.n("[ct:ct_ammo_bounds]")==1,"regression path emits details, not command summary")
f=fixture();local units,byid={},{}
for i=1,200 do local u={id=i};units[u]=true;byid[i]=u end
f.env.Unit={alive=function()return true end}
f.env.ScriptUnit={has_extension=function()return{pickup_name="throwing_axe"}end}
f.env.Managers.state.entity={system=function()return{linked_projectile_units={units}}end}
f.env.Managers.state.unit_storage={go_id=function(_,u)return u.id end,unit=function(_,id)return byid[id]end}
check(f.commands.verify_ct_linked_pickups().status=="SKIP" and f.n("[ct:322]")==128 and f.n("[ct:ct_linked_pickups]")==1,"128-detail limit remains SKIP when truncated")
f.checks.ct_linked_pickup_identity_322()
check(f.n("[ct:322]")==256 and f.n("[ct:ct_linked_pickups]")==1,"regression linked path has independent128 bound, no summary")
print("CT_RECEIPT_LUA_PASS "..count)
'@
    & $assert (-not $Root.Contains('"') -and -not $Root.Contains([string][char]10) -and -not $Root.Contains([string][char]13)) 'unsafe Lua root argument'
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=$lua;$start.Arguments='- "'+$Root+'"';$start.WorkingDirectory=$Root
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true
    $start.RedirectStandardInput=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    $null=$start.EnvironmentVariables.Remove('VT2_CT_EVIDENCE_OVERLAY_ROOT')
    $process=New-Object Diagnostics.Process
    $process.StartInfo=$start
    try{
        & $assert ($process.Start()) 'could not start owned Lua proof'
        $outTask=$process.StandardOutput.ReadToEndAsync();$errTask=$process.StandardError.ReadToEndAsync()
        $process.StandardInput.Write($program);$process.StandardInput.Close()
        if(-not$process.WaitForExit(30000)){$process.Kill();throw 'CT receipt Lua proof timed out'}
        $stdout=$outTask.Result;$stderr=$errTask.Result
        & $assert ($process.ExitCode -eq 0 -and $stdout.Trim() -ceq 'CT_RECEIPT_LUA_PASS 15') ("actual Lua proof failed: "+$stderr+" "+$stdout)
    }finally{$process.Dispose()}
    $checks+=15
    Write-Host "[live-test-contract] CT official receipt routes passed:24 exact routes, $checks source/selector/adversarial/Lua assertions (not gameplay acceptance)."
    return [pscustomobject]@{Routes=24;Assertions=$checks;LuaAssertions=15}
}
