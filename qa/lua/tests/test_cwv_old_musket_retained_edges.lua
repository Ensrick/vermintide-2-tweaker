-- #428 independent-review edges through the same real installer/VMF/native path.
-- R1 fails the four defect oracles below; controls pin literal false, native
-- lifecycle exits, raw/meta preservation and weak-reference ownership.
return function(H,root)
    local quiet=setmetatable({test=function()end,test_if=function()end},{__index=H})
    local T=dofile(root.."/qa/lua/tests/test_cwv_old_musket_shot_owner.lua")(quiet,root)
    local make=dofile(root.."/qa/lua/fixtures/cwv_retained_sweep_harness.lua")
    local function new(config)return make(T,H,root,config)end
    local function tick(p)return p.ext:update(nil,nil,0.001,nil,100.001)end
    local function test(name,fn)H.test("#428 retained edge "..name,fn)end
    local function skip(p)local verdict=p.check();H.truthy(type(verdict)=="string"and verdict:sub(1,5)=="skip:")end
    local function unproven(p)local verdict=p.check();H.truthy(type(verdict)=="string"and verdict:sub(1,5)~="skip:","current unproven target is not no observation")end
    local function borrowed()
        local p=new()
        p.env.VMFMod.hook_disable(p.c.mod,p.env.WeaponUnitExtension,"start_action")
        p.env.VMFMod.hook_disable(p.c.mod,p.env.ActionSweep,"_get_damage_profile_name")
        p.start()
        p.env.VMFMod.hook_enable(p.c.mod,p.env.WeaponUnitExtension,"start_action")
        p.env.VMFMod.hook_enable(p.c.mod,p.env.ActionSweep,"_get_damage_profile_name")
        return p
    end
    local function pack(...)return {n=select('#',...),...}end
    test("actual native false hand is healthy",function()
        local p=new();p.start(false)
        H.equal(p.ext.actions.sweep._action_hand,false,"native preserves false")
        H.equal(p.check(),nil,"false uses native fallback; must not become a guard defect")
        p.queue();tick(p);H.equal(p.ledger.send,1);H.equal(p.ledger.rig_enable,0)
    end)
    test("borrowed native active target without record fails visibly",function()
        local p=borrowed();p.queue();tick(p)
        H.equal(p.ledger.send,0);unproven(p)
    end)
    test("metatable cannot supply native cleanup callback",function()
        local p=new();p.start();p.queue();local unsafe=0
        local meta={__index={finish_function=function()unsafe=unsafe+1 end}}
        setmetatable(p.action,meta);local lookup=T.shape(p.lookup)
        tick(p)
        H.equal(unsafe,0,"unproven inherited callback must never run")
        H.equal(p.ledger.send,0);H.equal(p.ledger.rig_enable,0)
        H.truthy(p.check():find("terminal",1,true))
        H.equal(getmetatable(p.action),meta,"do not repair foreign metadata")
        H.equal(rawget(p.action,"finish_function"),nil);T.unchanged(lookup)
    end)
    test("initial non-nil action metatable is not admitted",function()
        local c=T.installed(function(c)
            local original=c.mod.dofile
            c.mod.dofile=function(self,path)
                local value=original(self,path)
                if path:match("/_cwv_old_musket_melee_owner$")then
                    local bind=value.bind
                    return {bind=function(...)
                        local create=bind(...)
                        return function(opts)
                            local clone=opts.clone
                            opts.clone=function(source)
                                local result=clone(source)
                                if result.actions then setmetatable(result.actions.action_one.light_attack_left,
                                    {__index={finish_function=function()error("unproven initial callback")end}})end
                                return result
                            end
                            return create(opts)
                        end
                    end}
                end
                return value
            end
        end)
        H.equal(c.capsule.admit_old_musket({item_key="cwv_es_musket_old",template="old_musket_template"}),false)
        H.equal(rawget(c.env.Weapons,"old_musket_template_melee"),nil)
        for _,name in ipairs({"heavy_slashing_tank","heavy_slashing_smiter_stab_polearm","medium_spear_smiter_stab","medium_slashing_linesman_spear"})do
            H.equal(rawget(c.env.DamageProfileTemplates,"cwv_old_musket_melee_"..name),nil)
        end
    end)
    test("nil false left right preserve complete native tuple holes",function()
        for _,case in ipairs({{},{hand=false},{hand="left"},{hand="right"}})do
            local p=new({tuples=true});local result=pack(p.start(case.hand))
            H.equal(result.n,4);H.equal(result[1],nil);H.equal(result[2],"start");H.equal(result[3],nil);H.equal(result[4],4)
            H.equal(p.ext.actions.sweep._action_hand,case.hand);H.equal(p.ledger.helper,1);H.equal(p.check(),nil)
            local finish=pack(p.ext.actions.sweep:finish("interrupted"))
            H.equal(finish.n,4);H.equal(finish[1],nil);H.equal(finish[2],"finish");H.equal(finish[3],nil);H.equal(finish[4],4)
        end
    end)
    test("no-record repeated checks neither adopt nor initiate cleanup",function()
        local p=borrowed();p.queue();local shape=T.shape(p.lookup)
        for _=1,3 do tick(p);unproven(p)end
        H.equal(p.ledger.send,0);H.equal(p.ledger.rig_enable,0);H.equal(p.ledger.buff_remove,0)
        H.equal(p.ext.current_action_settings,p.action);T.unchanged(shape)
        -- Only a genuinely observed fresh start can create its private epoch.
        p.start();H.equal(p.check(),nil);H.equal(p.ledger.rig_enable,1)
        p.queue();tick(p);H.equal(p.ledger.send,1)
    end)
    test("no-record native completed exit is out of scope",function()
        local p=borrowed();tick(p);unproven(p);H.equal(p.ledger.rig_enable,0)
        p.ext:stop_action("interrupted")
        H.equal(p.ext.current_action_settings,nil);H.equal(p.ledger.rig_enable,1);skip(p)
    end)
    test("no-record actual unmanaged native transition is out of scope",function()
        local p=borrowed();p.queue();tick(p);unproven(p)
        p.ext:start_action("action_one","light_attack_left",p.native_actions,100,650,nil)
        H.equal(p.ledger.send,0);H.equal(p.ledger.rig_enable,1);H.equal(p.ext.current_action_settings,p.native_actions.action_one.light_attack_left)
        skip(p)
    end)
    test("no-record destroyed unit is out of scope without cleanup",function()
        local p=borrowed();tick(p);unproven(p)
        p.ext.actions.sweep.weapon_unit.dead=true;skip(p)
        H.equal(p.ledger.rig_enable,0);H.equal(p.ledger.send,0)
    end)
    test("no-record missing or mismatched caller remains a failure",function()
        local p=borrowed();tick(p);p.ext.actions.sweep._weapon_extension=nil;unproven(p)
        local q=borrowed();tick(q);q.ext.actions.sweep.current_action={};unproven(q)
        H.equal(p.ledger.rig_enable,0);H.equal(q.ledger.rig_enable,0)
    end)
    test("protected changed action metadata is never repaired",function()
        local p=new();p.start();p.queue();local unsafe=0
        local meta={__metatable="foreign-protected",__index={finish_function=function()unsafe=unsafe+1 end}}
        setmetatable(p.action,meta);tick(p)
        H.equal(unsafe,0);H.equal(p.ledger.rig_enable,0);H.equal(p.ledger.send,0)
        H.equal(getmetatable(p.action),"foreign-protected");H.truthy(p.check():find("terminal",1,true))
    end)
    test("weak latest unproven row does not retain native instance cycles",function()
        local p=borrowed();tick(p);unproven(p)
        local weak=setmetatable({p.ext,p.ext.actions.sweep},{__mode="v"})
        local env=p.env;p.release();p=nil;collectgarbage("collect");collectgarbage("collect")
        H.equal(weak[1],nil);H.equal(weak[2],nil);H.truthy(env.ActionSweep.finish)
    end)
    test("foreign hand table is not retained in weak action ledger",function()
        local p=new();p.start();p.ext:stop_action("interrupted")
        local bad={instance=p.ext.actions.sweep};local ok,err=pcall(p.start,bad)
        H.equal(ok,false);H.truthy(tostring(err):find("concatenate",1,true));unproven(p)
        local weak=setmetatable({p.ext,p.ext.actions.sweep,bad},{__mode="v"});local env=p.env
        p.release();p=nil;bad=nil;collectgarbage("collect");collectgarbage("collect")
        H.equal(weak[1],nil);H.equal(weak[2],nil);H.equal(weak[3],nil);H.truthy(env.ActionSweep.finish)
    end)
    test("missing-record inner fence allocates no new table or closure",function()
        local text=T.read(root.."/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_guard428_old_musket_sweep.lua")
        local a=assert(text:find("local function update_hook(",1,true));local b=assert(text:find("local function finish_hook(",a,true))
        local body=text:sub(a,b-1):gsub("%-%-[^\n]*","")
        H.equal(body:find("{",1,true),nil);H.equal(body:find("function",#"local function"+1,true),nil)
    end)
end
