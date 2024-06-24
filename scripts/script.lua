-- Auto generated script file --

local radio_model = models["radio"]["Skull"]

local max_distance_from_radios = 16

local static_hiss = sounds["Pink-Loop"]
local static_hiss_volume = 0.01
local static_hiss_punch_volume = 0.2

local all_radios = {}
local nearest_radio = nil

local brodcasts = {}
local current_brodcast = nil

-- Radio blocks management
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
        pos = pos,
        squish_scale = 1
    }
end

-- sound management
local function reposition_sounds(pos)
    static_hiss:setPos(pos)
end

-- interaction management
local function radio_react_to_punch(pos)
    local current_radio = all_radios[tostring(pos)]
    current_radio.squish_scale = 0.2
    static_hiss:setVolume(static_hiss_punch_volume)
end


-- render loops
local function reset_skull() 
    radio_model:setScale(1,1,1)
end


local function skull_renderer_loop(_, block)
    reset_skull()
    if not block then return end

    -- test if new radio
    if not pos_is_known_radio(block:getPos()) and radio_is_in_range(block:getPos()) then 
        print("Found radio at "..tostring(block:getPos()))
        print(block)
        add_radio(block:getPos())
    end

    local current_radio = all_radios[tostring(block:getPos())]
    if not current_radio then 
        -- looks like the radio isn't allways created in time (??). 
        -- It should clear up eventualy, but lets skip for now
        return 
    end

    -- animate punch squish effect
    local squash = (2+(current_radio.squish_scale*-1))

    radio_model:setScale(squash ,current_radio.squish_scale, squash)
    current_radio.squish_scale = math.lerp(current_radio.squish_scale, 1, 0.2)
    -- print(radio_model)
end


-- world tick loop
local world_remove_radio_loop_next_key = nil
local function world_radio_checkup_loop()
    -- this function checks 1 radio per run. so with many radios, it may be slow to detect changes. 
    -- but at many radios, will only use a few instructions. 
    local current_key = world_remove_radio_loop_next_key
    world_remove_radio_loop_next_key = next(all_radios, current_key)
    
    -- when looping back to the top of the list, this will be nil. 
    -- this will be resolved by `next()` on next run, so just return early. 
    if not current_key then return end
    local current_radio = all_radios[current_key]
    
    -- remove distant radios and radios that have been broken
    if not (pos_is_a_radio(current_radio.pos) and radio_is_in_range(current_radio.pos)) then 
        print("lost radio at" .. tostring(current_radio.pos))
        all_radios[current_key] = nil
    end

    -- test nearest radio, if viewer is arround. 
    if client:getViewer() then 
        if  not nearest_radio or not all_radios[nearest_radio]
            or    distancesquared(client:getViewer():getPos(), all_radios[nearest_radio].pos) 
                > distancesquared(client:getViewer():getPos(), current_radio.pos) 
        then
            nearest_radio = current_key
            -- print("new nearest radio")
            particles:newParticle("smoke", current_radio.pos + vec(0.5,0.5,0.5), vec(0, 0, 0))
            reposition_sounds(current_radio.pos + vec(0.5,0.5,0.5))
        end
    end
end

local function world_tick_loop()
    -- check next radio and clean up radio list if any are missing. 
    world_radio_checkup_loop()

    -- animate static hiss volume
    static_hiss:setVolume( math.lerp(static_hiss:getVolume(), static_hiss_volume, 0.1  ) )

    -- get players interacting with radios
    local punchedRadios = {}
    for k, loopPlayer in pairs(world.getPlayers()) do
        if (loopPlayer:getSwingTime() == 1) then -- this player punched this tick
            local punchedBlock, _, _ = loopPlayer:getTargetedBlock()
            if pos_is_known_radio(punchedBlock:getPos()) then
                print("That's a radio")
                radio_react_to_punch(punchedBlock:getPos())
                table.insert(punchedRadios, punchedBlock:getPos())
            end
        end
    end

    -- someone punched a radio, try to play a brodcast. 
    -- if #punchedRadios >= 1 then
    --     for i, radioPos in ipairs(punchedRadios) do
    --         print(radioPos)
            
    --     end
    -- end
end
events.WORLD_TICK:register(world_tick_loop, "main_world_loop")




local function entity_init()
    print("Entity init → "..client:getSystemTime())
    static_hiss
        :setPos(player:getPos())
        :setPitch(1.25)
        :setVolume(static_hiss_punch_volume)
        :loop(true)
        :play()
    -- events.TICK:register(tick_loop)


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