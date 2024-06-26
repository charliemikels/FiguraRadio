
events.ENTITY_INIT:register(function() print("Entity init → "..client:getSystemTime()) end)

local radio_model = models["radio"]["Skull"]

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
local max_distance_from_radios = 16
local all_radios = {}
local radio_count = 0
local nearest_radio_key = nil

local radio_sound_pos_offset = vec(0.5,0.5,0.5)
local fac_to_end_of_brodcast = 1    -- internal. Used to animate out of brodcast. 

-- brodcasts
local brodcasts = {}
local current_brodcast_key = nil
local current_brodcast_sound = nil
local current_brodcast_done_at = nil

local received_brodcast_from_host = false

for _, sound_name in pairs(sounds:getCustomSounds()) do
    if string.match(sound_name, "Default_Brodcasts.") then
        
        local _, _, seconds = string.find(sound_name, "-(%d+)s$")

        if seconds then 
            local new_brodcast = {
                sound = sounds[sound_name]:setSubtitle("Radio Brodcast #"..tostring(#brodcasts +1)),
                is_local = true,
                durration = seconds*1000
            }
            table.insert(
                brodcasts, 
                math.random(1, #brodcasts+1), 
                new_brodcast
            )
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
        -- brodcast is done, but it was still non-nil. reset, and tell puncher it's ok to play next brodcast

        kill_brodcast()
        return true
    end

    return false
end

local last_brodcast_index = nil
local function get_next_brodcast() 
    local next_brodcast_index, next_brodcast = next(brodcasts, last_brodcast_index)
    
    if not next_brodcast_index then 
        -- last brodcast was the last brodcast in the list. reshuffle and start again.
        -- this process reduces the chance of playing the same brodcast 2+ times in a row. 

        local shuffled_brodcasts = {}
        for _, v in pairs(brodcasts) do
            table.insert(shuffled_brodcasts, math.random(1, #shuffled_brodcasts+1), v)
        end

        brodcasts = shuffled_brodcasts

        next_brodcast_index, next_brodcast = next(brodcasts, nil)
    end
    last_brodcast_index = next_brodcast_index
    return next_brodcast_index, next_brodcast
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
    local squish = current_radio.squish_scale
    current_radio.squish_scale = math.lerp(squish, 1, 0.2)
    
    local bounce = (
        current_brodcast_key 
        and math.lerp(
            (math.abs(math.sin(client:getSystemTime()/500)))/16 +1, 
            1, 
            fac_to_end_of_brodcast
        ) 
        or 1
    )
    local squash = (2+(squish*-1))

    radio_model:setScale(squash ,bounce* squish, squash)

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
    elseif block and client.getViewer():getTargetedBlock():getPos() == block:getPos() then 
        radio_model["PermissionRequestSign"]:setVisible(true)
    end
end

events.WORLD_TICK:register(wait_for_max_permission_then_init_world_loop, "wait_for_max_permission_then_init_world_loop")
events.SKULL_RENDER:register(render_request_permission_sign_loop, "render_request_permission_sign_loop")


-- ----------------------------------------------------------------------------------------------------------------- --


-- Pings
local max_packet_size = 750
-- local max_packet_rate = 1500
local max_packet_rate = 100  -- DEV
local last_packet_sent = client:getSystemTime()

local incomming_brodcasts = {}
local function ping_brodcast_data_to_client(brodcast_id, packet_number, total_packets_count, durration_in_s, data)
    if not incomming_brodcasts[brodcast_id] then 
        incomming_brodcasts[brodcast_id] = {}
        incomming_brodcasts[brodcast_id].total_packets_count = total_packets_count
        incomming_brodcasts[brodcast_id].packet_count = 0
        incomming_brodcasts[brodcast_id].durration_in_s = durration_in_s
        incomming_brodcasts[brodcast_id].packets = {}
        incomming_brodcasts[brodcast_id].done = false
    end

    if incomming_brodcasts[brodcast_id].done then return end 

    if not incomming_brodcasts[brodcast_id].packets[packet_number] then
        -- first time seeing this packet. 
        incomming_brodcasts[brodcast_id].packets[packet_number] = data
        incomming_brodcasts[brodcast_id].packet_count = incomming_brodcasts[brodcast_id].packet_count +1
    end

    if incomming_brodcasts[brodcast_id].packet_count == incomming_brodcasts[brodcast_id].total_packets_count then
        -- we have received all packets for this brodcast. 
        incomming_brodcasts[brodcast_id].done = true

        print("Brodcast #"..brodcast_id.." has been received")
        
        local full_data = {}

        for packet_index = 1, incomming_brodcasts[brodcast_id].total_packets_count do
            for _, data in ipairs(incomming_brodcasts[brodcast_id].packets[packet_index]) do
               table.insert(full_data, data)
            end
        end

        local brodcast_name_string = "remote_brodcast#"..tostring(brodcast_id).."-"..tostring(durration_in_s).."s"

        sounds:newSound(brodcast_name_string, full_data)

        local new_brodcast = {
            sound = sounds[brodcast_name_string]:setSubtitle("Radio Brodcast #"..tostring(#brodcasts +1)),
            is_local = false,
            durration = durration_in_s*1000
        }
        table.insert(
            brodcasts, 
            math.random((last_brodcast_index and last_brodcast_index or 1), #brodcasts+1),
            new_brodcast
        )

        incomming_brodcasts[brodcast_id].packets = nil
        if not received_brodcast_from_host and nearest_radio_key then 
            print("received first remote brodcast")
            -- TODO: make radio react to successfuly host → client brodcasts
        end
        received_brodcast_from_host = true
    end
end

-- function pings.ping_brodcast_data_to_client(brodcast_id, packet_number, total_packets_count, durration_in_s, data)
--     ping_brodcast_data_to_client(brodcast_id, packet_number, total_packets_count, durration_in_s, data)
-- end


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
                    data_packets = {}
                })
            end 
        end
    end

    if #host_brodcasts == 0 then 
        -- no brodcasts? don't bother continuing. 
        -- This skips setting up the host tick events. 
        return 
    end

    -- collect data from files. 
    for _, brodcast in ipairs(host_brodcasts) do 
        local brodcast_file_read_stream = file:openReadStream(brodcast.file_path)
        local available = brodcast_file_read_stream:available()
        for i = 1, available do
            -- table.insert(brodcast.data, data)
            packet_index = math.floor((i - (i %max_packet_size ))/max_packet_size)+1
            if not brodcast.data_packets[packet_index] then brodcast.data_packets[packet_index] = {} end
            table.insert(brodcast.data_packets[packet_index], brodcast_file_read_stream:read())
        end
        brodcast_file_read_stream:close()
    end

    -- file transfer
    -- "One goofy developer keeps sending packets without stopping! The backend hates him!"

    local current_sending_brodcast_index = next(host_brodcasts)
    local function get_next_packet_to_send()
        -- see if current brodcast still has packets. send the next one of those. 
        -- if not, get the next brodcast and send it's first packet. 
        -- if on last brodcast, shuffle list and send the new first brodcast. 

        -- only ask if there are brodcasts to send. 
        local packet_index, packet = next(host_brodcasts[current_sending_brodcast_index].data_packets, host_brodcasts[current_sending_brodcast_index].last_packet_index)

        if not packet_index then 
            -- we passed last packet. Reset and loop back arround. 
            host_brodcasts[current_sending_brodcast_index].last_packet_index = nil
            current_sending_brodcast_index = next(host_brodcasts, current_sending_brodcast_index)
            if not current_sending_brodcast_index then 
                -- end of list. rerun to get top of list. 
                current_sending_brodcast_index = next(host_brodcasts, nil) 
            end
            -- print("Switching to next brodcast.")
            return get_next_packet_to_send()
        end

        host_brodcasts[current_sending_brodcast_index].last_packet_index = packet_index

        return current_sending_brodcast_index, packet_index, #host_brodcasts[current_sending_brodcast_index].data_packets, host_brodcasts[current_sending_brodcast_index].durration, packet
    end

    local function send_data_to_clients_loop()
        -- print(get_next_packet_to_send())
        if client:getSystemTime() > last_packet_sent + max_packet_rate then
            last_packet_sent = client:getSystemTime()

            local brodcast_index, packet_index, packet_total, brodcast_durration, packet_data = get_next_packet_to_send()
            ping_brodcast_data_to_client(brodcast_index, packet_index, packet_total, brodcast_durration, packet_data)


            if pos_is_a_radio(player:getTargetedBlock():getPos()) then 
                host:actionbar("Brodcast #"..brodcast_index.." - Sending packet "..packet_index.." of "..packet_total)
            end
        end
    end
    events.TICK:register(send_data_to_clients_loop)


end
