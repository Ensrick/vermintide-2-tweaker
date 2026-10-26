-- Real production transaction, whole old/new balance modules, native data/clone.
return function(H, root)
    local Fixture = assert(loadfile(root .. "/qa/lua/fixtures/wt_authentic_pistol_native_6_13.lua"))()
    local KEY, SOURCE = "wt_authentic_pistol", "shot_sniper"
    local OWNER, FALLBACK = "_wt428_authentic_pistol_owner", "_wt431_custom_profile_fallback"
    local function pack(...) return {n=select("#",...),...} end
    local function snapshot(roots)
        local rows, seen = {}, {}
        local function capture(value)
            if type(value) ~= "table" or seen[value] then return end
            seen[value]=true;local raw={}
            for key,item in next,value do raw[key]=item end
            rows[#rows+1]={value,raw,getmetatable(value)}
            for _,item in next,raw do capture(item) end
        end
        for _,value in ipairs(roots) do capture(value) end
        return function()
            for _,row in ipairs(rows) do
                H.equal(getmetatable(row[1]),row[3],"metatable identity")
                local count,expected=0,0
                local function same(a,b)
                    if type(a)=="number" and a~=a and type(b)=="number" and b~=b then return end
                    H.equal(a,b,"raw value/presence")
                end
                for key,item in next,row[1] do count=count+1;same(item,rawget(row[2],key)) end
                for key,item in next,row[2] do expected=expected+1;same(rawget(row[1],key),item) end
                H.equal(count,expected,"raw cardinality")
            end
        end
    end
    local ease=function(value) return value end
    local function fixture(ns, enabled, allowed)
        local f={ns=ns,enabled=enabled,allowed=allowed,checks={},loaded={},warnings={}}
        f.prefix=root.."/"..ns.."/scripts/mods/"..ns.."/"
        f.env=setmetatable({}, {__index=_G});f.env._G=f.env
        f.env.table=setmetatable({}, {__index=table})
        local function native(source)
            local chunk=assert(loadstring(source));setfenv(chunk,f.env);return chunk()
        end
        native(Fixture.is_class_instance);native(Fixture.clone)
        f.clone=f.env.table.clone
        f.env.DamageProfileTemplates={};native(Fixture.donor)
        f.profiles=f.env.DamageProfileTemplates;f.donor=f.profiles[SOURCE]
        f.lookup={SOURCE,"shot_carbine","light_blunt_smiter_stab",[SOURCE]=1,shot_carbine=2,light_blunt_smiter_stab=3}
        f.env.NetworkLookup={damage_profiles=f.lookup};f.network=f.env.NetworkLookup
        f.env.PowerLevelTemplates={}
        f.profiles.light_blunt_smiter_stab={charge_value="light_attack",default_target={power_distribution={attack=0.1,impact=0.2}},targets={}}
        f.env.Projectiles={pistol_shot={marker="native-pistol"}}
        f.env.math=setmetatable({easeInCubic=ease,ease_out_quad=ease},{__index=math})
        f.env.ActionTemplates={action_inspect={},wield={}}
        f.env.DamageTypes={ARMOR_PIERCING=1,CLEAVE=2,SPEED=3,STAGGER=4,DAMAGE=5}
        -- Only this disjoint 1/2/4 constant expression is evaluated; no live bit API.
        f.env.bit={bor=function(a,b,c) return a+b+c end}
        f.env.BreedCategory={Berserker=1,Special=2,Armored=4}
        f.env.AttachmentNodeLinking={pistol={right={},left={}}}
        f.template=native(Fixture.brace).brace_of_pistols_template_1
        f.env.Weapons={brace_of_pistols_template_1=f.template,two_handed_hammer_priest_template={actions={action_one={punch={damage_profile="light_blunt_smiter_stab"}}}}}
        f.mod={_wt={dbg=function() end}}
        f.mod.get=function(_,key) return key=="authentic_brace_of_pistols" and f.enabled or false end
        f.mod.info=function() end;f.mod.warning=function(_,message) f.warnings[#f.warnings+1]=message end
        f.mod.command=function() end
        f.mod._wt431_profiles_allowed=function() if f.parity_error then error(f.parity_error) end;return f.allowed end
        f.env.printf=function() end
        f.env.get_mod=function(id) H.equal(id,ns=="weapon_tweaker" and "wt" or "wt_dev");return f.mod end
        local cache={}
        f.mod.dofile=function(_,name)
            local leaf=assert(name:match("/([^/]+)$"));f.loaded[#f.loaded+1]=leaf
            if not cache[leaf] then local chunk=assert(loadfile(f.prefix..leaf..".lua"));setfenv(chunk,f.env);cache[leaf]=chunk() end
            return cache[leaf]
        end
        f.module=f.mod:dofile("scripts/mods/"..ns.."/_wt_authentic_pistol_owner")
        function f:install(deps) deps=deps or {};deps.globals=self.env;return self.module.install(self.mod,deps) end
        function f:balance(old)
            local chunk=old and assert(loadstring((Fixture.prior_balance:gsub('get_mod%("wt"%)','get_mod("'..(ns=="weapon_tweaker" and "wt" or "wt_dev")..'")')))) or assert(loadfile(self.prefix.."_wt_weapon_balance_patches.lua"))
            setfenv(chunk,self.env);return chunk()
        end
        function f:unchanged() return snapshot({self.mod,self.profiles,self.lookup,self.env.PowerLevelTemplates,self.env.Weapons}) end
        function f:slots() return self.mod._wt431_brace_profile_slots end
        return f
    end
    local function rejected(f,deps)
        local unchanged=f:unchanged();local owner,reason=f:install(deps)
        H.equal(owner,nil);H.truthy(type(reason)=="string" and reason~="");unchanged();return reason
    end
    local function entry_check(f)
        local file=assert(io.open(f.prefix..f.ns..".lua","rb"));local source=file:read("*a");file:close()
        assert(loadstring(source,"@complete-"..f.ns.."-entry")) -- Full chunk/local-limit proof, no engine execution.
        local mod_line=assert(source:match('(local mod = get_mod%("'..(f.ns=="weapon_tweaker" and "wt" or "wt_dev")..'"%))'))
        local balance=assert(source:match('(local _wt_balance_registration_verify = mod:dofile%("scripts/mods/'..f.ns..'/_wt_weapon_balance_patches"%))'))
        local checks=assert(source:match('(local _wt_runtime_checks = mod:dofile%("scripts/mods/'..f.ns..'/_wt_runtime_checks"%))'))
        local install=assert(source:match('(_wt_runtime_checks%.install%([^\n]+)'))
        H.truthy(assert(source:find(balance,1,true))<assert(source:find(install,1,true)))
        local deps={}
        if f.ns=="weapon_tweaker_dev" then deps.dev_hold_pose={};deps.hold_pose_checks=f.mod:dofile("scripts/mods/"..f.ns.."/_wt_runtime_checks_hold_pose") end
        local check
        f.env._rt_register=function(name,callback) if name=="wt_authentic_pistol_profile_registered_unconditionally" then check=callback end end
        f.env._wt_review_check_deps=deps
        local chunk=assert(loadstring(mod_line..'\n'..balance..'\n'..checks..'\nlocal _wt_runtime_check_deps = _wt_review_check_deps\n'..install))
        setfenv(chunk,f.env);chunk();H.equal(type(check),"function")
        return check
    end
    -- Verbatim portable 6.13 fragments; the freeze compares these exact bytes.
    -- scripts/unit_extensions/weapons/spread/spread_templates.lua:878-969.
    local tooltip_native_spread = [====[
SpreadTemplates.brace_of_pistols = {
	continuous = {
		still = {
			max_pitch = 0.4,
			max_yaw = 0.4,
		},
		moving = {
			max_pitch = 0.5,
			max_yaw = 0.5,
		},
		crouch_still = {
			max_pitch = 0.5,
			max_yaw = 0.5,
		},
		crouch_moving = {
			max_pitch = 0.5,
			max_yaw = 0.5,
		},
		zoomed_still = {
			max_pitch = 0,
			max_yaw = 0,
		},
		zoomed_moving = {
			max_pitch = 0.4,
			max_yaw = 0.4,
		},
		zoomed_crouch_still = {
			max_pitch = 0,
			max_yaw = 0,
		},
		zoomed_crouch_moving = {
			max_pitch = 0.4,
			max_yaw = 0.4,
		},
	},
	immediate = {
		being_hit = {
			immediate_pitch = 0.4,
			immediate_yaw = 0.4,
		},
		shooting = {
			immediate_pitch = 0.25,
			immediate_yaw = 0.25,
		},
	},
}
SpreadTemplates.pistol_special = {
	continuous = {
		still = {
			max_pitch = 1,
			max_yaw = 1,
		},
		moving = {
			max_pitch = 1.5,
			max_yaw = 1.5,
		},
		crouch_still = {
			max_pitch = 0.5,
			max_yaw = 0.5,
		},
		crouch_moving = {
			max_pitch = 1,
			max_yaw = 1,
		},
		zoomed_still = {
			max_pitch = 0,
			max_yaw = 0,
		},
		zoomed_moving = {
			max_pitch = 1,
			max_yaw = 1,
		},
		zoomed_crouch_still = {
			max_pitch = 0,
			max_yaw = 0,
		},
		zoomed_crouch_moving = {
			max_pitch = 1,
			max_yaw = 1,
		},
	},
	immediate = {
		being_hit = {
			immediate_pitch = 1.4,
			immediate_yaw = 1.4,
		},
		shooting = {
			immediate_pitch = 0.25,
			immediate_yaw = 0.25,
		},
	},
}
]====]
    -- scripts/unit_extensions/generic/generic_ammo_user_extension.lua:119-143.
    local tooltip_native_reset = [====[
GenericAmmoUserExtension.reset = function (self)
	local no_ammo = self._initialized and self:total_remaining_ammo() == 0
	local start_ammo = self._starting_loaded_ammo or self._start_ammo

	if self._ammo_immediately_available then
		self._current_ammo = start_ammo
	else
		self._current_ammo = math.min(self._ammo_per_clip, start_ammo)
	end

	self._available_ammo = self._starting_reserve_ammo or self._start_ammo - self._current_ammo
	self._shots_fired = 0

	self:_update_anim_ammo()

	if no_ammo then
		local inventory_extension = ScriptUnit.has_extension(self.owner_unit, "inventory_system")

		if inventory_extension and self.slot_name == inventory_extension:get_wielded_slot_name() then
			self:instant_reload(true, self._no_ammo_reload_event)
		end
	end

	self._initialized = true
end
]====]
    local function tooltip_fixture(ns)
        local f=fixture(ns,true,true)
        f.env.SpreadTemplates={};local chunk=assert(loadstring(tooltip_native_spread));setfenv(chunk,f.env);chunk()
        local before=f.clone(f.template,true);local spread_before=f.clone(f.env.SpreadTemplates,true)
        local aim,reload,rapid=f.template.actions.action_two.default,f.template.actions.weapon_reload.default,f.template.actions.action_one.fast_shot
        local verify=f:balance()
        H.equal(type(verify),"function");H.equal(verify(),KEY);H.equal(f.mod[OWNER].validate(),true)
        H.equal(#f:slots(),3);for _,slot in ipairs(f:slots()) do H.equal(slot.impact_data.damage_profile,KEY) end
        return f,before,spread_before,aim,reload,rapid
    end
    local function scaled(before,after,mult)
        for key,value in pairs(before) do
            if type(value)=="table" then scaled(value,after[key],mult) else H.equal(after[key],value*mult) end
        end
    end
    for _,ns in ipairs({"weapon_tweaker","weapon_tweaker_dev"}) do
        local tag=ns.." authentic pistol: "
        H.test(tag.."tooltip English agrees with installed whole-balance facts",function()
            local f=tooltip_fixture(ns)
            local file=assert(io.open(f.prefix..ns.."_localization.lua","rb"));local loc=file:read("*a");file:close()
            local text=assert(loc:match('authentic_brace_of_pistols_description%s*=%s*{%s*en%s*=%s*"([^"\r\n]*)"'))
            H.truthy(text:find("Keeps rapid fire and manual reload",1,true))
            H.truthy(text:find(f.template.ammo_data.ammo_per_clip.."-round clip",1,true))
            H.truthy(text:find(f.template.ammo_data.max_ammo.." base ammo",1,true))
            H.truthy(text:find(f.template.ammo_data.ammo_per_reload.." round loaded per reload",1,true))
            for _,fact in ipairs({"wider spread","twice-as-fast primary firing timings","Rapid-fire timings stay unchanged","matching Weapon Tweaker damage-profile catalog on every peer"}) do H.truthy(text:find(fact,1,true)) end
            for _,stale in ipairs({"no aim mode, rapid fire, or manual reload","24 to 12","so their game cannot crash","penetration"}) do H.equal(text:find(stale,1,true),nil) end
            H.equal(pcall(string.format,text),true)
        end)
        H.test(tag.."tooltip facts use native data, real installer and native ammo reset",function()
            local f,before,spread_before,aim,reload,rapid=tooltip_fixture(ns);local actions=f.template.actions
            H.equal(before.ammo_data.ammo_per_clip,12);H.equal(before.ammo_data.max_ammo,30);H.equal(before.ammo_data.ammo_per_reload,2)
            H.equal(actions.action_two.default,aim);H.equal(aim.anim_end_event_condition_func,before.actions.action_two.default.anim_end_event_condition_func)
            H.equal(actions.weapon_reload.default,reload);H.equal(reload.condition_func,before.actions.weapon_reload.default.condition_func)
            H.equal(reload.chain_condition_func,before.actions.weapon_reload.default.chain_condition_func)
            H.equal(actions.action_one.fast_shot,rapid);H.equal(rapid.total_time,before.actions.action_one.fast_shot.total_time)
            H.equal(actions.action_one.default.total_time,before.actions.action_one.default.total_time*0.5)
            H.equal(f.template.ammo_data.ammo_per_clip,6);H.equal(f.template.ammo_data.max_ammo,12);H.equal(f.template.ammo_data.ammo_per_reload,1)
            for index,row in ipairs(aim.allowed_chain_actions) do
                if row.sub_action=="fast_shot" then H.equal(row.start_time,before.actions.action_two.default.allowed_chain_actions[index].start_time) end
            end
            local spread=f.env.SpreadTemplates
            H.deep_equal(spread.brace_of_pistols,spread_before.brace_of_pistols);H.deep_equal(spread.pistol_special,spread_before.pistol_special)
            scaled(spread_before.brace_of_pistols,spread[f.template.default_spread_template],2)
            scaled(spread_before.pistol_special,spread[aim.spread_template_override],9)
            local globals=setmetatable({GenericAmmoUserExtension={},math=math},{__index=function(_,key) error("unexpected native contact "..tostring(key)) end})
            local chunk=assert(loadstring(tooltip_native_reset));setfenv(chunk,globals);chunk()
            local updates=0;local ammo={_start_ammo=f.template.ammo_data.max_ammo,_ammo_per_clip=f.template.ammo_data.ammo_per_clip,_update_anim_ammo=function() updates=updates+1 end}
            globals.GenericAmmoUserExtension.reset(ammo)
            H.equal(ammo._current_ammo,6);H.equal(ammo._available_ammo,6);H.equal(updates,1)
            f.allowed=false;f.mod._wt431_brace_repoint()
            for _,slot in ipairs(f:slots()) do H.equal(slot.impact_data.damage_profile,"shot_carbine") end
            H.equal(f.template.ammo_data.ammo_per_clip,6);H.equal(actions.action_one.default.total_time,before.actions.action_one.default.total_time*0.5)
            scaled(spread_before.brace_of_pistols,spread[f.template.default_spread_template],2)
        end)
        for _,enabled in ipairs({false,true}) do
            H.test(tag.."whole old/new balance preserves native content/order/settings "..tostring(enabled),function()
                local old,new=fixture(ns,enabled,true),fixture(ns,enabled,true)
                new.template=new.clone(old.template,true);new.env.Weapons.brace_of_pistols_template_1=new.template
                local donor=snapshot({new.donor,new.env.PowerLevelTemplates})
                old:balance(true);new:balance()
                H.deep_equal(new.profiles,old.profiles);H.deep_equal(new.lookup,old.lookup)
                H.deep_equal(new.template,old.template);H.deep_equal(new.mod[FALLBACK],old.mod[FALLBACK])
                H.equal(new.lookup[4],KEY);H.equal(new.lookup[5],"wt_priest_punch_buffed")
                H.truthy(new.mod[OWNER].validate());H.equal(new.profiles[KEY].cleave_distribution.attack,0.15)
                H.deep_equal(new.profiles[KEY].armor_modifier_far,new.donor.armor_modifier_near)
                H.deep_equal(new.profiles[KEY].default_target.power_distribution_far,new.donor.default_target.power_distribution_near)
                H.equal(new.profiles[KEY].default_target.range_modifier_settings,nil);donor()
                if enabled then
                    H.equal(#new:slots(),3)
                    for i,slot in ipairs(new:slots()) do H.equal(slot.impact_data.damage_profile,KEY);H.equal(slot.original,"shot_carbine");H.equal(slot.custom,KEY);H.equal(old:slots()[i].original,slot.original) end
                    H.equal(pack(new.mod._wt431_brace_repoint()).n,0,"callback return tuple")
                end
                local wire=assert(loadfile(new.prefix.."_wt431_wire_contract.lua"))()
                H.equal(wire.build_wire_identity(new.mod[FALLBACK],new.lookup,new.profiles),wire.build_wire_identity(old.mod[FALLBACK],old.lookup,old.profiles))
                H.deep_equal(wire.capture_catalog(new.mod[FALLBACK],new.lookup,new.profiles),wire.capture_catalog(old.mod[FALLBACK],old.lookup,old.profiles))
            end)
        end
        H.test(tag.."native clone recurses with skip_metatable rather than depth",function()
            local f=fixture(ns,false,false);local nested=setmetatable({value={x=1}},{__index={foreign=true}})
            local result=f.clone(nested,true);H.equal(getmetatable(result),nil);H.truthy(result.value~=nested.value);H.equal(result.value.x,1)
            local ok=pcall(f.clone,nested,false);H.equal(ok,false)
        end)
        H.test(tag.."unconditional owner requires neither weapons nor power templates",function()
            local f=fixture(ns,false,false);f.env.Weapons=nil;f.env.PowerLevelTemplates=nil
            local owner=assert(f:install());H.truthy(owner.validate());H.equal(f.lookup[4],KEY);H.equal(f.mod._wt431_brace_profile_slots,nil)
        end)
        H.test(tag.."repeat reuses exact owner and rejects changed ownership",function()
            local f=fixture(ns,false,false);local owner=assert(f:install());local unchanged=f:unchanged()
            local again,why=f:install();H.equal(again,owner);H.equal(why,"already-installed");unchanged()
            f.mod._wt431_brace_repoint=function() end;H.equal(f:install(),nil)
        end)
        H.test(tag.."same-module records keep two mod identities separate",function()
            local first,second=fixture(ns,false,false),fixture(ns,false,false)
            second.module=first.module
            local left,right=assert(first:install()),assert(second:install())
            H.truthy(left~=right);H.equal(first:install(),left);H.equal(second:install(),right)
            local own_callback=rawget(first.mod,"_wt431_brace_repoint")
            rawset(first.mod,OWNER,right);rawset(first.mod,"_wt431_brace_repoint",right.repoint)
            local unchanged=first:unchanged();H.equal(first:install(),nil);unchanged()
            rawset(first.mod,OWNER,left);rawset(first.mod,"_wt431_brace_repoint",own_callback)
            H.equal(first:install(),left);H.equal(second:install(),right)
        end)
        for _,kind in ipairs({"profiles","network","lookup","donor","target","cleave","sparse","reverse","foreignkey","profile_exists","pair_exists","fallback_exists","fallback_bad","owner_exists","callback_exists"}) do
            H.test(tag.."refuses "..kind.." without publication",function()
                local f=fixture(ns,false,false)
                if kind=="profiles" then f.env.DamageProfileTemplates=nil
                elseif kind=="network" then f.env.NetworkLookup=nil
                elseif kind=="lookup" then f.network.damage_profiles=nil
                elseif kind=="donor" then f.profiles[SOURCE]=nil
                elseif kind=="target" then f.donor.default_target=false
                elseif kind=="cleave" then f.donor.cleave_distribution.attack=0/0
                elseif kind=="sparse" then rawset(f.lookup,2,nil);rawset(f.lookup,"shot_carbine",nil)
                elseif kind=="reverse" then rawset(f.lookup,SOURCE,2)
                elseif kind=="foreignkey" then f.lookup.foreign=77
                elseif kind=="profile_exists" then f.profiles[KEY]={foreign=true}
                elseif kind=="pair_exists" then f.lookup[4]=KEY;f.lookup[KEY]=4
                elseif kind=="fallback_exists" then f.mod[FALLBACK]={[KEY]=SOURCE}
                elseif kind=="fallback_bad" then f.mod[FALLBACK]=false
                elseif kind=="owner_exists" then f.mod[OWNER]={}
                else f.mod._wt431_brace_repoint=function() end end
                rejected(f)
            end)
        end
        for _,kind in ipairs({"throws","returns_donor","returns_input","nested_donor","nested_input","alters_value","helper_throws","helper_extra","reader_throws"}) do
            H.test(tag.."rejects injected "..kind.." before commit",function()
                local f=fixture(ns,false,false);local deps={}
                if kind=="throws" then deps.clone=function() error("clone") end
                elseif kind=="returns_donor" then deps.clone=function() return f.donor end
                elseif kind=="returns_input" then deps.clone=function(value) return value end
                elseif kind=="nested_donor" then deps.clone=function(value) local out=f.clone(value,true);out.default_target=f.donor.default_target;return out end
                elseif kind=="nested_input" then deps.clone=function(value) local out=f.clone(value,true);out.default_target=value.default_target;return out end
                elseif kind=="alters_value" then deps.clone=function(value) local out=f.clone(value,true);out.charge_value="foreign";return out end
                elseif kind=="helper_throws" then deps.lookup={register=function() error("helper") end}
                elseif kind=="helper_extra" then local helper=f.mod:dofile("scripts/mods/"..ns.."/_lib_network_lookup");deps.lookup={register=function(t,key) local i,n=helper.register(t,key);t.foreign=1;return i,n end}
                else deps.read=function() error("reader") end end
                rejected(f,deps)
            end)
        end
        for index=1,7 do
            H.test(tag.."write "..index.." rollback including hostile raw additions",function()
                local f=fixture(ns,false,false);local writes=0
                rejected(f,{write=function(target,key,value) writes=writes+1;rawset(target,key,value);if writes==index then rawset(target,"foreign_added",true);error("commit") end end})
                H.equal(writes,index)
            end)
            H.test(tag.."dropped write "..index.." cannot claim readiness",function()
                local f=fixture(ns,false,false);local writes=0
                rejected(f,{write=function(target,key,value) writes=writes+1;if writes~=index then rawset(target,key,value) end end})
            end)
        end
        H.test(tag.."old missing lookup is a real partial-publication counterexample",function()
            local old=fixture(ns,false,false);old.network.damage_profiles=nil;old:balance(true)
            H.truthy(old.profiles[KEY]);H.equal(old.mod[FALLBACK][KEY],SOURCE)
            local f=fixture(ns,false,false);f.network.damage_profiles=nil;rejected(f)
            H.equal(f.profiles[KEY],nil);H.equal(f.mod[FALLBACK],nil)
        end)
        H.test(tag.."whole production balance refuses missing lookup before profile publication",function()
            local f=fixture(ns,false,false);f.network.damage_profiles=nil;f:balance()
            H.equal(f.profiles[KEY],nil,"no exposed pistol profile after failed registration")
            H.equal(f.mod[FALLBACK],nil,"no exposed pistol fallback after failed registration")
            H.equal(f.mod[OWNER],nil)
        end)
        for _,kind in ipairs({"profile_content","profile_replaced","profiles_replaced","network_replaced","lookup_replaced","axis","fallback","owner","callback","reader","parity"}) do
            H.test(tag.."retained "..kind.." cannot leave custom action selected",function()
                local f=fixture(ns,true,true);f:balance();local owner=f.mod[OWNER]
                if kind=="profile_content" then f.profiles[KEY].cleave_distribution.attack=7
                elseif kind=="profile_replaced" then f.profiles[KEY]={}
                elseif kind=="profiles_replaced" then f.env.DamageProfileTemplates={}
                elseif kind=="network_replaced" then f.env.NetworkLookup={}
                elseif kind=="lookup_replaced" then f.network.damage_profiles={}
                elseif kind=="axis" then f.lookup[4]="foreign"
                elseif kind=="fallback" then f.mod[FALLBACK][KEY]="foreign"
                elseif kind=="owner" then f.mod[OWNER]={}
                elseif kind=="callback" then f.mod._wt431_brace_repoint=nil
                elseif kind=="reader" then setmetatable(f.mod,{__index=function() error("read") end});f.mod._wt431_profiles_allowed=nil
                else f.parity_error={} end
                owner.repoint()
                for _,slot in ipairs(f:slots()) do H.equal(slot.impact_data.damage_profile,"shot_carbine") end
            end)
        end
        H.test(tag.."parity restores three captured originals without scaling again",function()
            local f=fixture(ns,true,true);f:balance();local before=f.clone(f.template,true)
            for _,value in ipairs({false,true,false,true}) do
                f.allowed=value;f.mod._wt431_brace_repoint()
                for _,slot in ipairs(f:slots()) do H.equal(slot.impact_data.damage_profile,value and KEY or "shot_carbine") end
            end
            H.deep_equal(f.template,before)
            f.mod._wt431_brace_profile_slots={};f.mod[OWNER].repoint()
            for _,name in ipairs({"default","fast_shot","special_action_shoot"}) do H.equal(f.template.actions.action_one[name].impact_data.damage_profile,"shot_carbine") end
        end)
        H.test(tag.."strict lookup and inherited foreign owner cells preserve raw shape",function()
            local f=fixture(ns,false,false)
            local strict={__index=function() error("strict read") end,__newindex=function() error("strict write") end}
            setmetatable(f.lookup,strict);setmetatable(f.profiles,strict)
            local donor=snapshot({f.donor});local owner=assert(f:install());H.truthy(owner.validate());donor()
            H.equal(getmetatable(f.lookup),strict);H.equal(getmetatable(f.profiles),strict)
            local other=fixture(ns,false,false);setmetatable(other.mod,{__index={[FALLBACK]={foreign=true}}});rejected(other)
        end)
        for index=1,3 do
            H.test(tag.."action write "..index.." restores raw fields and native profiles",function()
                local f=fixture(ns,true,true);local fail,writes=false,0
                local owner=assert(f:install({write=function(target,key,value)
                    rawset(target,key,value)
                    if fail and key=="damage_profile" then
                        writes=writes+1
                        if writes==index then rawset(target,"foreign_added",true);error("action-write") end
                    end
                end}))
                f:balance();f.allowed=false;fail=true;owner.repoint();H.equal(writes,index)
                for _,slot in ipairs(f:slots()) do H.equal(slot.impact_data.damage_profile,"shot_carbine");H.equal(rawget(slot.impact_data,"foreign_added"),nil) end
                f.allowed=true;fail=false;owner.repoint()
                for _,slot in ipairs(f:slots()) do H.equal(slot.impact_data.damage_profile,KEY) end
            end)
        end
        H.test(tag.."foreign replaced action remains foreign; other hands release",function()
            local f=fixture(ns,true,true);f:balance()
            f:slots()[2].impact_data.damage_profile="foreign-profile"
            f.mod[OWNER].repoint()
            H.equal(f:slots()[2].impact_data.damage_profile,"foreign-profile")
            H.equal(f:slots()[1].impact_data.damage_profile,"shot_carbine")
            H.equal(f:slots()[3].impact_data.damage_profile,"shot_carbine")
        end)
        H.test(tag.."actual runtime-check module calls retained owner and fails closed",function()
            local f=fixture(ns,false,false);local verify=f:balance();local runtime=f.mod:dofile("scripts/mods/"..ns.."/_wt_runtime_checks")
            local check
            local deps={}
            if ns=="weapon_tweaker_dev" then deps.dev_hold_pose={};deps.hold_pose_checks=f.mod:dofile("scripts/mods/"..ns.."/_wt_runtime_checks_hold_pose") end
            runtime.install(f.mod,function(name,callback) if name=="wt_authentic_pistol_profile_registered_unconditionally" then check=callback end end,deps,verify)
            H.equal(type(check),"function");H.equal(check(),nil)
            local unchanged=f:unchanged();f.profiles[KEY].cleave_distribution.attack=9
            H.truthy(type(check())=="string");f.profiles[KEY].cleave_distribution.attack=0.15;unchanged()
            f.mod[OWNER].validate=function() error("validate") end;H.truthy(type(check())=="string")
            f.mod[OWNER]=nil;H.truthy(type(check())=="string")
        end)
        for _,fault in ipairs({"forged_validator","forged_owner","paired_callback","unrelated_fields"}) do
            H.test(tag.."registered check rejects retained forgery: "..fault,function()
                local f=fixture(ns,false,false);local verify=f:balance();local owner=assert(f.mod[OWNER])
                local original_validate=owner.validate
                local runtime=f.mod:dofile("scripts/mods/"..ns.."/_wt_runtime_checks")
                local deps={};if ns=="weapon_tweaker_dev" then deps.dev_hold_pose={};deps.hold_pose_checks=f.mod:dofile("scripts/mods/"..ns.."/_wt_runtime_checks_hold_pose") end
                local check
                runtime.install(f.mod,function(name,callback) if name=="wt_authentic_pistol_profile_registered_unconditionally" then check=callback end end,deps,verify)
                H.equal(check(),nil)
                if fault=="forged_validator" then
                    f.profiles[KEY].cleave_distribution.attack=9
                    rawset(owner,"validate",function() return true end)
                elseif fault=="forged_owner" then
                    rawset(f.mod,OWNER,{token=f.module,validate=function() return true end,repoint=owner.repoint})
                elseif fault=="paired_callback" then
                    local foreign=function() return "foreign" end
                    rawset(owner,"repoint",foreign);rawset(f.mod,"_wt431_brace_repoint",foreign)
                else
                    rawset(owner,"unrelated_annotation",{value=7});rawset(f.mod,"unrelated_annotation",{value=8})
                end
                local unchanged=f:unchanged()
                if fault=="unrelated_fields" then
                    H.equal(check(),nil);H.equal(original_validate(),true);H.equal(f:install(),owner)
                else
                    local result=check();H.truthy(type(result)=="string" and not result:find("skip:",1,true))
                    H.equal(original_validate(),false,"original lexical validator must independently reject")
                    H.equal(f:install(),nil,"same-module reentry must not trust forged methods")
                end
                unchanged()
            end)
        end
        H.test(tag.."whole balance reentry cannot authorize a forged retained validator",function()
            local f=fixture(ns,true,true);f:balance()
            f.profiles[KEY].cleave_distribution.attack=9
            local forged_calls=0
            rawset(f.mod[OWNER],"validate",function() forged_calls=forged_calls+1;return true end)
            for _,slot in ipairs(f:slots()) do rawset(slot.impact_data,"damage_profile",slot.original) end
            local unchanged=f:unchanged()
            f:balance()
            H.equal(forged_calls,0);unchanged()
            for _,slot in ipairs(f:slots()) do H.equal(slot.impact_data.damage_profile,"shot_carbine") end
        end)
        for _,fault in ipairs({"forged_validator","forged_owner","paired_callback","unrelated_fields"}) do
            H.test(tag.."whole balance captures authority before setting read: "..fault,function()
                local f=fixture(ns,true,true);local before=f.clone(f.template,true)
                local original_get=f.mod.get;local forged_calls=0
                f.mod.get=function(mod,key)
                    if key=="authentic_brace_of_pistols" then
                        local owner=assert(rawget(mod,OWNER))
                        if fault=="forged_validator" then
                            f.profiles[KEY].cleave_distribution.attack=9
                            rawset(owner,"validate",function() forged_calls=forged_calls+1;return true end)
                        elseif fault=="forged_owner" then
                            rawset(mod,OWNER,{validate=function() forged_calls=forged_calls+1;return true end})
                        elseif fault=="paired_callback" then
                            local foreign=function() forged_calls=forged_calls+1 end
                            rawset(owner,"repoint",foreign);rawset(mod,"_wt431_brace_repoint",foreign)
                        else rawset(owner,"unrelated_annotation",7) end
                    end
                    return original_get(mod,key)
                end
                f:balance();H.equal(forged_calls,0)
                if fault=="unrelated_fields" then
                    H.equal(#f:slots(),3);H.truthy(f.mod[OWNER].validate())
                    for _,slot in ipairs(f:slots()) do H.equal(slot.impact_data.damage_profile,KEY) end
                else
                    H.deep_equal(f.template,before);H.equal(f:slots(),nil)
                end
            end)
        end
        for _,fault in ipairs({"forged_validator","forged_owner","unrelated_fields","healthy"}) do
            H.test(tag.."actual entry passes trusted verifier across pre-check tamper: "..fault,function()
                local f=fixture(ns,true,true);local original_get=f.mod.get;local forged_calls=0
                f.mod.get=function(mod,key)
                    if key=="authentic_brace_of_pistols" then
                        local owner=assert(rawget(mod,OWNER))
                        if fault=="forged_validator" then
                            f.profiles[KEY].cleave_distribution.attack=9
                            rawset(owner,"validate",function() forged_calls=forged_calls+1;return true end)
                        elseif fault=="forged_owner" then
                            rawset(mod,OWNER,{validate=function() forged_calls=forged_calls+1;return true end})
                        elseif fault=="unrelated_fields" then rawset(owner,"unrelated_annotation",7) end
                    end
                    return original_get(mod,key)
                end
                local check=entry_check(f);local unchanged=f:unchanged();local result=check()
                if fault=="healthy" or fault=="unrelated_fields" then H.equal(result,nil)
                else H.truthy(type(result)=="string" and not result:find("skip:",1,true));H.equal(f:slots(),nil) end
                H.equal(forged_calls,0);unchanged()
            end)
        end
        H.test(tag.."missing private check dependency never self-heals from a forged method",function()
            local f=fixture(ns,false,false);f:balance();local runtime=f.mod:dofile("scripts/mods/"..ns.."/_wt_runtime_checks")
            local deps={};if ns=="weapon_tweaker_dev" then deps.dev_hold_pose={};deps.hold_pose_checks=f.mod:dofile("scripts/mods/"..ns.."/_wt_runtime_checks_hold_pose") end
            local check
            runtime.install(f.mod,function(name,callback) if name=="wt_authentic_pistol_profile_registered_unconditionally" then check=callback end end,deps)
            H.truthy(type(check())=="string","healthy mod fields cannot replace missing private DI")
            rawset(f.mod,OWNER,{validate=function() return true end})
            local unchanged=f:unchanged();H.truthy(type(check())=="string");unchanged()
        end)
        H.test(tag.."actual entry calls and full431 boot retain catalog and firing lifecycle",function()
            local prefix=root.."/"..ns.."/scripts/mods/"..ns.."/"
            local function load(name) return assert(loadfile(prefix..name..".lua"))() end
            local Checks=assert(loadfile(root.."/qa/lua/fixtures/wt_fire_sword_heat_network.lua"))()
            local Lookup,Contract=load("_lib_network_lookup"),load("_wt431_wire_contract")
            local Json=assert(loadfile(root.."/qa/lua/fixtures/restricted_json.lua"))()
            local file=assert(io.open(prefix..ns..".lua","rb"));local entry=file:read("*a");file:close()
            local balance_call=assert(entry:match('mod:dofile%("scripts/mods/'..ns..'/_wt_weapon_balance_patches"%)'))
            local parity_call=assert(entry:match('mod:dofile%("scripts/mods/'..ns..'/_wt431_damage_profile_parity"%)'))
            local net=Checks.network(load,Json)
            local function install(mod,heavy,balance,deps,node)
                local f=fixture(ns,true,false);local env=f.env
                node.profiles[SOURCE]=f.donor
                node.profiles.light_blunt_smiter_stab=f.profiles.light_blunt_smiter_stab
                local before=#node.lookup
                assert(Lookup.register(node.lookup,SOURCE));assert(Lookup.register(node.lookup,"shot_carbine"));assert(Lookup.register(node.lookup,"light_blunt_smiter_stab"))
                node.pistol_index=before+4
                node.weapons.brace_of_pistols_template_1=f.template
                node.weapons.two_handed_hammer_priest_template=f.env.Weapons.two_handed_hammer_priest_template
                env.DamageProfileTemplates,env.Weapons=node.profiles,node.weapons
                env.NetworkLookup={damage_profiles=node.lookup};env.PowerLevelTemplates={armor_modifier_linesman_H=deps.armor_reference}
                env.mod=mod;env.get_mod=function() return mod end;env.ALIVE={[node.unit]=true}
                env.ScriptUnit={has_extension=deps.extension};env.Managers={player={human_players=deps.humans}}
                env.Network={peer_id=deps.local_peer};env.Application={guid=deps.guid};env.AiUtils={unit_breed=deps.breed}
                env.DamageUtils=node.classes.damage;env.DamageUtils.get_breed_damage_multiplier_type=deps.multiplier
                env.ActionSweep,env.ActionShieldSlam=node.classes.sweep,node.classes.slam
                env.ActionUtils,env.GameNetworkManager=node.classes.utils,node.classes.network
                env.printf=deps.log
                mod._wt.dbg=function() end;mod.warning=function() end;mod.info=function() end;mod.command=function() end
                mod.is_enabled=function() return node.enabled end
                mod.get_name=function() return ns=="weapon_tweaker" and "wt" or "wt_dev" end
                mod._wt431_custom_profile_fallback=deps.fallbacks
                mod.dofile=function(_,name) local chunk=assert(loadfile(prefix..assert(name:match('/([^/]+)$'))..'.lua'));setfenv(chunk,env);return chunk() end
                node.wire={send_rpc_attack_hit=function(...) return ... end}
                mod.hook=function(_,class,method,callback)
                    if class=="WeaponSystem" then class=node.wire end
                    return deps.hook(class,method,callback)
                end
                mod.hook_safe=function(_,class,method,callback)
                    H.equal(class,"GameNetworkManager");H.equal(method,"remove_peer")
                    deps.hook(node.classes.network,method,function(func,...) local result=pack(func(...));callback(...);return unpack(result,1,result.n) end)
                end
                local chunk=assert(loadstring(balance_call));setfenv(chunk,env);chunk()
                H.equal(node.lookup[KEY],node.pistol_index);H.equal(node.lookup.wt_priest_punch_buffed,node.pistol_index+1)
                H.truthy(mod[OWNER].validate());H.equal(#mod._wt431_brace_profile_slots,3)
                node.pistol_prefix_identity=assert(Contract.build_wire_identity(deps.fallbacks,node.lookup,node.profiles))
                local owner_chunk=assert(loadfile(prefix.."_wt_fire_sword_owner.lua"));setfenv(owner_chunk,env)
                local owner=owner_chunk().install(mod,heavy,balance)
                H.equal(owner.prepared,true);node.env=env
                return owner
            end
            local function options() return {prepare_only=true,install=install,mod_setup=function(_,node) node.settings.authentic_brace_of_pistols=true end} end
            local host,client=net:add("host",options()),net:add("client",options())
            for _,node in ipairs({host,client}) do
                local chunk=assert(loadstring(parity_call));setfenv(chunk,node.env);chunk()
                H.equal(node.mod._wt431_wire_floor_installed,true);H.truthy(node.mod._wt431_wire_catalog_snapshot)
                H.equal(node.mod[OWNER].validate(),true)
                for _,slot in ipairs(node.mod._wt431_brace_profile_slots) do H.equal(slot.impact_data.damage_profile,"shot_carbine") end
            end
            H.equal(host.pistol_prefix_identity,client.pistol_prefix_identity)
            net:connect("host","client");net:settle()
            for _,node in ipairs({host,client}) do
                H.equal(node.mod._wt431_profiles_allowed(),true)
                for _,slot in ipairs(node.mod._wt431_brace_profile_slots) do H.equal(slot.impact_data.damage_profile,KEY) end
                local result=pack(node.wire.send_rpc_attack_hit({is_server=false},1,2,3,4,5,6,node.pistol_index,nil,"tail",nil))
                H.equal(result.n,11);H.equal(result[8],node.pistol_index);H.equal(result[10],"tail")
            end
            host.on_join=function()
                for _,slot in ipairs(host.mod._wt431_brace_profile_slots) do H.equal(slot.impact_data.damage_profile,"shot_carbine") end
                local result=pack(host.wire.send_rpc_attack_hit({is_server=false},1,2,3,4,5,6,host.pistol_index,nil,"tail",nil))
                H.equal(result[8],host.lookup[SOURCE]);H.equal(result.n,11)
            end
            host.classes.network.hot_join_sync({},"late")
            host.classes.network.remove_peer({},"late")
        end)
    end
    return {fixture=fixture,snapshot=snapshot,native=Fixture}
end
