
events.ENTITY_INIT:register(function() print("Entity init → "..client:getSystemTime()) end)

local radio_model = models["radio"]["Skull"]

local use_ping_file_transfer = true

-- functional sounds
local static_hiss_volume = 0.1
local static_hiss_volume_during_brodcats = 0.05
local static_hiss_punch_volume = 0.15

local static_hiss = sounds["Pink-Loop"]:setPitch(1.25):setVolume(0):loop(true)

local brodcast_target_volume = 1

local sound_radio_tuned_click_1 = sounds["block.note_block.hat"]:setPitch(1):setSubtitle("Radio Tuned")
local sound_radio_tuned_click_2 = sounds["block.note_block.cow_bell"]:setPitch(2.5):setVolume(0.25):setSubtitle("Radio Tuned")
local sound_radio_tune_attempt  = sounds["block.note_block.snare"]:setPitch(3):setSubtitle("Radio Clicks")

-- radio management
local block_reach = 4.5 -- how far away can the player be where punch triggers the radio reaction. 

local max_distance_from_radios = 16 -- how far away untill script stops thinking about them. 
local all_radios = {}
local radio_count = 0
local nearest_radio_key = nil

local radio_sound_pos_offset = vec(0.5,0.5,0.5)
local fac_to_end_of_brodcast = 1    -- internal. Used to animate out of brodcast. 

-- brodcasts
local brodcasts = {}
local current_brodcast_key = nil    -- TODO: rename or remove, this value is actualy only used to test if a brodcast is playing, and not actualy used to index. 
local current_brodcast_sound = nil
local current_brodcast_done_at = nil

local currently_playing_brodcasts = {   -- TODO: per-radio brodcasts
    -- radio pos
    -- brodcast_table_index
    -- sound_object_name
} 

local received_brodcast_from_host = false

local function sort_brodcasts_table()
    table.sort(brodcasts, function(a,b) 
        if a.is_local ~= b.is_local then return a.is_local end
        return a.sound_name < b.sound_name 
    end)
end


