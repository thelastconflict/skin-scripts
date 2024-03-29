local json = {_version = "0.1.1"}

-------------------------------------------------------------------------------
-- Encode
-------------------------------------------------------------------------------

local encode

local escape_char_map = {
    ["\\"] = "\\\\",
    ["\""] = "\\\"",
    ["\b"] = "\\b",
    ["\f"] = "\\f",
    ["\n"] = "\\n",
    ["\r"] = "\\r",
    ["\t"] = "\\t"
}

local escape_char_map_inv = {["\\/"] = "/"}
for k, v in pairs(escape_char_map) do escape_char_map_inv[v] = k end

local function escape_char(c)
    return escape_char_map[c] or string.format("\\u%04x", c:byte())
end

local function encode_nil(val) return "null" end

local function encode_table(val, stack)
    local res = {}
    stack = stack or {}

    -- Circular reference?
    if stack[val] then error("circular reference") end

    stack[val] = true

    if val[1] ~= nil or next(val) == nil then
        -- Treat as array -- check keys are valid and it is not sparse
        local n = 0
        for k in pairs(val) do
            if type(k) ~= "number" then
                error("invalid table: mixed or invalid key types")
            end
            n = n + 1
        end
        if n ~= #val then error("invalid table: sparse array") end
        -- Encode
        for i, v in ipairs(val) do table.insert(res, encode(v, stack)) end
        stack[val] = nil
        return "[" .. table.concat(res, ",") .. "]"

    else
        -- Treat as an object
        for k, v in pairs(val) do
            if type(k) ~= "string" then
                error("invalid table: mixed or invalid key types")
            end
            table.insert(res, encode(k, stack) .. ":" .. encode(v, stack))
        end
        stack[val] = nil
        return "{" .. table.concat(res, ",") .. "}"
    end
end

local function encode_string(val)
    return '"' .. val:gsub('[%z\1-\31\\"]', escape_char) .. '"'
end

local function encode_number(val)
    -- Check for NaN, -inf and inf
    if val ~= val or val <= -math.huge or val >= math.huge then
        error("unexpected number value '" .. tostring(val) .. "'")
    end
    return string.format("%.14g", val)
end

local type_func_map = {
    ["nil"] = encode_nil,
    ["table"] = encode_table,
    ["string"] = encode_string,
    ["number"] = encode_number,
    ["boolean"] = tostring
}

encode = function(val, stack)
    local t = type(val)
    local f = type_func_map[t]
    if f then return f(val, stack) end
    error("unexpected type '" .. t .. "'")
end

function json.encode(val) return (encode(val)) end

-------------------------------------------------------------------------------
-- Decode
-------------------------------------------------------------------------------

local parse

local function create_set(...)
    local res = {}
    for i = 1, select("#", ...) do res[select(i, ...)] = true end
    return res
end

local space_chars = create_set(" ", "\t", "\r", "\n")
local delim_chars = create_set(" ", "\t", "\r", "\n", "]", "}", ",")
local escape_chars = create_set("\\", "/", '"', "b", "f", "n", "r", "t", "u")
local literals = create_set("true", "false", "null")

local literal_map = {["true"] = true, ["false"] = false, ["null"] = nil}

local function next_char(str, idx, set, negate)
    for i = idx, #str do if set[str:sub(i, i)] ~= negate then return i end end
    return #str + 1
end

local function decode_error(str, idx, msg)
    local line_count = 1
    local col_count = 1
    for i = 1, idx - 1 do
        col_count = col_count + 1
        if str:sub(i, i) == "\n" then
            line_count = line_count + 1
            col_count = 1
        end
    end
    error(string.format("%s at line %d col %d", msg, line_count, col_count))
end

local function codepoint_to_utf8(n)
    -- http://scripts.sil.org/cms/scripts/page.php?site_id=nrsi&id=iws-appendixa
    local f = math.floor
    if n <= 0x7f then
        return string.char(n)
    elseif n <= 0x7ff then
        return string.char(f(n / 64) + 192, n % 64 + 128)
    elseif n <= 0xffff then
        return string.char(f(n / 4096) + 224, f(n % 4096 / 64) + 128,
                           n % 64 + 128)
    elseif n <= 0x10ffff then
        return string.char(f(n / 262144) + 240, f(n % 262144 / 4096) + 128,
                           f(n % 4096 / 64) + 128, n % 64 + 128)
    end
    error(string.format("invalid unicode codepoint '%x'", n))
