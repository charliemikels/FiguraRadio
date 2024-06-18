-- Auto generated script file --

local all_radios = {}
local function pos_is_a_radio(pos)
    local pcall_status, function_return = pcall(function (pos)
        if client:intUUIDToString(table.unpack(world.getBlockState(pos):getEntityData()["SkullOwner"]["Id"])) == avatar:getUUID() then return true else return false end
    end, pos)
    return (pcall_status and function_return or false)
end

local world_remove_radio_loop_index = 1
local function world_remove_radios_loop()
    current_radio = all_radios[world_remove_radio_loop_index]
    
    if not pos_is_a_radio(current_radio.pos) then 
        print("lost radio at" .. tostring(current_radio.pos))
        table.remove(all_radios, world_remove_radio_loop_index)
    end

    world_remove_radio_loop_index = world_remove_radio_loop_index % #all_radios +1
end
events.WORLD_TICK:register(world_remove_radios_loop, "unregister_removed_radios")



local function pos_is_known_radio(pos) 
    -- TODO: This for loop is very taxing when lots of radios are placed, 
    -- especialy since we're making this check on every radio, every frame
    for _, radio in ipairs(all_radios) do 
        if radio.id == tostring(pos) then return true end
    end
    return false
end

local function add_radio(pos)
    table.insert(all_radios, #all_radios+1, {
        id = tostring(pos), 
        pos = pos
    })
end

local function skull_renderer_loop(_, block)
    if not block then return end
    if not pos_is_known_radio(block:getPos()) then 
        print("Found radio at "..tostring(block:getPos()))
        print(block)
        add_radio(block:getPos())
    end
    -- printTable(all_radios)
end

local mysound = sounds["Pink-Loop"]
local target_volume = 0.8

local function tick_loop()
    mysound:setPos(player:getPos())
    mysound:setVolume( math.lerp(mysound:getVolume(), target_volume, 0.1  ) )
end

local function entity_init()
    print("Entity init → "..client:getSystemTime())
    mysound
        :setPos(player:getPos())
        :setVolume(0)
        -- :loop(true)
        :play()
    events.TICK:register(tick_loop)
end

events.SKULL_RENDER:register(skull_renderer_loop, "skull_renderer_loop")
events.ENTITY_INIT:register(entity_init)