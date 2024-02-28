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
-- main

local config_path = app.fs.userConfigPath
-- todo: test if this path works on windows
local scripts_dir = app.fs.joinPath(config_path, "scripts")
local dump_exe_path = app.fs.joinPath(scripts_dir, "dump_ztxt")

local K_STATE = "state"
local K_DIRS = "dirs"
local K_DELAY = "delay"
local K_FRAMES = "frames"
local debug = false
local function import_image(image_path)
    -- added quotes around imagepath or else it wont work with paths with spaces
    local fpath = app.fs.tempPath
    if debug then fpath = app.fs.filepath(image_path) end
    local anim_txt_path = app.fs.joinPath(fpath, "0TEMP.ztxt")
    local command = dump_exe_path .. " \"" .. image_path .. "\" -o \"" ..
                        anim_txt_path .. "\""
    local command_res = os.execute(command)
    if debug then print("running: " .. command) end
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
            all_states[state_counter][K_STATE] = state_name -- state is assumed to be a string
        else
            local kv = parse_assignment(l)
            local key = kv[1]
            all_states[state_counter][key] = kv[2]
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
    -- NOTE: we create a new layer so the indices are constant and refer to the same image. Swapping in place will be a headache
    local old_layer = app.activeLayer
    local new_layer = sprite:newLayer()

    -- tag with e,n,s,w,sw for directions! 
    -- byond always stores directions in the order of south, north, east, west (snew) + (se, sw, ne, nw,)
    local last_offset = 1
    local global_frame_counter = 1
    for _, t in ipairs(all_states) do
        local state_name = t[K_STATE]
        local max_dirs = t[K_DIRS]
        local max_frames = t[K_FRAMES]
        local delays = t[K_DELAY]
        -- print(state_name, max_dirs, max_frames)
        for index_dir = 0, (max_dirs - 1) do
            local tag_start = global_frame_counter
            for index_frame = 0, (max_frames - 1) do
                local frame_num = last_offset + index_dir + index_frame *
                                      max_dirs
                -- print(index_dir, frame_num, last_offset, lua_frame_num)
                sprite:newCel(new_layer, global_frame_counter,
                              old_layer:cel(frame_num).image)
                if delays ~= nil then
                    -- add delays
                    local dur = delays[index_frame + 1] / 10
                    new_layer.sprite.frames[global_frame_counter].duration = dur
                end
                global_frame_counter = global_frame_counter + 1
            end
            local tag = sprite:newTag(tag_start, global_frame_counter - 1)
            tag.name = state_name .. "_" .. num_to_dir(index_dir)
        end
        last_offset = global_frame_counter
    end
    -- should provide a way to optionally delete?
    sprite:deleteLayer(old_layer)
    return sprite
end

if app.isUIAvailable then
    local dlg = Dialog()
    local PICKER = "picker"
    local image_path = ""
    dlg:file{
        id = PICKER,
        label = "select dmi or png file",
        title = "dmi importer",
        load = false,
        open = false,
        filename = image_path,
        filetypes = {"dmi", "png"}
    }:button{
        id = "Ok",
        text = "Ok",
        onclick = function()
            -- print(dlg.data[PICKER])
            import_image(dlg.data[PICKER])
            dlg:close()
        end
    }:show()
else
    -- cli mode
    -- examples: aseprite.exe "Sparkybio2.dmi" --script="dmi-import.lua" --batch
    -- this will create a file of the same name but with dmi extension
    local fname = app.activeSprite.filename
    local new = import_image(fname)
    local without_ext = app.fs.filePathAndTitle(fname)
    app.command.saveFileAs {
        ["filename"] = without_ext .. ".ase",
        ["filename-format"] = ".ase"
    }
end