end

local function parse_unicode_escape(s)
    local n1 = tonumber(s:sub(3, 6), 16)
    local n2 = tonumber(s:sub(9, 12), 16)
    -- Surrogate pair?
    if n2 then
        return
            codepoint_to_utf8((n1 - 0xd800) * 0x400 + (n2 - 0xdc00) + 0x10000)
    else
        return codepoint_to_utf8(n1)
    end
end

local function parse_string(str, i)
    local has_unicode_escape = false
    local has_surrogate_escape = false
    local has_escape = false
    local last
    for j = i + 1, #str do
        local x = str:byte(j)

        if x < 32 then
            decode_error(str, j, "control character in string")
        end

        if last == 92 then -- "\\" (escape char)
            if x == 117 then -- "u" (unicode escape sequence)
                local hex = str:sub(j + 1, j + 5)
                if not hex:find("%x%x%x%x") then
                    decode_error(str, j, "invalid unicode escape in string")
                end
                if hex:find("^[dD][89aAbB]") then
                    has_surrogate_escape = true
                else
                    has_unicode_escape = true
                end
            else
                local c = string.char(x)
                if not escape_chars[c] then
                    decode_error(str, j,
                                 "invalid escape char '" .. c .. "' in string")
                end
                has_escape = true
            end
            last = nil

        elseif x == 34 then -- '"' (end of string)
            local s = str:sub(i + 1, j - 1)
            if has_surrogate_escape then
                s = s:gsub("\\u[dD][89aAbB]..\\u....", parse_unicode_escape)
            end
            if has_unicode_escape then
                s = s:gsub("\\u....", parse_unicode_escape)
            end
            if has_escape then s = s:gsub("\\.", escape_char_map_inv) end
            return s, j + 1

        else
            last = x
        end
    end
    decode_error(str, i, "expected closing quote for string")
end

local function parse_number(str, i)
    local x = next_char(str, i, delim_chars)
    local s = str:sub(i, x - 1)
    local n = tonumber(s)
    if not n then decode_error(str, i, "invalid number '" .. s .. "'") end
    return n, x
end

local function parse_literal(str, i)
    local x = next_char(str, i, delim_chars)
    local word = str:sub(i, x - 1)
    if not literals[word] then
        decode_error(str, i, "invalid literal '" .. word .. "'")
    end
    return literal_map[word], x
end

local function parse_array(str, i)
    local res = {}
    local n = 1
    i = i + 1
    while 1 do
        local x
        i = next_char(str, i, space_chars, true)
        -- Empty / end of array?
        if str:sub(i, i) == "]" then
            i = i + 1
            break
        end
        -- Read token
        x, i = parse(str, i)
        res[n] = x
        n = n + 1
        -- Next token
        i = next_char(str, i, space_chars, true)
        local chr = str:sub(i, i)
        i = i + 1
        if chr == "]" then break end
        if chr ~= "," then decode_error(str, i, "expected ']' or ','") end
    end
    return res, i
end

local function parse_object(str, i)
    local res = {}
    i = i + 1
    while 1 do
        local key, val
        i = next_char(str, i, space_chars, true)
        -- Empty / end of object?
        if str:sub(i, i) == "}" then
            i = i + 1
            break
        end
        -- Read key
        if str:sub(i, i) ~= '"' then
            decode_error(str, i, "expected string for key")
        end
        key, i = parse(str, i)
        -- Read ':' delimiter
        i = next_char(str, i, space_chars, true)
        if str:sub(i, i) ~= ":" then
            decode_error(str, i, "expected ':' after key")
        end
        i = next_char(str, i + 1, space_chars, true)
        -- Read value
        val, i = parse(str, i)
        -- Set
        res[key] = val
        -- Next token
        i = next_char(str, i, space_chars, true)
        local chr = str:sub(i, i)
        i = i + 1
        if chr == "}" then break end
        if chr ~= "," then decode_error(str, i, "expected '}' or ','") end
    end
    return res, i
end

