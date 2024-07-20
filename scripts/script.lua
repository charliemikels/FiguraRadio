-- debug
events.ENTITY_INIT:register(function() print("Entity init → " .. client:getSystemTime()) end)

-- meta
local radio_model                          = models["radio"]["Skull"]

-- remote broadcasts
local enable_remote_broadcasts             = true
local use_ping_file_transfer               = true
local use_fast_packets_when_pings_disabled = true
local host_broadcast_files_root            = "Additional_Radio_Broadcasts/"

-- sound configuration
local static_hiss_volume                   = 0.15
local static_hiss_volume_during_brodcats   = 0.05
local static_hiss_punch_volume             = 0.2

local broadcast_target_volume              = 1

local static_hiss                          = sounds["Pink-Loop"]:setPitch(1.25):setVolume(0):loop(true):setPos(0, -255, 0)

local sound_radio_tuned_click_1            = sounds["block.note_block.hat"]:setPitch(1):setSubtitle("Radio Tuned")
local sound_radio_tuned_click_2            = sounds["block.note_block.cow_bell"]:setPitch(2.5):setVolume(0.25)
    :setSubtitle("Radio Tuned")
local sound_radio_tune_attempt             = sounds["block.note_block.snare"]:setPitch(3):setSubtitle("Radio Clicks")

-- radio management
local block_reach                          = 4.5 -- how far away can the player be where punch triggers the radio reaction.

local max_distance_from_radios             = 16  -- how far away untill script stops thinking about them.
local all_radios                           = {}
local radio_count                          = 0
local nearest_radio_key                    = nil

local radio_sound_pos_offset               = vec(0.5, 0.5, 0.5)

-- broadcasts
local broadcasts                           = {}
local currently_playing_broadcasts         = {}

local received_broadcast_from_host         = false

-- broadcasts initilization and management
local function sort_broadcasts_table()
    table.sort(broadcasts, function(a, b)
        if a.is_local ~= b.is_local then return a.is_local end
        return a.sound_name < b.sound_name
    end)
end

