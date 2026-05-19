-- Ported byte-for-byte from the decompiled original Material-Hijack
-- (anim_texture_extension.lua). No defensive changes needed here — the
-- extension only operates on units that already passed Material-Hijack's
-- gating in the main script.
local mod = get_mod("material_hijack_patched")

local unit_alive = Unit.alive
local material_set_texture = Material.set_texture

AnimTextureExtension = class(AnimTextureExtension)

AnimTextureExtension.init = function (self, unit)
    self.unit = unit
    self.aniamted_channels = {}
    self.frame_delay = {}
    self.loop_on_spawn = {}
    self.num_of_loops = {}
    self.frame_numbers = {}
    self.unit_time = {}
    self.texture_slot_names = {}

    if Unit.has_data(unit, "animation") then
        for i = 1, 5, 1 do
            if Unit.has_data(unit, "animation", "slot" .. tostring(i)) then
                self:get_frames(unit, "slot" .. tostring(i), "colors")
                self:get_texture_slot_names(unit, "colors")
                self:get_frames(unit, "slot" .. tostring(i), "normals")
                self:get_texture_slot_names(unit, "normals")
                self:get_frames(unit, "slot" .. tostring(i), "MABs")
                self:get_texture_slot_names(unit, "MABs")
                self:get_frames(unit, "slot" .. tostring(i), "emis_colors")
                self:get_texture_slot_names(unit, "emis_colors")
                self:get_frames(unit, "slot" .. tostring(i), "emis_details")
                self:get_texture_slot_names(unit, "emis_details")
            end
        end
    else
        self:destroy()
    end

    self.unit_mat_dict = {}
    self:get_materials(unit)
end

AnimTextureExtension.get_frames = function (self, unit, mat_slot_key, slot_type)
    local mat_slot = Unit.get_data(unit, "mat_slots", mat_slot_key)

    if not self.aniamted_channels[mat_slot] then
        self.aniamted_channels[mat_slot] = {}
    end

    self.aniamted_channels[mat_slot][slot_type] = {}
    local i = 1

    while Unit.has_data(unit, "animation", mat_slot_key, slot_type, tostring(i)) do
        self.aniamted_channels[mat_slot][slot_type][i] = Unit.get_data(unit, "animation", mat_slot_key, slot_type, tostring(i))
        i = i + 1
    end

    if not self.frame_numbers[mat_slot] then
        self.frame_numbers[mat_slot] = {}
    end

    self.frame_numbers[mat_slot][slot_type] = {
        loops = 0,
        current_number = 1,
        max_number = i - 1,
    }

    self:get_time(unit, mat_slot_key, mat_slot, slot_type)
    self:get_spawn_loop(unit, mat_slot_key, mat_slot, slot_type)
    self:get_num_of_loops(unit, mat_slot_key, mat_slot, slot_type)
end

AnimTextureExtension.get_time = function (self, unit, mat_slot_key, mat_slot, slot_type)
    if not self.frame_delay[mat_slot] then self.frame_delay[mat_slot] = {} end
    if not self.unit_time[mat_slot] then self.unit_time[mat_slot] = {} end
    if Unit.has_data(unit, "animation", mat_slot_key, slot_type, "frame_delay") then
        self.frame_delay[mat_slot][slot_type] = Unit.get_data(unit, "animation", mat_slot_key, slot_type, "frame_delay")
        self.unit_time[mat_slot][slot_type] = 0
    end
end

AnimTextureExtension.get_spawn_loop = function (self, unit, mat_slot_key, mat_slot, slot_type)
    if not self.loop_on_spawn[mat_slot] then self.loop_on_spawn[mat_slot] = {} end
    if Unit.has_data(unit, "animation", mat_slot_key, slot_type, "loop_on_spawn") then
        self.loop_on_spawn[mat_slot][slot_type] = Unit.get_data(unit, "animation", mat_slot_key, slot_type, "loop_on_spawn")
    end
end