local char_func_map = {
    ['"'] = parse_string,
    ["0"] = parse_number,
    ["1"] = parse_number,
    ["2"] = parse_number,
    ["3"] = parse_number,
    ["4"] = parse_number,
    ["5"] = parse_number,
    ["6"] = parse_number,
    ["7"] = parse_number,
    ["8"] = parse_number,
    ["9"] = parse_number,
    ["-"] = parse_number,
    ["t"] = parse_literal,
    ["f"] = parse_literal,
    ["n"] = parse_literal,
    ["["] = parse_array,
    ["{"] = parse_object
}

parse = function(str, idx)
    local chr = str:sub(idx, idx)
    local f = char_func_map[chr]
    if f then return f(str, idx) end
    decode_error(str, idx, "unexpected character '" .. chr .. "'")
end

function json.decode(str)
    if type(str) ~= "string" then
        error("expected argument of type string, got " .. type(str))
    end
    local res, idx = parse(str, next_char(str, 1, space_chars, true))
    idx = next_char(str, idx, space_chars, true)
    if idx <= #str then decode_error(str, idx, "trailing garbage") end
    return res
end

--[[
  This script creates a .ase file out of a packed texture atlas, SPECIFICALLY for TLCs head & body and eyes splitted animations.

  Credits:
    json decoding by rxi - https://github.com/rxi/json.lua
]]

-- start main

local function split(str, sep)
    local result = {}
    local regex = ("([^%s]+)"):format(sep)
    for each in str:gmatch(regex) do table.insert(result, each) end
    return result
end

-- src and dest are image classes
local function draw_section(src_img, dest_img, src_rect, dest_rect, palette)
    local frame = src_rect
    local source = dest_rect
    for y = 0, frame.h - 1, 1 do
        for x = 0, frame.w - 1, 1 do
            local src_x = frame.x + x
            local src_y = frame.y + y
            local color_or_index = src_img:getPixel(src_x, src_y)
            local color;
            if src_img.colorMode == ColorMode.INDEXED then
                -- fixes greenish artifacts when importing from an indexed file: https://discord.com/channels/324979738533822464/324979738533822464/975147445564604416
                -- because indexed sprites have a special index as the transparent color: https://www.aseprite.org/docs/color-mode/#indexed
                if color_or_index ~= src_img.spec.transparentColor then
                    color = palette:getColor(color_or_index)
                else
                    color = Color {r = 0, g = 0, b = 0, a = 0}
                end
            else
                color = color_or_index
            end
            -- DEPENDS ON THE COLOR MODE, MAKE SURE ITS NOT INDEXED, if indexed, grab the index coolor from the pallete, otherwise it is the color
            local dest_x = source.x + x
            local dest_y = source.y + y
            dest_img:drawPixel(dest_x, dest_y, color)
        end
    end
end
local function is_hand(str)
    return str == "melee" or str == "handgun" or str == "machineh" or str ==
               "shotgun" or str == "machinel" or str == "death" or str ==
               "corpse"
end

function append_tables(t1, t2)
    for i = 1, #t2 do t1[#t1 + 1] = t2[i] end
    return t1
end