local function load_internal_brodcasts()
    for _, sound_name in pairs(sounds:getCustomSounds()) do
        if string.match(sound_name, "Default_Brodcasts.") then
            
            local _, _, seconds = string.find(sound_name, "-(%d+)s$")

            if seconds then 
                local new_brodcast = {
                    sound = sounds[sound_name]:setSubtitle("Radio Brodcast #"..tostring(#brodcasts +1)),
                    sound_name = sound_name,
                    is_local = true,
                    durration = seconds*1000
                }
                table.insert(
                    brodcasts, 
                    #brodcasts+1, --math.random(1, #brodcasts+1), 
                    new_brodcast
                )
            end
        end
    end
    sort_brodcasts_table()
end
load_internal_brodcasts()

-- -- syncronization
local function get_current_brodcast_seed_pre_floor()
    return world:getTime()/20
end

local function get_current_brodcast_seed()
    return math.floor(get_current_brodcast_seed_pre_floor())
    -- gets a new,fixed seed every second
end

local attempts_before_sync_window_opens = math.huge
local last_sync_seed = 0

local function syncronization_window_is_open()

    local current_seed = get_current_brodcast_seed()
    if current_seed ~= last_sync_seed then
        last_sync_seed = current_seed

        math.randomseed(current_seed)
        attempts_before_sync_window_opens = math.random(3)
        math.randomseed(get_current_brodcast_seed_pre_floor())
    else
        attempts_before_sync_window_opens = attempts_before_sync_window_opens -1
    end

    return attempts_before_sync_window_opens < 1
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

local function is_playing_brodcast()
    return current_brodcast_key ~= nil
end

local function can_play_brodcast()  -- TODO: rename to "radio is bussy(radio pos)" when we implement per-radio brodcasts
    if not is_playing_brodcast() then return true end

    if current_brodcast_done_at < client:getSystemTime() then
        -- brodcast is done, but it was still non-nil. reset, and tell puncher it's ok to play next brodcast

        kill_brodcast()
        return true
    end

    return false
end

-- local last_brodcast_index = nil
local recent_brodcasts = {}
local recent_brodcasts_table_last_checked = client.getSystemTime()
local function brodcast_was_recently_played(brodcast_name)
    if recent_brodcasts_table_last_checked + 60000 < client.getSystemTime() then recent_brodcasts = {} end

    recent_brodcasts_table_last_checked = client.getSystemTime()
    if #recent_brodcasts < 1 then return false end
    for _, recent_brodcast_names in ipairs(recent_brodcasts) do
        if recent_brodcast_names == brodcast_name then
            return true
        end
    end
    return false
end

local function get_next_brodcast() 
    math.randomseed(get_current_brodcast_seed())
    
    -- local next_brodcast_index = nil
    local next_brodcast = nil
    repeat
        -- next_brodcast_index = math.random(#brodcasts)
        next_brodcast = brodcasts[math.random(#brodcasts)]
    until (not brodcast_was_recently_played(next_brodcast.sound_name) and not next_brodcast.is_incomming)
    

    table.insert(recent_brodcasts, next_brodcast.sound_name)
    if #recent_brodcasts > 2 then 
        table.remove(recent_brodcasts, 1) 
    end

    return next_brodcast.sound_name, next_brodcast
end

local function play_a_brodcast()
    local _, selected_brodcast = get_next_brodcast()

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
    if      pcall(client.getViewer) and client:getViewer():isLoaded() 
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
        squish_scale = 1,
        current_knob_rotation_a = 180,
        current_knob_rotation_b = 180,
        current_knob_rotation_c = 180,
        current_knob_rotation_side = 180,
        current_tune_x_position = math.random()*-4.75,
        target_knob_rotation_a = 180,
        target_knob_rotation_b = 180,
        target_knob_rotation_c = 180,
        target_knob_rotation_side = 180,
        target_tune_x_position = math.random()*-4.75,
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
local punches_to_next_brodcast = 2
local last_tunning_position = 0
local function radio_react_to_punch(pos)
    local current_radio = all_radios[tostring(pos)]
    
    if not is_playing_brodcast() then
        current_radio.squish_scale = 0.2
        current_radio.target_knob_rotation_a = math.random(0, 3)*90
        current_radio.target_knob_rotation_b = math.random(0, 3)*90
        current_radio.target_knob_rotation_c = math.random(0, 3)*90
        current_radio.target_knob_rotation_side = math.random(0, 3)*90
        math.random(get_current_brodcast_seed())
        last_tunning_position = math.random()*-4.75
        math.random(get_current_brodcast_seed_pre_floor())
    else
        current_radio.squish_scale = 0.8
    end

    if pcall(client.getViewer) and client:getViewer() then 
        if  nearest_radio_key and all_radios[nearest_radio_key]
            and (  distancesquared(client:getViewer():getPos(), all_radios[nearest_radio_key].pos)
                > distancesquared(client:getViewer():getPos(), current_radio.pos) )
        then
            nearest_radio_key = tostring(current_radio.pos)
            reposition_sounds(current_radio.pos)
        end
    end

    local sound_pos = pos+radio_sound_pos_offset
    static_hiss:setVolume(static_hiss_punch_volume)

    if can_play_brodcast() then
        punches_to_next_brodcast = punches_to_next_brodcast -1
        if punches_to_next_brodcast < 1 and syncronization_window_is_open()
        then
            -- play next brodcast
            punches_to_next_brodcast = 2
            -- print("Playing brodcast")
            play_a_brodcast()

            sound_radio_tuned_click_1:setPos(sound_pos):stop():play()
            sound_radio_tuned_click_2:setPos(sound_pos):stop():play()
            particles:newParticle("note", current_radio.pos + vec(math.random()/2+0.25,0.5,math.random()/2+0.25), vec(0, 0.2, 0))
                :setColor(vectors.hsvToRGB(vec(math.random(), 0.8, 1)))
            particles:newParticle("note", current_radio.pos + vec(math.random()/2+0.25,0.75,math.random()/2+0.25), vec(0, 0.3, 0))
                :setColor(vectors.hsvToRGB(vec(math.random(), 0.8, 1)))
        else
            particles:newParticle("smoke", current_radio.pos + vec(math.random()/2+0.25,0.5,math.random()/2+0.25), vec(0, 0.1, 0))
            sound_radio_tune_attempt:setPitch(math.random()*2+2):setPos(sound_pos):stop():play()
            current_radio.target_tune_x_position = last_tunning_position
        end
    end
end


-- render loops
local function reset_skull() 
    radio_model:setScale(1,1,1)
    radio_model["Tune Marker"]:setPos(-1,0,0)
    radio_model["Knob A"]:setRot(0,0,0)
    radio_model["Knob A"]:setRot(0,0,0)
    radio_model["Knob C"]:setRot(0,0,0)
    radio_model["Knob Side"]:setRot(0,0,0)
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

    -- annimations 
    -- -- punch effects
    -- -- -- Tuning marker
    if is_playing_brodcast() then
        -- force all radios to match current tuning if playing a brodcast. 
        current_radio.target_tune_x_position = last_tunning_position
    end
    current_radio.current_tune_x_position = math.lerp(
        current_radio.current_tune_x_position,
        current_radio.target_tune_x_position,
        0.1
    )
    radio_model["Tune Marker"]:setPos( current_radio.current_tune_x_position ,0,0)
    
    -- -- -- knobs
    current_radio.current_knob_rotation_a = math.lerp(
        current_radio.current_knob_rotation_a,
        current_radio.target_knob_rotation_a,
        0.1
    )
    current_radio.current_knob_rotation_b = math.lerp(
        current_radio.current_knob_rotation_b,
        current_radio.target_knob_rotation_b,
        0.1
    )
    current_radio.current_knob_rotation_c = math.lerp(
        current_radio.current_knob_rotation_c,
        current_radio.target_knob_rotation_c,
        0.1
    )
    current_radio.current_knob_rotation_side = math.lerp(
        current_radio.current_knob_rotation_side,
        current_radio.target_knob_rotation_side,
        0.1
    )
    radio_model["Knob A"]:setRot(0,0,current_radio.current_knob_rotation_a)
    radio_model["Knob B"]:setRot(0,0,current_radio.current_knob_rotation_b)
    radio_model["Knob C"]:setRot(0,0,current_radio.current_knob_rotation_c)
    radio_model["Knob Side"]:setRot(current_radio.current_knob_rotation_side,0,0)

    -- -- -- Squish and Squash: applied with bounce at the bottom
    local squish = current_radio.squish_scale
    current_radio.squish_scale = math.lerp(squish, 1, 0.2)
    local squash = (2+(squish*-1))

    -- -- Animations while playing
    local pulse = math.abs(math.sin(client:getSystemTime()/400))
    local pulse_faster = math.abs(math.sin(client:getSystemTime()/200))

    -- -- -- Bounce
    local bounce = (
        current_brodcast_key 
        and math.lerp(
            (pulse)/16 +1.0125, 
            1, 
            fac_to_end_of_brodcast
        ) 
        or 1
    )
    radio_model:setScale(squash ,bounce* squish, squash)

    -- -- -- Speaker
    local speaker_push = math.lerp(math.lerp(0.9, 1,pulse_faster), 1, fac_to_end_of_brodcast)
    radio_model["Speaker"]:setScale(speaker_push, speaker_push, 1 )
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
    if pcall(client.getViewer) then 
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
            local punchedBlock, _, _ = loopPlayer:getTargetedBlock(true, block_reach)
            if pos_is_known_radio(punchedBlock:getPos()) then
                -- print("That's a radio")
                radio_react_to_punch(punchedBlock:getPos())
                table.insert(punchedRadios, punchedBlock:getPos())
            end
        end
    end
end

-- Skull initilization
local function wait_for_max_permission_then_init_world_loop() 
    if avatar:getPermissionLevel() == "MAX" then 
        -- we're at max perms, start initilization!
        events.WORLD_TICK:remove("wait_for_max_permission_then_init_world_loop")

        events.WORLD_TICK:register(world_tick_loop, "main_world_loop")
        events.SKULL_RENDER:register(skull_renderer_loop, "skull_renderer_loop")
    end
end

local function render_request_permission_sign_loop(_, block)
    radio_model["PermissionRequestSign"]:setVisible(false)
    if avatar:getPermissionLevel() == "MAX" then 
        -- events.SKULL_RENDER:remove("render_request_permission_sign_loop")
    elseif block and pcall(client.getViewer) and client.getViewer():getTargetedBlock(true, block_reach):getPos() == block:getPos() then 
        radio_model["PermissionRequestSign"]:setVisible(true)
    end
end

events.WORLD_TICK:register(wait_for_max_permission_then_init_world_loop, "wait_for_max_permission_then_init_world_loop")
events.SKULL_RENDER:register(render_request_permission_sign_loop, "render_request_permission_sign_loop")


-- ----------------------------------------------------------------------------------------------------------------- --


-- Pings
local max_packet_size = 500 -- note: if your song takes more than max_packet_size packets, 
                            -- then there will be a conversion error trying to assign a number > than 255 to the "total packets" count
local max_packet_rate = 1500
-- local max_packet_rate = 100  -- DEV. Disable pings when using this option. 
local last_packet_sent = client:getSystemTime()

local incomming_brodcasts = {}
local function ping_brodcast_data_to_client(byte_string_packet)
    if not byte_string_packet then return end

    local raw_packet_data_table = table.pack(string.byte(byte_string_packet, 1, -1))

    local brodcast_id = raw_packet_data_table[1]
    local packet_index = raw_packet_data_table[2]
    local total_packets_count = raw_packet_data_table[3]
    local durration_in_s = raw_packet_data_table[4]

    local brodcast_name_string = "remote_brodcast#"..tostring(brodcast_id).."-"..tostring(durration_in_s).."s"

    if not incomming_brodcasts[brodcast_id] then 
        -- first time seeing this brodcast
        incomming_brodcasts[brodcast_id] = {}
        incomming_brodcasts[brodcast_id].total_packets_count = total_packets_count
        incomming_brodcasts[brodcast_id].packet_count = 0
        incomming_brodcasts[brodcast_id].durration_in_s = durration_in_s
        incomming_brodcasts[brodcast_id].packet_data = {}
        incomming_brodcasts[brodcast_id].done = false

        table.insert(brodcasts, #brodcasts +1, {
            sound_name = brodcast_name_string,
            is_local = false,
            durration = durration_in_s*1000,
            is_incomming = true
        })
        sort_brodcasts_table()
    end

    if incomming_brodcasts[brodcast_id].done then return end 

    local ogg_data_part = {table.unpack(raw_packet_data_table, 5, #raw_packet_data_table)}

    if not incomming_brodcasts[brodcast_id].packet_data[packet_index] then
        -- first time seeing this packet. 
        incomming_brodcasts[brodcast_id].packet_data[packet_index] = ogg_data_part
        incomming_brodcasts[brodcast_id].packet_count = incomming_brodcasts[brodcast_id].packet_count +1
    end

    if incomming_brodcasts[brodcast_id].packet_count == incomming_brodcasts[brodcast_id].total_packets_count then
        -- we have received all packets for this brodcast. 
        incomming_brodcasts[brodcast_id].done = true

        -- print("Brodcast #"..brodcast_id.." has been received")
        
        local full_data = {}
        for packet_i = 1, incomming_brodcasts[brodcast_id].total_packets_count do
            for _, byte in ipairs(incomming_brodcasts[brodcast_id].packet_data[packet_i]) do
               table.insert(full_data, byte)
            end
        end

        sounds:newSound(brodcast_name_string, full_data)

        -- processing is done. find and update the placeholder brodcast
        for _, search_brodcast in ipairs(brodcasts) do
            if search_brodcast.sound_name == brodcast_name_string then
                search_brodcast.sound = sounds[brodcast_name_string]:setSubtitle("Radio Brodcast #"..tostring(brodcast_id))
                search_brodcast.is_incomming = nil
                break
            end 
        end

        incomming_brodcasts[brodcast_id].packets = nil

        if not received_brodcast_from_host and nearest_radio_key then 
            if not host:isHost() then print("Received a remote brodcast") end
            -- TODO: make radio react to successfuly host → client brodcasts
            -- ie a light goes from red to green or something. 
        end
        received_brodcast_from_host = true
    end
end

function pings.ping_brodcast_data_to_client(byte_string_packet)
    ping_brodcast_data_to_client(byte_string_packet)
end


-- Host only
local host_brodcast_files_root = "Additional_Radio_Brodcasts/"
if host:isHost() then 

    if avatar:getPermissionLevel() ~= "MAX" then 
        print("Set yourself to max permissions and reload your avatar plz. :)")
        return
    end

    local host_brodcasts = {}

    -- find adtional brodcasts
    if not file:allowed() then
        return
    elseif not file:exists(host_brodcast_files_root) then 
        file:mkdir(host_brodcast_files_root) 
        print("Created folder for aditional radio brodcasts.")
    else
        for _, filename in pairs(file:list(host_brodcast_files_root)) do
            local _, _, seconds = string.find(filename, "-(%d+)s%.ogg$")
            if seconds then 
                table.insert(host_brodcasts, math.random(1, #host_brodcasts+1), {
                    file_path = host_brodcast_files_root..filename,
                    durration = seconds,
                    -- data = {},
                    data_packets = {},
                    data_packets_tables = {}
                })
            end 
        end
        table.sort(host_brodcasts, function(a,b) 
            return a.file_path < b.file_path
        end)
    end

    if #host_brodcasts == 0 then 
        -- no brodcasts? don't bother continuing. 
        -- This skips setting up the host tick events. 
        return 
    end

    -- file transfer
    -- "The backend hates this one simple trick!"

    local current_sending_brodcast_index = next(host_brodcasts)
    local function get_next_packet_to_send()
        -- see if current brodcast still has packets. send the next one of those. 
        -- if not, get the next brodcast and send it's first packet. 
        -- if on last brodcast, shuffle list and send the new first brodcast. 

        -- only ask if there are brodcasts to send. 
        local packet_index, packet = next(host_brodcasts[current_sending_brodcast_index].data_packets, host_brodcasts[current_sending_brodcast_index].last_packet_index)

        if not packet_index then 
            -- we passed last packet. Reset and move to next brodcast. 
            host_brodcasts[current_sending_brodcast_index].last_packet_index = nil
            current_sending_brodcast_index = next(host_brodcasts, current_sending_brodcast_index)
            if not current_sending_brodcast_index then 
                -- end of list of brodcasts. run again to get the top of the brodcasts list. 
                current_sending_brodcast_index = next(host_brodcasts, nil) 
            end
            -- print("Switching to next brodcast.")
            return get_next_packet_to_send()
        end

        host_brodcasts[current_sending_brodcast_index].last_packet_index = packet_index

        return packet, host_brodcasts[current_sending_brodcast_index].data_packets_tables[packet_index]
    end

    local function send_data_to_clients_loop()
        -- print(get_next_packet_to_send())
        if client:getSystemTime() > last_packet_sent + max_packet_rate then
            last_packet_sent = client:getSystemTime()

            local packet_byte_string, packet_byte_table = get_next_packet_to_send()
            -- printTable(packet_byte_string)

            if use_ping_file_transfer then 
                pings.ping_brodcast_data_to_client(packet_byte_string)
            else
                ping_brodcast_data_to_client(packet_byte_string)
            end

            -- byte_str → table test. effects actionbar
            -- packet_byte_table = table.pack(string.byte(packet_byte_string, 1, -1))

            if pos_is_a_radio(player:getTargetedBlock(true, block_reach):getPos()) then 
                host:actionbar("Brodcast #"..packet_byte_table[1].." - Sending packet "..packet_byte_table[2].." of "..packet_byte_table[3])
            end
        end
    end

    local last_processed_host_brodcast_index = nil
    local function process_next_host_brodcast()
        local current_host_brodcast_key, current_host_brodcast = next(host_brodcasts, last_processed_host_brodcast_index)
        last_processed_host_brodcast_index = current_host_brodcast_key

        if not current_host_brodcast_key then
            events.WORLD_RENDER:remove("one-at-a-time_host_brodcast_processor_loop")
            events.TICK:register(send_data_to_clients_loop)
            return
        end

        local brodcast_file_read_stream = file:openReadStream(current_host_brodcast.file_path)
        local available = brodcast_file_read_stream:available()
        local total_packets = math.floor((available - (available %max_packet_size ))/max_packet_size)
        local packet_builder = {}
        table.insert(packet_builder, tonumber(current_host_brodcast_key))
        table.insert(packet_builder, tonumber(1))
        table.insert(packet_builder, tonumber(total_packets))
        table.insert(packet_builder, tonumber(current_host_brodcast.durration))
        
        local last_packet_index = 1
        for i = 1, available do
            -- table.insert(current_host_brodcast.data, data)
            local packet_index = math.floor((i - (i %max_packet_size ))/max_packet_size)+1
            if packet_index > last_packet_index then 
                -- print("time to make a new packet")

                table.insert(current_host_brodcast.data_packets_tables, packet_builder)
                table.insert(current_host_brodcast.data_packets, string.char(table.unpack(packet_builder)))
                
                last_packet_index = packet_index

                packet_builder = {}
                table.insert(packet_builder, tonumber(current_host_brodcast_key))
                table.insert(packet_builder, tonumber(packet_index))
                table.insert(packet_builder, tonumber(total_packets))
                table.insert(packet_builder, tonumber(current_host_brodcast.durration))
            end
            -- print("byte")
            table.insert(packet_builder, brodcast_file_read_stream:read())
        end
        brodcast_file_read_stream:close()
    end

    -- Tick allways goes in order, even if they take longer than 1/20 of a second, which can bring the game to a halt. 
    -- world_render firers whenever it happens to be ready. 
    -- usefull to prevent total freezes while processing many large files. 
    events.WORLD_RENDER:register(process_next_host_brodcast, "one-at-a-time_host_brodcast_processor_loop")
end