local function load_internal_broadcasts()
    for _, sound_name in pairs(sounds:getCustomSounds()) do
        if string.match(sound_name, "Default_Broadcasts.") then
            local _, _, seconds = string.find(sound_name, "-(%d+)s$")

            if seconds then
                local new_broadcast = {
                    -- sound = sounds[sound_name]:setSubtitle("Radio Broadcast #"..tostring(#broadcasts +1)),
                    sound_name = sound_name,
                    is_local = true,
                    durration = seconds * 1000
                }
                table.insert(
                    broadcasts,
                    #broadcasts + 1, --math.random(1, #broadcasts+1),
                    new_broadcast
                )
            end
        end
    end
    sort_broadcasts_table()
end
load_internal_broadcasts()


-- -- syncronization
local function get_current_broadcast_seed_pre_floor()
    return world.getTime() / 20
end

local function get_current_broadcast_seed()
    return math.floor(get_current_broadcast_seed_pre_floor())
    -- gets a new,fixed seed every second
end

local attempts_before_sync_window_opens = math.huge
local last_sync_seed = 0

local function syncronization_window_is_open()
    local current_seed = get_current_broadcast_seed()
    if current_seed ~= last_sync_seed then
        last_sync_seed = current_seed

        math.randomseed(current_seed)
        attempts_before_sync_window_opens = math.random(3)
        math.randomseed(get_current_broadcast_seed_pre_floor())
    else
        attempts_before_sync_window_opens = attempts_before_sync_window_opens - 1
    end

    return attempts_before_sync_window_opens < 1
end


-- sound management
local function get_playing_broadcast(pos)
    return currently_playing_broadcasts[tostring(pos)], tostring(pos)
end

local function kill_broadcast(pos)
    local current_broadcast, current_broadcast_index = get_playing_broadcast(pos)
    current_broadcast.sound:setVolume(0):stop()
    currently_playing_broadcasts[current_broadcast_index] = nil
    return
end

local function can_play_broadcast(pos) -- TODO: rename to "radio is bussy(radio pos)" when we implement per-radio broadcasts
    local current_broadcast_at_pos = get_playing_broadcast(pos)

    if not current_broadcast_at_pos then return true end

    if current_broadcast_at_pos.done_at < client:getSystemTime() then
        -- broadcast is done, but it was still non-nil. reset, and tell puncher it's ok to play next broadcast

        kill_broadcast(pos)
        return true
    end

    return false
end

-- local last_broadcast_index = nil
local recent_broadcasts = {}
local recent_broadcasts_table_last_checked = client.getSystemTime()
local function broadcast_was_recently_played(broadcast_name)
    if recent_broadcasts_table_last_checked + 60000 < client.getSystemTime() then recent_broadcasts = {} end

    recent_broadcasts_table_last_checked = client.getSystemTime()
    if #recent_broadcasts < 1 then return false end
    for _, recent_broadcast_names in ipairs(recent_broadcasts) do
        if recent_broadcast_names == broadcast_name then
            return true
        end
    end
    return false
end

local function get_next_broadcast()
    math.randomseed(get_current_broadcast_seed())

    -- local next_broadcast_index = nil
    local next_broadcast = nil
    repeat
        -- next_broadcast_index = math.random(#broadcasts)
        next_broadcast = broadcasts[math.random(#broadcasts)]
    until (not broadcast_was_recently_played(next_broadcast.sound_name) and not next_broadcast.is_incomming)


    table.insert(recent_broadcasts, next_broadcast.sound_name)
    if #recent_broadcasts > 2 then
        table.remove(recent_broadcasts, 1)
    end

    return next_broadcast.sound_name, next_broadcast
end

local function play_a_broadcast(pos)
    local _, selected_broadcast = get_next_broadcast()

    local new_playing_broadcast = {
        radio_pos = pos,
        broadcast = selected_broadcast,
        sound = sounds[selected_broadcast.sound_name]
            :setSubtitle("Radio Plays")
            :setVolume(0)
            :setPos(pos + radio_sound_pos_offset),
        sound_name = selected_broadcast.sound_name,
        started_at = client:getSystemTime(),
        done_at = selected_broadcast.durration + client:getSystemTime(),

        get_progress_factor = function(__self)
            -- gets the factor value used in letp fns to fade in and out features at the starts and end of this broadcast.
            local broadcast_start_time = __self.started_at
            local broadcast_fade_up_end = broadcast_start_time + 1000
            local broadcast_fade_down_start = broadcast_start_time + selected_broadcast.durration - 2000
            local broadcast_done_time = __self.done_at

            local current_time = client:getSystemTime()

            local fade_in_fac = 0
            local fade_out_fac = 1
            local both = nil

            if current_time <= broadcast_start_time then
                both = 0
            elseif current_time <= broadcast_fade_up_end then
                fade_in_fac = (current_time - broadcast_start_time) / (broadcast_fade_up_end - broadcast_start_time)
                both = fade_in_fac
            elseif current_time <= broadcast_fade_down_start then
                both = 1
                fade_in_fac = 1
            elseif current_time <= broadcast_done_time then
                fade_in_fac = 1
                fade_out_fac = (current_time - broadcast_done_time) / (broadcast_fade_down_start - broadcast_done_time)
                both = fade_out_fac
            else
                fade_in_fac = 1
                fade_out_fac = 0
                both = 0
            end

            return both, fade_in_fac, fade_out_fac
        end
    }

    currently_playing_broadcasts[tostring(pos)] = new_playing_broadcast
    currently_playing_broadcasts[tostring(pos)].sound:play()

    return new_playing_broadcast, selected_broadcast.sound_name
end

-- Radio blocks management
local function pos_is_a_radio(pos)
    local pcall_status, function_return = pcall(
        function(pos)
            if client:intUUIDToString(
                    table.unpack(
                        world.getBlockState(pos):getEntityData()["SkullOwner"]["Id"]
                    )
                ) == avatar:getUUID()
            then
                return true
            else
                return false
            end
        end,
        pos
    )

    return (pcall_status and function_return or false)
end

local function distancesquared(veca, vecb)
    return (vecb.x - veca.x) ^ 2 + (vecb.y - veca.y) ^ 2 + (vecb.z - veca.z) ^ 2
end

local max_distance_from_radios_squared = max_distance_from_radios ^ 2
local function radio_is_in_range(pos)
    if pcall(client.getViewer) and client:getViewer():isLoaded()
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
    if not radio_is_in_range(pos) then return end
    all_radios[tostring(pos)] = {
        pos = pos,
        squish_scale = 1,
        current_knob_rotation_a = 180,
        current_knob_rotation_b = 180,
        current_knob_rotation_c = 180,
        current_knob_rotation_side = 180,
        current_tune_x_position = math.random() * -4.75,
        target_knob_rotation_a = 180,
        target_knob_rotation_b = 180,
        target_knob_rotation_c = 180,
        target_knob_rotation_side = 180,
        target_tune_x_position = math.random() * -4.75,
    }
    radio_count = radio_count + 1
    if nearest_radio_key == nil then
        nearest_radio_key = tostring(pos)
        static_hiss:setPos(pos+radio_sound_pos_offset)  -- Figura 0.1.5 RC 1: Static never starts even though it looks like it should be playing.
                                                        -- But for some reason setting the position immediatly when the first radio is
                                                        -- found (and before calling :play()) causes it to correctly play.
                                                        -- Perhaps this is a reportable bug in Figura 0.1.5.
                                                        -- TODO: Test starting sounds in odd locations at 0 volume, play the sound, then on next tick,
                                                        --       set it's position back to within hearing distance.
        static_hiss:play()
    end
end

local function unknow_radio(pos)
    all_radios[tostring(pos)] = nil
    radio_count = radio_count - 1
    if not all_radios[nearest_radio_key] then
        -- we removed the nearest radio.
        -- Grab a random radio and let the world checkup loop take care of it.
        if radio_count == 0 then
            nearest_radio_key = nil
        else
            nearest_radio_key = next(all_radios)
        end
    end
    if get_playing_broadcast(pos) then kill_broadcast(pos) end
end


-- interaction management
local last_tunning_position = 0
local function radio_react_to_punch(pos)
    local current_radio = all_radios[tostring(pos)]

    if not get_playing_broadcast(pos) then
        math.random(get_current_broadcast_seed_pre_floor())
        current_radio.squish_scale = 0.2
        current_radio.target_knob_rotation_a = math.random(0, 3) * 90
        current_radio.target_knob_rotation_b = math.random(0, 3) * 90
        current_radio.target_knob_rotation_c = math.random(0, 3) * 90
        current_radio.target_knob_rotation_side = math.random(0, 3) * 90
        current_radio.target_tune_x_position = math.random() * -4.75
    else
        current_radio.squish_scale = 0.8
    end

    if pcall(client.getViewer) and client:getViewer() then
        if nearest_radio_key and all_radios[nearest_radio_key]
            and (distancesquared(client:getViewer():getPos(), all_radios[nearest_radio_key].pos + radio_sound_pos_offset)
                > distancesquared(client:getViewer():getPos(), current_radio.pos + radio_sound_pos_offset))
        then
            nearest_radio_key = tostring(current_radio.pos)
        end
    end

    if all_radios[nearest_radio_key] and all_radios[nearest_radio_key].pos == pos then
        static_hiss:setVolume(static_hiss_punch_volume)
    end

    local sound_pos = pos + radio_sound_pos_offset

    if can_play_broadcast(pos) then
        if syncronization_window_is_open()
        then
            -- play next broadcast
            -- print("Playing broadcast")
            local _, broadcast_sound_name = play_a_broadcast(pos)

            sound_radio_tuned_click_1:setPos(sound_pos):stop():play()
            sound_radio_tuned_click_2:setPos(sound_pos):stop():play()

            local seed_from_sound_name = 0
            for _, num in ipairs(table.pack(string.byte(broadcast_sound_name, 1, -1))) do
                -- randomseed can't use strings as a seed, but all we really have to go on is strings
                -- (indexes can change). So convert the string to bytes, then a table, then sum up the table.
                seed_from_sound_name = seed_from_sound_name + num
            end

            math.randomseed(client:getSystemTime())
            local particle_a = particles:newParticle("note",
                current_radio.pos + vec(math.random() / 2 + 0.25, 0.5, math.random() / 2 + 0.25), vec(0, 0.2, 0))
            local particle_b = particles:newParticle("note",
                current_radio.pos + vec(math.random() / 2 + 0.25, 0.75, math.random() / 2 + 0.25), vec(0, 0.3, 0))

            math.randomseed(seed_from_sound_name)
            particle_a:setColor(vectors.hsvToRGB(vec(math.random(), 0.8, 1)))
            particle_b:setColor(vectors.hsvToRGB(vec(math.random(), 0.8, 1)))
            current_radio.target_tune_x_position = math.random() * -4.75
        else
            particles:newParticle("smoke", current_radio.pos + vec(math.random() / 2 + 0.25, 0.5, math.random() / 2 +
                0.25), vec(0, 0.1, 0))
            sound_radio_tune_attempt:setPitch(math.random() * 2 + 2):setPos(sound_pos):stop():play()
        end
    end
end


-- render loops
local function reset_skull()
    radio_model:setScale(1, 1, 1)
    radio_model["Tune Marker"]:setPos(-1, 0, 0)
    radio_model["Knob A"]:setRot(0, 0, 0)
    radio_model["Knob A"]:setRot(0, 0, 0)
    radio_model["Knob C"]:setRot(0, 0, 0)
    radio_model["Knob Side"]:setRot(0, 0, 0)
    radio_model["Speaker"]:setScale(1, 1, 1)
    radio_model["Antenna"]:setVisible(true) -- Set to false on unknown block radios.
end

local function skull_renderer_loop(_, block)
    reset_skull()
    if not block then return end

    if not pos_is_known_radio(block:getPos()) then
        radio_model["Antenna"]:setVisible(false)
        return
    end

    local current_radio = all_radios[tostring(block:getPos())]
    if not current_radio then
        -- there was a rare bug that a radio would be added, but had not been really added. (?)
        -- I probably fixed it anyways, but this is here to catch that issue.
        -- Radio has not been added yet. ignore it.
        return
    end

    -- annimations
    -- -- punch effects
    -- -- -- Tuning marker
    current_radio.current_tune_x_position = math.lerp(
        current_radio.current_tune_x_position,
        current_radio.target_tune_x_position,
        0.1
    )
    radio_model["Tune Marker"]:setPos(current_radio.current_tune_x_position, 0, 0)

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
    radio_model["Knob A"]:setRot(0, 0, current_radio.current_knob_rotation_a)
    radio_model["Knob B"]:setRot(0, 0, current_radio.current_knob_rotation_b)
    radio_model["Knob C"]:setRot(0, 0, current_radio.current_knob_rotation_c)
    radio_model["Knob Side"]:setRot(current_radio.current_knob_rotation_side, 0, 0)

    -- -- -- Squish and Squash: applied with bounce at the bottom
    local squish = current_radio.squish_scale
    current_radio.squish_scale = math.lerp(squish, 1, 0.2)
    local squash = (2 + (squish * -1))

    -- -- Animations while playing
    local current_radio_broadcast = get_playing_broadcast(block:getPos())
    if current_radio_broadcast then
        local pulse        = math.abs(math.sin((client:getSystemTime() + current_radio_broadcast.started_at) / 400))
        local pulse_faster = math.abs(math.sin((client:getSystemTime() + current_radio_broadcast.started_at) / 200))

        local both_factor, _, out_factor = current_radio_broadcast:get_progress_factor()

        -- -- -- Bounce
        local bounce = math.lerp( 1, (pulse) / 16 + 1.0125, out_factor )
        radio_model:setScale(squash, bounce * squish, squash)

        -- -- -- Speaker
        local speaker_push = math.lerp(1,
            math.lerp(0.9, 1, pulse_faster),
            both_factor
        )
        radio_model["Speaker"]:setScale(speaker_push, speaker_push, 1)
    else
        radio_model:setScale(squash, squish, squash)
    end
end


-- world tick loop
local world_radio_checkup_loop_last_key = nil
local function world_radio_checkup_loop()
    -- this function checks 1 radio per run. so with many radios, it may be slow to detect changes.
    -- but at many radios, will only use a few instructions.
    if radio_count == 0 then return end
    if not all_radios[world_radio_checkup_loop_last_key] then
        -- rare bug where we'll still have a world_radio_checkup_loop_last_key,
        -- but that won't be a valid key anymore. (thus, `next()` will fail)
        -- reset to nil. we'll start the loop over, but better than crashing.
        world_radio_checkup_loop_last_key = nil
    end

    local current_key = next(all_radios, world_radio_checkup_loop_last_key)
    world_radio_checkup_loop_last_key = current_key

    if not current_key and radio_count > 0 then
        current_key = next(all_radios, world_radio_checkup_loop_last_key)
        world_radio_checkup_loop_last_key = current_key
    end

    if not current_key then
        -- shouldn't ever reach this point. But just in case:
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
        if not nearest_radio_key or not all_radios[nearest_radio_key]
            or distancesquared(client:getViewer():getPos(), all_radios[nearest_radio_key].pos + radio_sound_pos_offset)
            > distancesquared(client:getViewer():getPos(), current_radio.pos + radio_sound_pos_offset)
        then
            nearest_radio_key = current_key
            -- print("new nearest radio")
            particles:newParticle("smoke", current_radio.pos + radio_sound_pos_offset, vec(0, 0, 0))
        end
    end
end

local function world_tick_loop()
    -- check next radio and clean up radio list if any are missing.
    world_radio_checkup_loop()

    -- animate sounds
    -- broadcast fade in/out
    for _, current_broadcast in pairs(currently_playing_broadcasts) do
        local real_pos = current_broadcast.radio_pos

        if current_broadcast.done_at < client:getSystemTime()
        then
            kill_broadcast(real_pos)
        else
            current_broadcast.sound:setVolume(
                math.lerp(
                    0,
                    broadcast_target_volume,
                    current_broadcast:get_progress_factor() -- lets sound ramp up and down
                )
            )
        end
    end

    -- -- hiss volume
    local target_static_his_volume = static_hiss_volume
    local nearest_broadcast = (all_radios[nearest_radio_key] and get_playing_broadcast(all_radios[nearest_radio_key].pos) or nil)
    if nearest_broadcast then
        target_static_his_volume = math.lerp(
            static_hiss_volume,
            static_hiss_volume_during_brodcats,
            nearest_broadcast:get_progress_factor() -- inverted, because it's ok if the noise slides arround a bit more. It's animated on every tick anywhays.
        )
    end

    static_hiss:setVolume(
        math.lerp(
            static_hiss:getVolume(),
            target_static_his_volume,
            0.2
        )
    )

    -- -- hiss position
    if nearest_radio_key and radio_count > 0 then
        -- TODO: There's a situational case where nearest_radio_key will point to an old
        -- radio location that no longer has a radio there. Which means it passed through
        -- `unknow_radio()`, which should have fixed the key for us, Print statements
        -- says it is getting set correctly in unknow_radio, but it's still the old
        -- key right here. Loke it's having a race condition with itself.

        -- I'm probably overlooking something. But for now, don't mess with the hiss
        -- position if all_radios[nearest_radio_key] doesn't actualy exist.

        -- The cleanup loop will get arround to fixing this anyways.
        if all_radios[nearest_radio_key] then
            local target_pos = all_radios[nearest_radio_key].pos + radio_sound_pos_offset
            if static_hiss:getPos().y <= -200 then
                -- static_hiss sound gets banished to (0,-255,0) this is a quick check to see it's status.
                -- (since apparently, is_playing isn't reliable (thus says the wiki))
                -- immediatly reset pos and volume
                static_hiss:setPos(target_pos):volume(0)
            else
                static_hiss:setPos(
                    math.lerp(
                        static_hiss:getPos(),
                        target_pos,
                        0.2
                    )
                )
            end
        end
    else
        -- no nearby radio
        static_hiss:setPos(0, -255, 0)
    end

    -- get players interacting with radios
    for _, loopPlayer in pairs(world.getPlayers()) do
        if (loopPlayer:getSwingTime() == 1) then -- this player punched this tick
            local punchedBlock, _, _ = loopPlayer:getTargetedBlock(true, block_reach)
            local punched_block_pos = punchedBlock:getPos()

            if not pos_is_known_radio(punched_block_pos)
                and pos_is_a_radio(punched_block_pos)
                and radio_is_in_range(punched_block_pos)
                and not loopPlayer:isCrouching()
            then
                -- new radio, and it's in range!
                add_radio(punched_block_pos)
                sounds["block.lever.click"]
                    :setPos(punched_block_pos + radio_sound_pos_offset)
                    :setSubtitle("Radio turns on")
                    :setPitch(0.6)
                    :play()
            end

            if pos_is_known_radio(punched_block_pos) then
                if loopPlayer:isCrouching() then
                    unknow_radio(punched_block_pos)
                    sounds["block.lever.click"]
                        :setPos(punched_block_pos + radio_sound_pos_offset)
                        :setSubtitle("Radio turns off")
                        :setPitch(0.5)
                        :play()
                else
                    radio_react_to_punch(punched_block_pos)
                end
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

local function create_tab_list_icon()
    local radio_model_copy_for_portrait = radio_model:copy("radio_model_copy_for_portrait")
    local portrait_bone = models["radio"]:newPart("Portrait_bone", PORTRAIT)
    radio_model_copy_for_portrait:moveTo(portrait_bone)
    radio_model_copy_for_portrait:setParentType("PORTRAIT")
    radio_model_copy_for_portrait:setScale(0.55, 0.55, 0.55):setRot(-10, 35, -25):setPos(-1, 1.5, -5)
end

events.WORLD_TICK:register(wait_for_max_permission_then_init_world_loop, "wait_for_max_permission_then_init_world_loop")
events.SKULL_RENDER:register(render_request_permission_sign_loop, "render_request_permission_sign_loop")

create_tab_list_icon()


-- ----------------------------------------------------------------------------------------------------------------- --


-- Pings
local max_packet_size = 500 -- note: if your song takes more than max_packet_size packets,
-- then there will be a conversion error trying to assign a number > than 255 to the "total packets" count
local max_packet_rate = 1500
if not use_ping_file_transfer and use_fast_packets_when_pings_disabled then
    max_packet_rate = 10
end
local last_packet_sent = client:getSystemTime()

local function make_remore_broadcast_sound_name(id_number)
    return "remote_broadcast#" .. tostring(id_number) --.."-"..tostring(durration_in_s).."s"
end

local incomming_broadcasts = nil
local function ping_broadcast_data_to_client(byte_string_packet)
    if not byte_string_packet then return end

    local raw_packet_data_table = table.pack(string.byte(byte_string_packet, 1, -1))

    local broadcast_id = raw_packet_data_table[1]
    local total_num_host_broadcasts = raw_packet_data_table[2]
    local packet_index = raw_packet_data_table[3]
    local total_packets_count = raw_packet_data_table[4]
    local durration_in_s = raw_packet_data_table[5]

    if not incomming_broadcasts then
        -- this is the first time we're heard from the host
        -- Populate the tables with dummy data to help the
        -- randomizers stay in sync, even if we missed a broadcast already.
        incomming_broadcasts = {}
        for id = 1, total_num_host_broadcasts do
            -- broadcast IDs are all numeric.
            incomming_broadcasts[id] = {}
            incomming_broadcasts[id].done = false
            incomming_broadcasts[id].not_heard_from = true
            incomming_broadcasts[id].incomming_id = id

            table.insert(broadcasts, #broadcasts + 1, {
                sound_name = make_remore_broadcast_sound_name(id),
                is_local = false,
                is_incomming = true
            })
        end
        sort_broadcasts_table()
    end

    local broadcast_name_string = make_remore_broadcast_sound_name(broadcast_id)

    if incomming_broadcasts[broadcast_id].not_heard_from then
        -- first time seeing this broadcast
        incomming_broadcasts[broadcast_id].not_heard_from = nil

        incomming_broadcasts[broadcast_id].total_packets_count = total_packets_count
        incomming_broadcasts[broadcast_id].packet_count = 0
        incomming_broadcasts[broadcast_id].durration_in_s = durration_in_s
        incomming_broadcasts[broadcast_id].packet_data = {}
        incomming_broadcasts[broadcast_id].done = false
    end

    if incomming_broadcasts[broadcast_id].done then return end

    local ogg_data_part = { table.unpack(raw_packet_data_table, 6, #raw_packet_data_table) }

    if not incomming_broadcasts[broadcast_id].packet_data[packet_index] then
        -- first time seeing this packet.
        incomming_broadcasts[broadcast_id].packet_data[packet_index] = ogg_data_part
        incomming_broadcasts[broadcast_id].packet_count = incomming_broadcasts[broadcast_id].packet_count + 1
    end

    if incomming_broadcasts[broadcast_id].packet_count == incomming_broadcasts[broadcast_id].total_packets_count then
        -- we have received all packets for this broadcast.
        incomming_broadcasts[broadcast_id].done = true

        -- print("Broadcast #"..broadcast_id.." has been received")

        local full_data = {}
        for packet_i = 1, incomming_broadcasts[broadcast_id].total_packets_count do
            for _, byte in ipairs(incomming_broadcasts[broadcast_id].packet_data[packet_i]) do
                table.insert(full_data, byte)
            end
        end

        sounds:newSound(broadcast_name_string, full_data)

        -- processing is done. find and update the placeholder broadcast
        for _, search_broadcast in ipairs(broadcasts) do
            if search_broadcast.sound_name == broadcast_name_string then
                search_broadcast.sound = sounds[broadcast_name_string]:setSubtitle(broadcast_name_string)
                search_broadcast.durration = durration_in_s * 1000
                search_broadcast.is_incomming = nil
                break
            end
        end

        incomming_broadcasts[broadcast_id].packets = nil

        -- if not received_broadcast_from_host and nearest_radio_key then
        --     if not host:isHost() then print("Received a remote broadcast") end
        --     -- TODO: make radio react to successfuly host → client broadcasts
        --     -- ie a light goes from red to green or something.
        -- end
        received_broadcast_from_host = true
    end
end

function pings.ping_broadcast_data_to_client(byte_string_packet)
    ping_broadcast_data_to_client(byte_string_packet)
end

-- Host only
if host:isHost() and enable_remote_broadcasts then
    if avatar:getPermissionLevel() ~= "MAX" then
        print("Set yourself to max permissions and reload your avatar plz. :)")
        return
    end

    local host_broadcasts = {}

    -- find adtional broadcasts
    if not file:allowed() then
        return
    elseif not file:exists(host_broadcast_files_root) then
        file:mkdir(host_broadcast_files_root)
        print("Created folder for aditional radio broadcasts at `[figura_root]/data/" .. host_broadcast_files_root .. "`")
    else
        for _, filename in pairs(file:list(host_broadcast_files_root)) do
            local _, _, seconds = string.find(filename, "-(%d+)s%.ogg$")
            if seconds then
                table.insert(host_broadcasts, math.random(1, #host_broadcasts + 1), {
                    file_path = host_broadcast_files_root .. filename,
                    durration = seconds,
                    -- data = {},
                    data_packets = {},
                    data_packets_tables = {}
                })
            end
        end
        table.sort(host_broadcasts, function(a, b)
            return a.file_path < b.file_path
        end)
    end

    if #host_broadcasts == 0 then
        -- no broadcasts? don't bother continuing.
        -- This skips setting up the host tick events.
        return
    elseif #host_broadcasts > 255 then
        -- Max broadcast count is 255. This avoids errors related to `string.char()` later.
        print("Too many host broadcast files!")
        print("Maximum number of broadcasts is 255, but found " .. tostring(#host_broadcasts))
        print("Please remove some brodcasts from `[figura_root]/data/" ..
            host_broadcast_files_root .. "` and then reload this avatar.")
        return
    end

    -- file transfer
    -- "The backend hates this one simple trick!"

    local current_sending_broadcast_index = next(host_broadcasts)
    local function get_next_packet_to_send()
        -- see if current broadcast still has packets. send the next one of those.
        -- if not, get the next broadcast and send it's first packet.
        -- if on last broadcast, shuffle list and send the new first broadcast.

        -- only ask if there are broadcasts to send.
        local packet_index, packet = next(host_broadcasts[current_sending_broadcast_index].data_packets,
            host_broadcasts[current_sending_broadcast_index].last_packet_index)

        if not packet_index then
            -- we passed last packet. Reset and move to next broadcast.
            host_broadcasts[current_sending_broadcast_index].last_packet_index = nil
            current_sending_broadcast_index = next(host_broadcasts, current_sending_broadcast_index)
            if not current_sending_broadcast_index then
                -- end of list of broadcasts. run again to get the top of the broadcasts list.
                current_sending_broadcast_index = next(host_broadcasts, nil)
            end
            -- print("Switching to next broadcast.")
            return get_next_packet_to_send()
        end

        host_broadcasts[current_sending_broadcast_index].last_packet_index = packet_index

        return packet, host_broadcasts[current_sending_broadcast_index].data_packets_tables[packet_index]
    end

    local function send_data_to_clients_loop()
        -- print(get_next_packet_to_send())
        if client:getSystemTime() > last_packet_sent + max_packet_rate then
            last_packet_sent = client:getSystemTime()

            local packet_byte_string, packet_byte_table = get_next_packet_to_send()
            -- printTable(packet_byte_string)

            if use_ping_file_transfer then
                pings.ping_broadcast_data_to_client(packet_byte_string)
            else
                ping_broadcast_data_to_client(packet_byte_string)
            end

            -- byte_str → table test. effects actionbar
            -- packet_byte_table = table.pack(string.byte(packet_byte_string, 1, -1))

            if pos_is_a_radio(player:getTargetedBlock(true, block_reach):getPos()) then
                host:actionbar("Broadcast #" ..
                    packet_byte_table[1] ..
                    " of " .. packet_byte_table[2] ..
                    " - Sending packet " .. packet_byte_table[3] .. " of " .. packet_byte_table[4])
            end
        end
    end

    local last_processed_host_broadcast_index = nil
    local function process_next_host_broadcast()
        local current_host_broadcast_key, current_host_broadcast = next(host_broadcasts,
            last_processed_host_broadcast_index)
        last_processed_host_broadcast_index = current_host_broadcast_key

        if not current_host_broadcast_key then
            events.WORLD_RENDER:remove("one-at-a-time_host_broadcast_processor_loop")
            events.TICK:register(send_data_to_clients_loop)
            return
        end

        local broadcast_file_read_stream = file:openReadStream(current_host_broadcast.file_path)
        local available = broadcast_file_read_stream:available()
        local total_packets = math.floor((available - (available % max_packet_size)) / max_packet_size)

        -- bounds checking. Should prevent errors in string.char()
        if tonumber(current_host_broadcast_key) < 0 or tonumber(current_host_broadcast_key) > 255 then
            print("Skipping brodcast with out of range key: `" .. tostring(current_host_broadcast_key) .. "`")
            return
        elseif tonumber(total_packets) < 0 or tonumber(total_packets) > 255 then
            print("Brodcast `" ..
                current_host_broadcast.file_path ..
                "`. is too large. (The maximim packet count is 255, but this file needs " ..
                tostring(total_packets) .. " packets.)")
            return
        elseif tonumber(current_host_broadcast.durration) < 0 or tonumber(current_host_broadcast.durration) > 255 then
            print("Brodcast `" ..
                current_host_broadcast.file_path ..
                "`. is too long. (The maximim durration is 255 seconds, but this file needs " ..
                tostring(current_host_broadcast.durration) .. " secconds.)")
            return
        end

        local packet_builder = {}
        table.insert(packet_builder, tonumber(current_host_broadcast_key))
        table.insert(packet_builder, tonumber(#host_broadcasts)) -- already checked in intiial `isHost()` call under `elseif #host_broadcasts > 255 then`
        table.insert(packet_builder, tonumber(1))
        table.insert(packet_builder, tonumber(total_packets))
        table.insert(packet_builder, tonumber(current_host_broadcast.durration))

        local last_packet_index = 1
        for i = 1, available do
            -- table.insert(current_host_broadcast.data, data)
            local packet_index = math.floor((i - (i % max_packet_size)) / max_packet_size) + 1
            if packet_index > last_packet_index then
                -- print("time to make a new packet")

                table.insert(current_host_broadcast.data_packets_tables, packet_builder)
                table.insert(current_host_broadcast.data_packets, string.char(table.unpack(packet_builder)))

                last_packet_index = packet_index

                packet_builder = {}
                table.insert(packet_builder, tonumber(current_host_broadcast_key))
                table.insert(packet_builder, tonumber(#host_broadcasts))
                table.insert(packet_builder, tonumber(packet_index))
                table.insert(packet_builder, tonumber(total_packets))
                table.insert(packet_builder, tonumber(current_host_broadcast.durration))
            end
            -- print("byte")
            table.insert(packet_builder, broadcast_file_read_stream:read())
        end
        broadcast_file_read_stream:close()
    end

    -- Tick allways goes in order, even if they take longer than 1/20 of a second, which can bring the game to a halt.
    -- world_render firers whenever it happens to be ready.
    -- usefull to prevent total freezes while processing many large files.
    events.WORLD_RENDER:register(process_next_host_broadcast, "one-at-a-time_host_broadcast_processor_loop")
end