local function build(filepath)

    local f = io.open(filepath, "r+"):read('a')
    local jsondata = json.decode(f)

    if jsondata == nil then
        print("could not load file " .. filepath)
        print("check your json file for errors")

        return 1
    end
    -- split head and body into 2 seperate layers
    -- NOTE: aseprite cannot deal with STACKED tags!
    local image = app.activeImage
    local sprite = app.activeSprite

    if sprite == nil then
        print("you are not viewing a sprite on the active tab")
        return 1
    end

    local palettes = sprite.palettes[1]
    local og_size = jsondata.frames[1].sourceSize
    local new_sprite = Sprite(og_size.w, og_size.h)

    new_sprite.filename = app.fs.fileTitle(filepath);
    new_sprite:setPalette(palettes)
    local body_layer = new_sprite.layers[1]
    -- important that head and body are named layers because they are used in the export

    body_layer.name = "body"
    local frame = new_sprite.frames[1]

    -- NOTE: This is not "human sort!" it will sort like: idle_s_0, idle_s_10, idle_s_2. 
    -- sorting will lead to bugs as stated above, anims with over 10 frames
    --[[ table.sort(jsondata.frames,
               function(a, b) return a.filename < b.filename end) ]]
    -- NOT STABLE SORT!
    --[[ table.sort(jsondata.frames, function(a, b)
        local split_a = split(a.filename, "_")
        local split_b = split(b.filename, "_")
        local state_a = split_a[3]
        local state_b = split_b[3]

        local framenum_a = tonumber(split_a[4])
        local framenum_b = tonumber(split_b[4])
        return state_a == state_b and framenum_a < framenum_b
    end) ]]

    -- group and pair up the animation frames, 1st gather all of the _0 frames
    -- Table<Table<AtlasFrame>>
    local all_grouped_anim_frames = {}
    for index, aframe in pairs(jsondata.frames) do
        local fname = aframe.filename
        local esdf = split(fname, "_")
        local ename = esdf[1]
        local state = esdf[2]
        local dir = esdf[3]
        local frame_num = tonumber(esdf[4])
        -- PUSH ONLY WHEN we encounter a 0
        if frame_num == 0 then
            local nested = {}
            table.insert(nested, aframe)
            table.insert(all_grouped_anim_frames, nested)
        end
    end

    -- group the rest of the frames
    for index, group in pairs(all_grouped_anim_frames) do
        local start_frame = group[1]
        local fname = start_frame.filename
        local esdf = split(fname, "_")
        local ename = esdf[1]
        local state = esdf[2]
        local dir = esdf[3]
        local frame_num = tonumber(esdf[4])
        for index2, aframe2 in pairs(jsondata.frames) do
            local fname2 = aframe2.filename
            local esdf2 = split(fname2, "_")
            local ename2 = esdf2[1]
            local state2 = esdf2[2]
            local dir2 = esdf2[3]
            local frame_num2 = tonumber(esdf2[4])
            if ename == ename2 and state == state2 and dir == dir2 and
                frame_num2 ~= 0 then
                -- print(fname2)
                table.insert(group, aframe2)
            end
        end
    end

    local head_layer = nil

    local eyes_layer = nil
    local legs_layer = nil

    -- String, Table<Table<AtlasFrame>> -> Table<Table<AtlasFrame>>
    -- also reoders to some parts to defer to the end
    function filter_by_body_part(bpart_name, grouped_frames)
        local anims = {}
        local defer = {}
        for index, group in ipairs(grouped_frames) do
            local start_frame = group[1]
            local fname = start_frame.filename
            local esdf = split(fname, "_")
            local ename = esdf[1]
            local state = esdf[2]
            local limb_name_parts = split(ename, "-")
            local limb_name = limb_name_parts[1]

            if limb_name == bpart_name and is_hand(state) then
                -- push into defered
                table.insert(defer, group)
            elseif limb_name == bpart_name then
                table.insert(anims, group)
            end
        end
        if #anims > 0 then append_tables(anims, defer) end
        return anims
    end

    -- Table<Table<AtlasFrame>>
    local bodies = filter_by_body_part("body", all_grouped_anim_frames)
    local heads = filter_by_body_part("head", all_grouped_anim_frames)

    -- if the atlas does not have body- or head- prefixes, we assume its the body and we proceed with base_anim to create all the frames and anim tags
    local base_anim = all_grouped_anim_frames

    if #bodies > #heads then
        base_anim = bodies
    elseif #heads > #bodies then
        base_anim = heads
    else
        base_anim = all_grouped_anim_frames
    end

    -- create all the frames first!
    for i, group in pairs(base_anim) do
        for j, aframe in pairs(group) do
            local newframe = new_sprite:newFrame()
            local fname = aframe.filename
            local esdf = split(fname, "_")
            local duration_from_name = tonumber(esdf[5])
            local curr_global_index = newframe.frameNumber - 1
            if duration_from_name ~= nil then
                new_sprite.frames[curr_global_index].duration =
                    duration_from_name / 1000
            else
                if aframe.duration ~= nil then
                    new_sprite.frames[curr_global_index].duration =
                        aframe.duration / 1000
                end
            end
        end
    end

    -- create the tags
    local anim_start_index = 1
    local anim_end_index = 1

    for index, group in pairs(base_anim) do
        local start_fname = group[1].filename
        local end_fname = group[#group].filename

        local fname = start_fname
        local esdf = split(fname, "_")
        local ename = esdf[1]
        local state = esdf[2]
        local dir = esdf[3]
        local frame_num = tonumber(esdf[4])

        local name_parts = split(ename, "-")
        local head_body_arms = name_parts[1]

        local esdf2 = split(end_fname, "_")
        local ename2 = esdf2[1]
        local state2 = esdf2[2]
        local dir2 = esdf2[3]
        local frame_num2 = tonumber(esdf2[4]) -- one off

        local anim_name = state .. "_" .. dir

        anim_end_index = anim_start_index + #group

        local new_tag = new_sprite:newTag(anim_start_index, anim_end_index - 1)
        new_tag.name = anim_name
        anim_start_index = anim_end_index
    end

    local eyes = filter_by_body_part("eyes", all_grouped_anim_frames)

    local legs = filter_by_body_part("legs", all_grouped_anim_frames)

    if #heads > 0 and head_layer == nil then
        head_layer = new_sprite:newLayer()
        head_layer.name = "head"
    end

    if #eyes > 0 and eyes_layer == nil then
        eyes_layer = new_sprite:newLayer()
        eyes_layer.name = "eyes"
    end

    if #legs > 0 and legs_layer == nil then
        legs_layer = new_sprite:newLayer()
        legs_layer.name = "legs"
    end
    -- tag, Table<Table<AFrame>>, layer
    function draw_into_tag(tag, grouped, draw_layer)
        for index_group, group in ipairs(grouped) do
            local fname = group[1].filename
            local esdf = split(fname, "_")
            local ename = esdf[1]
            local state = esdf[2]
            local dir = esdf[3]

            local anim_name = state .. "_" .. dir
            if tag.name == anim_name then
                local tag_index_start = tag.fromFrame.frameNumber
                for j, aframe in ipairs(group) do
                    local src_loc = aframe.frame
                    local place_loc = aframe.spriteSourceSize
                    local dest_img = new_sprite:newCel(draw_layer,
                                                       tag_index_start).image
                    draw_section(image, dest_img, src_loc, place_loc, palettes)
                    tag_index_start = tag_index_start + 1
                end
            end
        end
    end

    for i, tag in ipairs(new_sprite.tags) do
        if body_layer ~= nil then draw_into_tag(tag, bodies, body_layer) end
        if head_layer ~= nil then draw_into_tag(tag, heads, head_layer) end
        if eyes_layer ~= nil then draw_into_tag(tag, eyes, eyes_layer) end
        if legs_layer ~= nil then draw_into_tag(tag, legs, legs_layer) end

        if #heads == 0 and #bodies == 0 and #eyes == 0 then
            -- draw everything
            draw_into_tag(tag, all_grouped_anim_frames, body_layer)
        end
    end

    -- delete the extra empty frame
    new_sprite:deleteFrame(#new_sprite.frames)

    -- SHOULD FIX BAD CROP REGIONS https://github.com/aseprite/aseprite/issues/3206#issuecomment-1069508834
    app.command.CanvasSize {
        ui = false,
        left = 0,
        top = 0,
        right = 0,
        bottom = 0,
        trimOutside = true
    }
    -- creating a new frame creates a cel but we dont need any for the body if we are creating arm frames
end

local JKEY = "json"
local PICKER = "picker"
local from_cli_json_path = app.params[JKEY]
if from_cli_json_path ~= nil then
    build(from_cli_json_path)

    -- filename must also have extension
    local name = app.fs.filePathAndTitle(from_cli_json_path) .. ".ase"

    app.command.saveFileAs {["filename"] = name, ["filename-format"] = ".ase"}
    -- switch the created sprite to the active tab
else
    local sprite = app.activeSprite;
    if sprite == nil then
        print("you are not viewing a sprite on the active tab")
        return 1
    end
    local dlg = Dialog()

    -- tries to guess that the png & json are in the same directory
    local json_filepath = app.fs.filePathAndTitle(sprite.filename) .. ".json"
    local exists_in_same_dir = app.fs.isFile(json_filepath)
    if exists_in_same_dir == false then
        json_filepath = "" -- not in same dir, look for it yourself
    end

    dlg:file{
        id = PICKER,
        label = "select animation data file(json)",
        title = "animimation tag importer",
        load = true,
        open = true,
        filename = json_filepath,
        filetypes = {"json"}
    }:button{
        id = "Ok",
        text = "Ok",
        onclick = function()
            local filepath = dlg.data[PICKER] -- matches id name

            build(filepath)
            dlg:close()
        end
    }:show()
end
