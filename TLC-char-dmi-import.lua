-- utils
local function str_split(inputstr, sep)
    if sep == nil then sep = "%s" end
    local t = {}
    for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
        table.insert(t, str)
    end
    return t
end

-- consumes a string of space deliminted numbers, e.g "1 4 9" and returns Table<Number>
local function tovector(s)
    local t = {}
    s:gsub('%-?%d+', function(n) t[#t + 1] = tonumber(n) end)
    return t
end

local function string_replace(s, find, replace)
    return string.gsub(s, find, replace)
end

-- removes spaces from string, e.g " test " -> "test"
local function trim(str)
    local res = string.gsub(str, "%s+", "")
    return res
end
-- takes the string "width = 32" and returns {key, val}
-- where val can be a number | string | table<numbers>
local function parse_assignment(str)
    local res = {}
    local spl = str_split(str, " = ")
    local key = trim(spl[1])
    local val = trim(spl[2])
    res[1] = key
    local try_number = tonumber(val)
    if try_number ~= nil then
        res[2] = try_number
        return res
    end

    if key == "delay" then
        -- its a sequence of numbers with comma delimination: "1,2,3"
        local spaced = string_replace(val, ",", " ")
        local vec = tovector(spaced)
        res[2] = vec
        -- print(spaced, vec)
        return res
    end
    -- otherwise its probably a quoted string, so we remove quotes
    res[2] = string_replace(val, "\"", "")
    return res
end
-- parse_assignment("delay = 2,2")

local function num_to_dir(num)
    if num == 0 then
        return "s"
    elseif num == 1 then
        return "n"
    elseif num == 2 then
        return "e"
    elseif num == 3 then
        return "w"
    elseif num == 4 then
        return "se"
    elseif num == 5 then
        return "sw"
    elseif num == 6 then
        return "ne"
    elseif num == 7 then
        return "nw"
    end
end

local function find_state(t, state_name)
    for _, v in ipairs(t) do if v[K_NAME] == state_name then return v end end
    if DEBUG then print("Could not find state: " .. state_name) end
end

-- main

local config_path = app.fs.userConfigPath
-- todo: test if this path works on windows
local scripts_dir = app.fs.joinPath(config_path, "scripts")
local dump_exe_path = app.fs.joinPath(scripts_dir, "dump_ztxt")

K_NAME = "state"
K_DIRS = "dirs"
K_DELAY = "delay"
K_FRAMES = "frames"
K_INDICIES = "g_indicies"
DEBUG = false
local function import_image(image_path, mask_sprite)
    -- added quotes around imagepath or else it wont work with paths with spaces
    local fpath = app.fs.tempPath
    if DEBUG then fpath = app.fs.filepath(image_path) end
    local anim_txt_path = app.fs.joinPath(fpath, "0TEMP.ztxt")
    local command = dump_exe_path .. " \"" .. image_path .. "\" -o \"" ..
                        anim_txt_path .. "\""
    local command_res = os.execute(command)
    if DEBUG then print("running: " .. command) end
    if command_res == nil then
        print(
            "Could not find the extractor to dump icon metadata or something else went wrong @: " ..
                dump_exe_path)
        return
    end
    -- print(anim_txt_path)
    local width = nil
    local height = nil
    local state_counter = 0
    -- contains [{state: "", dirs: number, frames: number, delay: number | nil, movement: number}]
    local all_states = {}
    for l in io.lines(anim_txt_path) do
        if string.match(l, "# BEGIN DMI") or string.match(l, "version = 4.0") then
            -- don't do anything
        elseif string.match(l, "width = ") and width == nil then
            local kv = parse_assignment(l)
            width = kv[2]
        elseif string.match(l, "height = ") and height == nil then
            local kv = parse_assignment(l)
            height = kv[2]
        elseif string.match(l, "state = ") then
            state_counter = state_counter + 1
            local kv = parse_assignment(l)
            local state_name = kv[2]
            all_states[state_counter] = {}
            all_states[state_counter][K_NAME] = state_name -- state is assumed to be a string
        else
            local kv = parse_assignment(l)
            local key = kv[1]
            all_states[state_counter][key] = kv[2]
        end
    end

    for _, v in pairs(all_states) do
        if v["movement"] == nil and v[K_NAME] == "normal" then
            -- print("Renaming idle")
            v[K_NAME] = "idle"
        end
    end
    app.open(image_path) -- use this instead of app.command.OpenFile because it will reject anything that is not of png extension
    -- print(image_path, width, height)
    if width == nil or height == nil then
        print("Could not determine frame width or height.")
        return
    end
    app.command.ImportSpriteSheet {
        ui = false,
        type = SpriteSheetType.ROWS,
        frameBounds = Rectangle(0, 0, width, height),
        padding = Size(0, 0),
        partialTiles = false
    }
    local sprite = app.activeSprite
    app.command.ChangePixelFormat {format = "rgb"}
    -- NOTE: we create a new layer so the indices are constant and refer to the same image. Swapping in place will be a headache
    local old_layer = app.activeLayer
    local organized_layer = sprite:newLayer() -- organizes byond frames by state sequentially so we can pick them apart more easily
    organized_layer.name = "organized"

    -- tag with e,n,s,w,sw for directions! 
    -- byond always stores directions in the order of south, north, east, west (snew) + (se, sw, ne, nw,)
    local last_offset = 1
    local global_frame_counter = 1
    local snew_states = {} -- {state: string, k_indicies: {numbers}}
    local snew_count = 1
    for _, t in ipairs(all_states) do
        local state_name = t[K_NAME]
        local max_dirs = t[K_DIRS]
        local max_frames = t[K_FRAMES]
        local delays = t[K_DELAY]
        t[K_INDICIES] = {}
        -- print(state_name, max_dirs, max_frames)
        for index_dir = 0, (max_dirs - 1) do
            local tag_start = global_frame_counter
            local dir_name = num_to_dir(index_dir)
            snew_states[snew_count] = {}
            snew_states[snew_count][K_NAME] = state_name .. "_" .. dir_name
            snew_states[snew_count][K_INDICIES] = {}
            for index_frame = 0, (max_frames - 1) do
                local frame_num = last_offset + index_dir + index_frame *
                                      max_dirs
                snew_states[snew_count][K_INDICIES][index_frame + 1] =
                    global_frame_counter
                local old_cel = old_layer:cel(frame_num)
                if old_cel ~= nil then
                    sprite:newCel(organized_layer, global_frame_counter,
                                  old_cel.image)
                else
                    sprite:newCel(organized_layer, global_frame_counter)
                end
                if delays ~= nil then
                    -- add delays
                    local dur = delays[index_frame + 1] / 10
                    organized_layer.sprite.frames[global_frame_counter].duration =
                        dur
                end
                global_frame_counter = global_frame_counter + 1
            end
            -- local tag = sprite:newTag(tag_start, global_frame_counter - 1)
            -- tag.name = state_name .. "_" .. dir_name
            snew_count = snew_count + 1
        end
        last_offset = global_frame_counter
    end
    -- should provide a way to optionally delete?
    sprite:deleteLayer(old_layer)

    -- string number -> struct
    -- the number should be RELATIVE to the animation tag and not the global frame number 
    local function mbase(from_state, num)
        return {from = from_state, num = num}
    end

    -- returns {new_name: "", frames={}} where frames are all from the state
    local function make_same_state(snew_states, state_name)
        local state = find_state(snew_states, state_name)
        if state == nil then return false end
        local res = {}
        res.new_name = state[K_NAME]
        res.frames = {}
        for i, num in ipairs(state[K_INDICIES]) do
            res.frames[i] = mbase(state[K_NAME], i)
        end
        return res
    end
    local idle_e = make_same_state(snew_states, "idle_e")
    local idle_n = make_same_state(snew_states, "idle_n")
    local idle_s = make_same_state(snew_states, "idle_s")
    local idle_w = make_same_state(snew_states, "idle_w")

    -- may optionally contain false for idle animations that don't exist
    local new_anims = {
        {
            new_name = "blink_e",
            frames = {
                mbase("normal_e", 1), mbase("normal_e", 1),
                mbase("normal_sleeping_e", 1), mbase("normal_e", 1),
                mbase("normal_e", 1)
            }
        }, {new_name = "blink_n", frames = {mbase("normal_n", 1)}}, {
            new_name = "blink_s",
            frames = {
                mbase("normal_s", 1), mbase("normal_s", 1),
                mbase("normal_sleeping_s", 1), mbase("normal_s", 1),
                mbase("normal_s", 1)
            }
        }, {
            new_name = "blink_w",
            frames = {
                mbase("normal_w", 1), mbase("normal_w", 1),
                mbase("normal_sleeping_w", 1), mbase("normal_w", 1),
                mbase("normal_w", 1)
            }
        }, {
            new_name = "down_n",
            frames = {
                mbase("normal_n", 1), mbase("normal_n", 2),
                mbase("normal_n", 3), mbase("normal_n", 4)
            }
        }, {
            new_name = "drawn_e",
            frames = {
                mbase("ShootingMachineH_e", 1), mbase("ShootingMachineH_e", 1)
            }
        }, {
            new_name = "drawn_n",
            frames = {
                mbase("ShootingMachineH_n", 1), mbase("ShootingMachineH_n", 1)
            }
        }, {
            new_name = "drawn_s",
            frames = {
                mbase("ShootingMachineH_s", 1), mbase("ShootingMachineH_s", 1)
            }
        }, {
            new_name = "drawn_w",
            frames = {
                mbase("ShootingShotgun_w", 1), mbase("ShootingShotgun_w", 1)
            }
        }, {
            new_name = "hurtidle_e",
            frames = {mbase("normal_e", 1), mbase("normal_sleeping_e", 1)}
        }, {new_name = "hurtidle_n", frames = {mbase("normal_sleeping_n", 1)}},
        {
            new_name = "hurtidle_s",
            frames = {mbase("normal_s", 1), mbase("normal_sleeping_s", 1)}
        }, {
            new_name = "hurtidle_w",
            frames = {mbase("normal_w", 1), mbase("normal_sleeping_w", 1)}
        }, {
            new_name = "hurtwalk_e",
            frames = {mbase("normal_e", 2), mbase("normal_e", 1)}
        }, {
            new_name = "hurtwalk_n",
            frames = {mbase("normal_n", 2), mbase("normal_n", 1)}
        }, {
            new_name = "hurtwalk_s",
            frames = {mbase("normal_s", 2), mbase("normal_s", 1)}
        }, {
            new_name = "hurtwalk_w",
            frames = {mbase("normal_w", 2), mbase("normal_w", 1)}
        }, 
        {new_name = "sit_e", frames = {mbase("normal_e", 1), mbase("normal_e", 1), mbase("normal_sleeping_e", 1)}},
        {new_name = "sit_n", frames = {mbase("normal_n", 1)}},
        {new_name = "sit_s", frames = {mbase("normal_s", 1), mbase("normal_s", 1), mbase("normal_sleeping_s", 1)}},
        {new_name = "sit_w", frames = {mbase("normal_w", 1), mbase("normal_w", 1), mbase("normal_sleeping_w", 1)}},
        {new_name = "sleep_e", frames = {mbase("normal_sleeping_e", 1)}},
        {new_name = "sleep_n", frames = {mbase("normal_sleeping_n", 1)}},
        {new_name = "sleep_s", frames = {mbase("normal_sleeping_s", 1)}},
        {new_name = "sleep_w", frames = {mbase("normal_sleeping_w", 1)}}, {
            new_name = "tiredidle_e",
            frames = {mbase("normal_e", 1), mbase("normal_e", 1)}
        }, {
            new_name = "tiredidle_n",
            frames = {mbase("normal_n", 1), mbase("normal_n", 1)}
        }, {
            new_name = "tiredidle_s",
            frames = {mbase("normal_s", 1), mbase("normal_s", 1)}
        }, {
            new_name = "tiredidle_w",
            frames = {mbase("normal_w", 1), mbase("normal_w", 1)}
        }, -- IDLE HAPPENS HERE!
        idle_e, idle_n, idle_s, idle_w, {
            new_name = "walk_e",
            frames = {
                mbase("normal_e", 4), mbase("normal_e", 3),
                mbase("normal_e", 2), mbase("normal_e", 1)
            }
        }, {
            new_name = "walk_n",
            frames = {
                mbase("normal_n", 4), mbase("normal_n", 3),
                mbase("normal_n", 2), mbase("normal_n", 1)
            }
        }, {
            new_name = "walk_s",
            frames = {
                mbase("normal_s", 4), mbase("normal_s", 3),
                mbase("normal_s", 2), mbase("normal_s", 1)
            }
        }, {
            new_name = "walk_w",
            frames = {
                mbase("normal_w", 4), mbase("normal_w", 3),
                mbase("normal_w", 2), mbase("normal_w", 1)
            }
        }, {
            new_name = "wink_s",
            frames = {
                mbase("normal_s", 1), mbase("normal_s", 1),
                mbase("normal_sleeping_s", 1)
            }
        }, {
            new_name = "handgun_e",
            frames = {
                mbase("ShootingHandgun_e", 1), mbase("ShootingHandgun_e", 2)
            }
        }, {
            new_name = "machineh_e",
            frames = {
                mbase("ShootingMachineH_e", 1), mbase("ShootingMachineH_e", 2)
            }
        },
        {
            new_name = "melee_e",
            frames = {mbase("Melee_e", 2), mbase("Melee_e", 1)}
        }, {
            new_name = "shotgun_e",
            frames = {
                mbase("ShootingShotgun_e", 1), mbase("ShootingShotgun_e", 2)
            }
        }
    }
    local body_layer = sprite:newLayer()
    body_layer.name = "body"
    -- for _, t in ipairs(snew_states) do
    --    print(t[K_STATE])
    --    for i, v in ipairs(t[K_INDICIES]) do print(v) end
    -- end
    local need_total_frames = 0
    for _, anim in ipairs(new_anims) do 
        if anim ~= false then
            need_total_frames = need_total_frames + #anim.frames
        end
    end
    --print(need_total_frames, #sprite.frames)
    for i = #sprite.frames, need_total_frames + 1 do 
        sprite:newFrame(i)
    end

    local seq_counter = 1
    for _, anim in ipairs(new_anims) do
        if anim == false then goto continue end
        local tag_start = seq_counter
        for _, frame in ipairs(anim.frames) do
            local from_state = frame.from
            local ref = find_state(snew_states, from_state)
            local to_index = ref[K_INDICIES][frame.num]
            -- print(ref[K_STATE], ref[K_INDICIES][frame.num])
            local from_cel = organized_layer:cel(to_index)
            if from_cel ~= nil then
                local pos = from_cel.position
                -- shift
                if anim.new_name == "drawn_e" then
                    pos.x = pos.x + 8
                elseif anim.new_name == "drawn_w" then
                    pos.x = pos.x - 4 -- shootshotgun midshift is 4
                end
                sprite:newCel(body_layer, seq_counter, from_cel.image, pos)
            else
                sprite:newCel(body_layer, seq_counter)
            end
            if #sprite.frames > seq_counter + 1 then
                seq_counter = seq_counter + 1
            end
        end
        local tag = sprite:newTag(tag_start, seq_counter - 1)
        tag.name = anim.new_name
        ::continue::
    end

    organized_layer.isVisible = false
    local mask_layer = sprite:newLayer()
    mask_layer.name = "mask"

    local mask_sprite_layer = mask_sprite.layers[#mask_sprite.layers] -- "THE MASK SHOULD BE AT THE TOP MOST OF THE MASK.ASE FILE"
    for _, tag in ipairs(sprite.tags) do
        for _, mask_tag in ipairs(mask_sprite.tags) do
            if mask_tag.name == tag.name then
                local curr_frame = tag.fromFrame
                local from_maskframe = mask_tag.fromFrame
                for _ = 1, tag.frames do
                    -- copy over the mask layer
                    local mask_frame_num = from_maskframe.frameNumber
                    if (tag.name == "idle_e" or tag.name == "idle_n" or tag.name ==
                        "idle_s" or tag.name == "idle_w") then
                        -- spread the first frame of the idle only!
                        mask_frame_num = mask_tag.fromFrame.frameNumber
                    end
                    local mask_cel = mask_sprite_layer:cel(mask_frame_num)
                    local newcel = sprite:newCel(mask_layer, curr_frame,
                                                 mask_cel.image,
                                                 mask_cel.position)
                    -- COPY OVER THE DELAYS FROM MASK.ase AS WELL HERE EXCEPT FOR IDLE
                    if not (tag.name == "idle_e" or tag.name == "idle_n" or
                        tag.name == "idle_s" or tag.name == "idle_w") then
                        newcel.frame.duration = mask_cel.frame.duration
                        from_maskframe = from_maskframe.next
                    end
                    curr_frame = curr_frame.next
                end
            end
        end
    end
    -- app.command.CloseFile() -- close the mask.ase file
    -- app.command.GotoPreviousTab()
    -- TODO: SEE IF WE CAN USE LAYER MERGING MODES FOR CUTTING HEADS OUT INSTEAD OF TRYING CODE IT ALL MANUALLY?
    -- import the mask on all frames and then just use a layer merging mode to crop the heads out
    -- or try to use magicwand selection on mask layer(on the bottom right corner) and app command cut on new head layer? for every frame?
    local head_layer = sprite:newLayer()
    head_layer.name = "head"
    for i, tag in ipairs(sprite.tags) do
        local curr_frame = tag.fromFrame
        for _ = 1, tag.frames do
            local frame_num = curr_frame.frameNumber
            local mask_cel = mask_layer:cel(frame_num)
            app.useTool {
                tool = "magic_wand",
                layer = mask_layer,
                cel = mask_cel,
                button = MouseButton.LEFT,
                points = {Point(0, 0)},
                selection = SelectionMode.REPLACE
            }
            app.activeLayer = body_layer
            app.activeFrame = body_layer:cel(frame_num).frame
            app.command.Cut()
            app.activeLayer = head_layer
            if not (tag.name == "handgun_e" or tag.name == "machineh_e" or
                tag.name == "melee_e" or tag.name == "shotgun_e") then
                -- selection is inverted works out so that we don't need to paste to head layer as hands remain in body
                app.command.Paste()
            end
            app.command.DeselectMask()
            curr_frame = curr_frame.next
        end
    end
    sprite:deleteLayer(organized_layer)
    sprite:deleteLayer(mask_layer)

    -- SHIFT HANDS! 1ST FRAME SHOULD JUST BE A -1 SHIFT OF THE 2ND FRAME(except for melee!)
    for _, tag in ipairs(sprite.tags) do
        if (tag.name == "handgun_e" or tag.name == "machineh_e" or tag.name ==
            "shotgun_e") then
            local first = tag.fromFrame
            local next = first.next
            local first_cel = body_layer:cel(first.frameNumber)
            local second_cel = body_layer:cel(next.frameNumber)
            if first_cel == nil or second_cel == nil then
                goto continue
            end
            app.activeLayer = body_layer
            app.activeFrame = first_cel.frame
            app.command.ClearCel()
            local off_x1 = second_cel.position
            off_x1.x = off_x1.x - 1
            sprite:newCel(body_layer, first, second_cel.image, off_x1)
        end
        ::continue::
    end
    local last_tag = sprite.tags[#sprite.tags]
    local last_valid_frame = last_tag.toFrame.frameNumber
    for i = #sprite.frames, last_valid_frame + 1, -1 do
        sprite:deleteFrame(sprite.frames[i])
    end

    local idle_delays = nil
    for _, state in ipairs(all_states) do
        -- idle delays are the same for every direction in the dmi file
        if state[K_NAME] == "idle" then idle_delays = state[K_DELAY] end
    end
    -- we merge sequential frames that are exactly the same for idle animations only(not blink because they still need to be worked on)
    for _, tag in ipairs(sprite.tags) do
        -- add idle durations based off the dmi
        if tag.name == "idle_e" or tag.name == "idle_n" or tag.name == "idle_s" or
            tag.name == "idle_w" then
            local curr_frame = tag.fromFrame
            for i = 1, tag.frames do
                if idle_delays ~= nil and tag.name == "idle_s" then
                    curr_frame.duration = idle_delays[i] / 10
                end
                curr_frame = curr_frame.next
            end
        end
    end

    for _, tag in ipairs(sprite.tags) do
        if tag.name == "idle_e" or tag.name == "idle_n" or tag.name == "idle_s" or
            tag.name == "idle_w" then
            local curr_frame = tag.fromFrame
            for _ = 1, tag.frames do
                local try_next_frame = curr_frame.next
                if try_next_frame ~= nil then
                    local curr_head = head_layer:cel(curr_frame)
                    local curr_body = body_layer:cel(curr_frame)
                    local next_head = head_layer:cel(try_next_frame)
                    local next_body = body_layer:cel(try_next_frame)
                    if curr_head ~= nil and curr_body ~= nil and next_head ~=
                        nil and next_body ~= nil and
                        curr_head.image:isEqual(next_head.image) and
                        curr_body.image:isEqual(next_body.image) then
                        -- if equal, merge duration and delete
                        curr_frame.duration =
                            curr_frame.duration + try_next_frame.duration
                        if DEBUG then
                            print("merging " .. curr_frame.frameNumber ..
                                      " and " .. try_next_frame.frameNumber ..
                                      " for " .. tag.name)
                        end
                        sprite:deleteFrame(try_next_frame)
                    else
                        if DEBUG then
                            print("diff: " .. curr_frame.frameNumber,
                                  try_next_frame.frameNumber)
                        end
                        curr_frame = curr_frame.next
                    end
                end

            end
        end
    end
    local without_ext = app.fs.filePathAndTitle(image_path)
    app.command.saveFile {
        ["filename"] = without_ext .. ".ase",
        ["filename-format"] = ".ase"
    }
    return sprite
end

local config_path = app.fs.userConfigPath
local scripts_dir = app.fs.joinPath(config_path, "scripts")
local mask_ase_path = app.fs.joinPath(scripts_dir, "mask.ase")
if app.isUIAvailable then
    -- https://github.com/aseprite/aseprite/issues/4352 MAKES IT SO WE HAVE TO OPEN THE MASK FILE FIRST CAUSE WE CANT CLOSE OR SWITCH TABS WITHOUT CRASHING
    -- NOTE: Because --batch mode is bugged atm(see below), for automation, we are running with UI, hence why the file picker stuff is commented out atm
        local mask_sprite = app.open(mask_ase_path)
    if mask_sprite == nil then
        print("could not open mask ase file")
        return
    end
    local image_path = app.params["file"]
    import_image(image_path, mask_sprite)
    app.exit()

    -- local dlg = Dialog()
    -- local PICKER = "picker"
    -- local image_path = ""
    -- dlg:file{
    --    id = PICKER,
    --    label = "select dmi or png file",
    --    title = "dmi importer",
    --    load = false,
    --    open = false,
    --    filename = image_path,
    --    filetypes = {"dmi", "png"}
    -- }:button{
    --    id = "Ok",
    --    text = "Ok",
    --    onclick = function()
    --        local mask_sprite = app.open(
    --                                "/mnt/shared/t0-assets/latest_2021_dec_iconshare_server/mask.ase")
    --        if mask_sprite == nil then
    --            print("could not open mask ase file")
    --            return
    --        end
    --        import_image(dlg.data[PICKER], mask_sprite)
    --        dlg:close()
    --    end
    -- }:show()
else
    -- cli mode

    -- NOTE: A LOT OF HACKS NEED ARE NEEDED BECAUSE ASEPRITE IS BUGGY:
    -- mask must be opened first because we can't close
    -- CANNOT RUN WITH --batch BECAUSE COPY AND PASTE TO LAYERS ISNT WORKING
    -- MUST RUN IN UI MODE WITH:
    -- aseprite.exe --script-param="file=<path.png>" --script="TLC-dmi-import.lua"
    -- this will create a file of the same name but with diff extension
    -- CANNOT DO --batch THIS UNTIL: https://github.com/aseprite/aseprite/issues/4354 is fixed
    print("SHOULD NOT RUN IN --BATCH MODE BECAUSE CUT AND PASTE DOES NOT WORK. See aseprite#4354")
    local mask_sprite = app.open(mask_ase_path)
    if mask_sprite == nil then
        print("could not open mask ase file")
        return
    end
    local image_path = app.params["file"]
    import_image(image_path, mask_sprite)

end
