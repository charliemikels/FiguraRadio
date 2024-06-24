-- Auto generated script file --

local max_distance_from_radios = 16

local all_radios = {}
local brodcasts = {}
local function pos_is_a_radio(pos)
    local pcall_status, function_return = pcall(
        function (pos)
            if client:intUUIDToString(
                table.unpack(
                    world.getBlockState(pos):getEntityData()["SkullOwner"]["Id"]
                )   
            ) == avatar:getUUID() 
            then return true else return false end
        end,
        pos
    )

    return (pcall_status and function_return or false)
end

local function distancesquared(veca, vecb)
    return (vecb.x - veca.x)^2 + (vecb.y - veca.y)^2 + (vecb.z - veca.z)^2
end

local max_distance_from_radios_squared = max_distance_from_radios^2
local function radio_is_in_range(pos)
    if      client:getViewer():isLoaded() 
        and distancesquared(client:getViewer():getPos(), pos) < max_distance_from_radios_squared 
    then
        return true
    end
    return false
end


local function pos_is_known_radio(pos)
    if all_radios[tostring(pos)] then return true end
    return false
end

local function add_radio(pos)
    all_radios[tostring(pos)] = {
        pos = pos
    }
end

local function skull_renderer_loop(_, block)
    if not block then return end
    if not pos_is_known_radio(block:getPos()) and radio_is_in_range(block:getPos()) then 
        print("Found radio at "..tostring(block:getPos()))
        print(block)
        add_radio(block:getPos())
    end
    -- printTable(all_radios)
end

local mysound = sounds["Pink-Loop"]
local target_volume = 0.0

local function tick_loop()
    mysound:setPos(player:getPos())
    mysound:setVolume( math.lerp(mysound:getVolume(), target_volume, 0.1  ) )



end



local world_remove_radio_loop_next_key = nil
local function world_remove_radios_loop_step()
    local current_key = world_remove_radio_loop_next_key
    world_remove_radio_loop_next_key = next(all_radios, current_key)
    
    if current_key then 
        local current_radio = all_radios[current_key]
        if not (pos_is_a_radio(current_radio.pos) and radio_is_in_range(current_radio.pos)) then 
            print("lost radio at" .. tostring(current_radio.pos))
            all_radios[current_key] = nil
        end
    end
end

local function world_tick_loop()
    world_remove_radios_loop_step()

    -- get players interacting with radios
    for k, loopPlayer in pairs(world.getPlayers()) do
        if (loopPlayer:getSwingTime() == 1) then -- this player punched this tick
            local punchedBlock, _, _ = loopPlayer:getTargetedBlock()
            if pos_is_known_radio(punchedBlock:getPos()) then
                print("That's a radio")
            end
        end
    end
end
events.WORLD_TICK:register(world_tick_loop, "main_world_loop")


local function entity_init()
    print("Entity init → "..client:getSystemTime())
    mysound
        :setPos(player:getPos())
        :setPitch(1.25)
        :setVolume(0.1)
        :loop(true)
        :play()
    events.TICK:register(tick_loop)


    -- local tmp_ogg_as_string = file:readString("Radio/Local Forecast-16000-2x.ogg", "base64")
    -- sounds:newSound("tmp_ogg_from_string", tmp_ogg_as_string)

    local tmp_ogg_read_stream = file:openReadStream("Radio/Local Forecast-4000-Highpass.ogg")
    local tmp_ogg_read_stream_dump = {}
    local available = tmp_ogg_read_stream:available()
    for i=1,available do
        table.insert(tmp_ogg_read_stream_dump, tmp_ogg_read_stream:read())
    end
    print(available)
    print(#tmp_ogg_read_stream_dump)
    sounds:newSound("tmp_ogg_from_string", tmp_ogg_read_stream_dump)
    sounds["tmp_ogg_from_string"]:setPitch(1):volume(2):setPos(player:getPos()):loop(false):play()
end

events.SKULL_RENDER:register(skull_renderer_loop, "skull_renderer_loop")
events.ENTITY_INIT:register(entity_init)