local radio_model = models["radio"]["Skull"]

-- functional sounds
local static_hiss_volume = 0.03
local static_hiss_volume_during_brodcats = 0.005
local static_hiss_punch_volume = 0.1

local static_hiss = sounds["Pink-Loop"]:setPitch(1.25):setVolume(static_hiss_volume):loop(true)

local brodcast_target_volume = 2

local sound_radio_tuned_click_1 = sounds["block.note_block.hat"]:setPitch(1):setSubtitle("Radio Tuned")
local sound_radio_tuned_click_2 = sounds["block.note_block.cow_bell"]:setPitch(2.5):setVolume(0.25):setSubtitle("Radio Tuned")
local sound_radio_tune_attempt  = sounds["block.note_block.snare"]:setPitch(3):setSubtitle("Radio Clicks")


-- radio management
local max_distance_from_radios = 16
local all_radios = {}
local radio_count = 0
local nearest_radio_key = nil

local radio_sound_pos_offset = vec(0.5,0.5,0.5)

-- brodcasts
local brodcasts = {}
local current_brodcast_key = nil
local current_brodcast_sound = nil
local current_brodcast_done_at = nil

local fac_to_end_of_brodcast = 1

-- local recent_brodcasts = {}

for _, sound_name in pairs(sounds:getCustomSounds()) do
    if string.match(sound_name, "Default_Brodcasts.") then
        
        local _, _, seconds = string.find(sound_name, "-(%d+)s$")

        if seconds then 
            local new_brodcast = {
                sound = sounds[sound_name]:setSubtitle("Radio Brodcast #"..tostring(#brodcasts +1)),
                is_local = true,
                durration = seconds*1000
            }
            table.insert(brodcasts, new_brodcast)
        end
    end
end

-- sound management
local function reposition_sounds(radio_pos)
    local sound_pos = radio_pos + radio_sound_pos_offset
    static_hiss:setPos(sound_pos)
    if current_brodcast_sound then current_brodcast_sound:setPos(sound_pos) end
end

local function kill_brodcast()
    current_brodcast_sound:setVolume(0):stop()
    current_brodcast_key = nil
    current_brodcast_sound = nil
    current_brodcast_done_at = nil
    fac_to_end_of_brodcast = 1
end

local function can_play_brodcast()
    if not current_brodcast_sound then return true end

    if current_brodcast_done_at < client:getSystemTime() then
        -- brodcast is done, but it was still non-nill. reset, and tell puncher it's ok to play next brodcast

        kill_brodcast()
        return true
    end

    return false
end

local function play_a_brodcast()
    -- TODO: avoid repeating a recent brodcast. (namely, never play the most recently played brodcast, and avoid playing the 3 most recent.)
    local selected_brodcast = brodcasts[math.random(#brodcasts)]

    selected_brodcast.sound:setVolume(0):setPos( all_radios[nearest_radio_key].pos + radio_sound_pos_offset )
    current_brodcast_key = selected_brodcast
    current_brodcast_sound = selected_brodcast.sound
    current_brodcast_done_at = selected_brodcast.durration + client:getSystemTime()

    current_brodcast_sound:play()
    fac_to_end_of_brodcast = 0
end


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
    radio_count = radio_count +1
    if nearest_radio_key == nil then
        nearest_radio_key = tostring(pos)
        reposition_sounds(pos)
        static_hiss:play()
    end
end

local function unknow_radio(pos)
    all_radios[tostring(pos)] = nil
    radio_count = radio_count -1
end



-- interaction management
local punches_to_next_brodcast = math.random(15)
local function radio_react_to_punch(pos)
    local current_radio = all_radios[tostring(pos)]
    
    current_radio.squish_scale = 0.2

    particles:newParticle("smoke", current_radio.pos + vec(math.random()/2+0.25,0.5,math.random()/2+0.25), vec(0, 0.1, 0))

    if client:getViewer() then 
        if  not nearest_radio_key or not all_radios[nearest_radio_key]
            or    distancesquared(client:getViewer():getPos(), all_radios[nearest_radio_key].pos) 
                > distancesquared(client:getViewer():getPos(), current_radio.pos) 
        then
            nearest_radio_key = current_key
            reposition_sounds(current_radio.pos)
        end
    end

    local sound_pos = pos+radio_sound_pos_offset
    static_hiss:setVolume(static_hiss_punch_volume)

    if can_play_brodcast() then
        punches_to_next_brodcast = punches_to_next_brodcast -1
        if punches_to_next_brodcast < 1 then
            -- play next brodcast
            punches_to_next_brodcast = math.random(5, 15)
            -- print("Playing brodcast")
            play_a_brodcast()
            sound_radio_tuned_click_1:setPos(sound_pos):stop():play()
            sound_radio_tuned_click_2:setPos(sound_pos):stop():play()
        else
            sound_radio_tune_attempt:setPitch(math.random()*2+2):setPos(sound_pos):stop():play()
        end
    end
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
        -- print("Found radio at "..tostring(block:getPos()))
        -- print(block)
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
    -- but this may be because the list is empty. if it is, make sure to reset sound positions. 
    if not current_key then 
        if radio_count == 0 then
            nearest_radio_key = nil
            reposition_sounds(vec(0, -255, 0))
        end
        
        return 
    end
    local current_radio = all_radios[current_key]
    
    -- remove distant radios and radios that have been broken
    if not (pos_is_a_radio(current_radio.pos) and radio_is_in_range(current_radio.pos)) then 
        -- print("lost radio at" .. tostring(current_radio.pos))
        unknow_radio(current_key)
    end

    -- test nearest radio, if viewer is arround. 
    if client:getViewer() then 
        if  not nearest_radio_key or not all_radios[nearest_radio_key]
            or    distancesquared(client:getViewer():getPos(), all_radios[nearest_radio_key].pos) 
                > distancesquared(client:getViewer():getPos(), current_radio.pos) 
        then
            nearest_radio_key = current_key
            -- print("new nearest radio")
            particles:newParticle("smoke", current_radio.pos + radio_sound_pos_offset, vec(0, 0, 0))
            reposition_sounds(current_radio.pos)
        end
    end
end

local function world_tick_loop()
    -- check next radio and clean up radio list if any are missing. 
    world_radio_checkup_loop()

    -- animate sound volumes
    if current_brodcast_sound then
        if current_brodcast_done_at < client:getSystemTime() 
        then 
            kill_brodcast() 
        else
            local remaining_durration = current_brodcast_done_at - client:getSystemTime()

            local fadeout_time = 2 *1000
            fac_to_end_of_brodcast = (math.min((remaining_durration), fadeout_time) /fadeout_time) *-1 +1

            current_brodcast_sound:setVolume( 
                math.lerp(
                    math.lerp(
                        current_brodcast_sound:getVolume(), 
                        brodcast_target_volume, 
                        0.1 -- lets sound ramp up
                        ),
                    0,  
                    fac_to_end_of_brodcast  -- forces brodcast to 0 at the end
                ) 
            )

            print(fac_to_end_of_brodcast)

            static_hiss:setVolume( 
                math.lerp(static_hiss:getVolume(), 
                    math.lerp( 
                        static_hiss_volume_during_brodcats,
                        static_hiss_volume, 
                        fac_to_end_of_brodcast  -- inverted, because it's ok if the noise slides arround a bit more. It's animated on every tick anywhays.
                    ),
                    0.2
                )
            )
        end
    else
        static_hiss:setVolume( math.lerp(static_hiss:getVolume(), static_hiss_volume, 0.1  ) )
    end

    -- get players interacting with radios
    local punchedRadios = {}
    for k, loopPlayer in pairs(world.getPlayers()) do
        if (loopPlayer:getSwingTime() == 1) then -- this player punched this tick
            local punchedBlock, _, _ = loopPlayer:getTargetedBlock()
            if pos_is_known_radio(punchedBlock:getPos()) then
                -- print("That's a radio")
                radio_react_to_punch(punchedBlock:getPos())
                table.insert(punchedRadios, punchedBlock:getPos())
            end
        end
    end
end
events.WORLD_TICK:register(world_tick_loop, "main_world_loop")


local function entity_init()
    print("Entity init → "..client:getSystemTime())
end

events.SKULL_RENDER:register(skull_renderer_loop, "skull_renderer_loop")
events.ENTITY_INIT:register(entity_init)



-- local function tmp_read_file_from_data_dir(path)
--     path = "Radio/Local Forecast-4000-Highpass.ogg"

--     local tmp_ogg_read_stream = file:openReadStream(path)
--     local tmp_ogg_read_stream_dump = {}
--     local available = tmp_ogg_read_stream:available()
--     for i=1,available do
--         table.insert(tmp_ogg_read_stream_dump, tmp_ogg_read_stream:read())
--     end
--     print(available)
--     print(#tmp_ogg_read_stream_dump)
--     sounds:newSound("tmp_ogg_from_string", tmp_ogg_read_stream_dump)
--     sounds["tmp_ogg_from_string"]:setPitch(1):volume(2):setPos(player:getPos()):loop(false):play()
-- end