AnimTextureExtension.get_num_of_loops = function (self, unit, mat_slot_key, mat_slot, slot_type)
    if not self.num_of_loops[mat_slot] then self.num_of_loops[mat_slot] = {} end
    if Unit.has_data(unit, "animation", mat_slot_key, slot_type, "num_of_loops") then
        self.num_of_loops[mat_slot][slot_type] = Unit.get_data(unit, "animation", mat_slot_key, slot_type, "num_of_loops")
    end
end

AnimTextureExtension.get_materials = function (self, unit)
    local count = 1
    local mat_slots = {}
    while Unit.get_data(unit, "mat_slots", "slot" .. tostring(count)) do
        mat_slots[count] = Unit.get_data(unit, "mat_slots", "slot" .. tostring(count))
        count = count + 1
    end

    local num_meshes = Unit.num_meshes(unit)
    for i = 0, num_meshes - 1, 1 do
        local mesh = Unit.mesh(unit, i)
        local num_mats = Mesh.num_materials(mesh)
        for j = 0, num_mats - 1, 1 do
            for _, mat_slot in ipairs(mat_slots) do
                if Mesh.has_material(mesh, mat_slot) then
                    local material = Mesh.material(mesh, mat_slot)
                    self.unit_mat_dict[mat_slot] = material
                end
            end
        end
    end
end

local slot_key_dict = {
    normals      = "norm_slot",
    emis_details = "emis_det_slot",
    colors       = "color_slot",
    MABs         = "MAB_slot",
    emis_colors  = "emis_col_slot",
}

AnimTextureExtension.get_texture_slot_names = function (self, unit, slot_type)
    local texture_slot_key = slot_key_dict[slot_type]
    self.texture_slot_names[slot_type] = Unit.get_data(unit, texture_slot_key)
end

AnimTextureExtension.update = function (self, dt, unit)
    if not unit_alive(unit) then
        self:destroy()
        return
    end

    local time_list = self.unit_time
    local frame_delay_list = self.frame_delay
    local material_dict = self.unit_mat_dict
    local loop_list = self.loop_on_spawn
    local frame_numbers = self.frame_numbers

    for mat_slot, mat_data in pairs(frame_delay_list) do
        for slot_type, delay_time in pairs(mat_data) do
            if loop_list[mat_slot][slot_type] then
                local current_time = time_list[mat_slot][slot_type]
                if delay_time <= current_time then
                    local material = material_dict[mat_slot]
                    local max_frame_number = frame_numbers[mat_slot][slot_type].max_number
                    local frame_number = frame_numbers[mat_slot][slot_type].current_number % max_frame_number + 1
                    local texture = self.aniamted_channels[mat_slot][slot_type][frame_number]
                    local texure_slot_name = self.texture_slot_names[slot_type]

                    material_set_texture(material, texure_slot_name, texture)

                    self.frame_numbers[mat_slot][slot_type].current_number = frame_number + 1

                    if frame_number == max_frame_number and loop_list[mat_slot][slot_type] then
                        self.frame_numbers[mat_slot][slot_type].loops = self.frame_numbers[mat_slot][slot_type].loops + 1
                        local max_loops = self.num_of_loops[mat_slot][slot_type]
                        if max_loops < self.frame_numbers[mat_slot][slot_type].loops and max_loops ~= -1 then
                            self.loop_on_spawn[mat_slot][slot_type] = false
                        end
                    end

                    self.unit_time[mat_slot][slot_type] = 0
                end
                self.unit_time[mat_slot][slot_type] = self.unit_time[mat_slot][slot_type] + dt
            end
        end
    end
end

AnimTextureExtension.destroy = function (self)
    mod.texture_animations[self.unit] = nil
    self.unit = nil
    self.aniamted_channels = nil
    self.frame_delay = nil
    self.loop_on_spawn = nil
    self.num_of_loops = nil
    self.unit_time = nil
    self.unit_mat_dict = nil
    self.frame_numbers = nil
    self.texture_slot_names = nil
end
