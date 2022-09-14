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

This script takes a TLC human skin and turns it into a zombie
It will prompt for you to select skin tones but will try automatically to guess

]] -- operates on atlased and json files!

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

-- Table<Tag> -> Tag | nil
local function get_tag(tbl, search_name)
    local res = nil
    for _, tag in ipairs(tbl) do
        if tag.name == search_name then
            res = tag
            break
        end
    end
    return res
end

-- tag, Table<Table<AFrame>>, layer
local function draw_into_tag(tag, grouped, draw_layer, new_sprite, source_img,
                             palettes)
    for index_group, group in ipairs(grouped) do
        local fname = group[1].filename
        local esdf = split(fname, "_")
        local ename = esdf[1]
        local state = esdf[2]
        local dir = esdf[3]

        local anim_name = state .. "_" .. dir
        -- local matches = tag.name == anim_name
        local matches = string.match(tag.name, anim_name)
        -- print(anim_name, tag.name, matches)
        if matches then
            local tag_index_start = tag.fromFrame.frameNumber
            for j, aframe in ipairs(group) do
                -- for the d2 state, there are only 3 frames of walk so we should only go up to that amount
                if j <= #group then
                    local src_loc = aframe.frame
                    local place_loc = aframe.spriteSourceSize
                    local dest_img = new_sprite:newCel(draw_layer,
                                                       tag_index_start).image
                    draw_section(source_img, dest_img, src_loc, place_loc,
                                 palettes)
                    tag_index_start = tag_index_start + 1
                end
            end
        end
    end
end

-- select the zombie base sprite
local dlg = Dialog()

local PICKER = "picker"
local PACKED = "select packed PNG"
local AJSON = "select json file"
local zbase = nil;

-- todo: sort the skin colors and detect duplicates?
-- assume white and have a button option that says "try based off position?"

-- we don't really care about eye colors
-- still need to find out what the arm colors are?
-- we can replace with a tolerance of 3
local white_tones = {
    -- Color {r = 192, g = 192, b = 192, a = 255},
    -- Color {r = 245, g = 245, b = 240, a = 255},
    -- Color {r = 255, g = 204, b = 51, a = 255},
    Color {r = 180, g = 125, b = 50, a = 255},
    Color {r = 213, g = 164, b = 98, a = 255},
    Color {r = 255, g = 215, b = 165, a = 255},
    Color {r = 245, g = 190, b = 125, a = 255}
}

local zombie_tones = {
    -- Color {r = 140, g = 140, b = 140, a = 255},
    -- Color {r = 155, g = 155, b = 155, a = 255},
    -- Color {r = 140, g = 140, b = 140, a = 255},
    Color {r = 75, g = 70, b = 60, a = 255},
    Color {r = 75, g = 70, b = 60, a = 255},
    Color {r = 115, g = 110, b = 95, a = 255},
    Color {r = 100, g = 90, b = 80, a = 255}
}

local skin_colors = white_tones;
-- include the zed base ase with the game and hardcode a path to it, see if it exsts, if not you have to select it yourself
local zbase_ase_path = "/mnt/shared/t0-assets/zeds/ase/ZBASE-NEW-SUITE.ase"

local infered_json_filename = nil
dlg:file{
    id = PICKER,
    label = "Select the zombie base icon",
    title = "zed base picker",
    load = false,
    open = false,
    filename = zbase_ase_path,
    filetypes = {"ase"}
}:file{
    id = PACKED,
    label = PACKED,
    filetypes = {"png"},
    open = true,
    load = false,
    onchange = function()
        local png_path = dlg.data[PACKED];
        infered_json_filename = app.fs.joinPath(app.fs.filePath(png_path),
                                                app.fs.fileTitle(png_path) ..
                                                    ".json")
        dlg:modify{id = AJSON, filename = infered_json_filename}
        -- weirdly still not effecting the file json default
        -- print(infered_json_filename)
    end
}:file{
    id = AJSON,
    label = AJSON,
    filename = infered_json_filename,
    filetypes = {"json"},
    open = true,
    load = false
}

-- todo: button that asks if we want to try and determine this off hard coded face positions?

for i = 1, #white_tones, 1 do
    local SCOL = "Skin Color " .. i;
    dlg:color{
        id = SCOL,
        label = SCOL,
        color = white_tones[i],
        onchange = function() skin_colors[i] = dlg.data[SCOL] end
    }
end

local packed_png = nil
local jsondata = nil
dlg:button{
    text = "Ok",
    onclick = function()
        local zbasefile = dlg.data[PICKER]
        local human_packed_png = dlg.data[PACKED]
        local json_path = dlg.data[AJSON]
        app.command.OpenFile {filename = human_packed_png};
        -- this must be the active image right after we open it!
        packed_png = app.activeImage
        jsondata = json.decode(io.open(json_path, "r+"):read("a"));
        zbase = Sprite {fromFile = zbasefile}
        dlg:close()
    end
}:show()

if zbase ~= nil then

    -- create new layers of body and head
    -- also we gotta split the legs
    -- grab walk animations, 2 and 3 only(so south and north in the zbase have all the walk anim legs, so we will just copy all the walk frames over to walk)

    local head_layer = zbase:newLayer()
    local HEAD = "head"
    head_layer.name = HEAD

    local body_layer = zbase:newLayer()
    local BODY = "body"
    body_layer.name = BODY

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

    -- String, Table<Table<AtlasFrame>> -> Table<Table<AtlasFrame>>
    -- also reoders to some parts to defer to the end
    function filter_by_body_part(bpart_name, grouped_frames)
        function append_tables(t1, t2)
            for i = 1, #t2 do t1[#t1 + 1] = t2[i] end
            return t1
        end
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

            if limb_name == bpart_name then
                table.insert(anims, group)
            end
        end
        if #anims > 0 then append_tables(anims, defer) end
        return anims
    end

    local walk_tags = {
        "walk_e", "walk_n", "walk_s", "walk_w", "d1-walk_e", "d1-walk_n",
        "d1-walk_s", "d1-walk_w", "d2-walk_e", "d2-walk_n", "d2-walk_s",
        "d2-walk_w"
    };

    local heads = filter_by_body_part("head", all_grouped_anim_frames)

    local bodies = filter_by_body_part("body", all_grouped_anim_frames)

    for _, tag_name in ipairs(walk_tags) do
        local tag = get_tag(zbase.tags, tag_name)
        draw_into_tag(tag, heads, head_layer, zbase, packed_png, nil)
        draw_into_tag(tag, bodies, body_layer, zbase, packed_png, nil)
    end

    local range_sel = app.range
    range_sel.layers = {body_layer, head_layer}

    for i, tone in ipairs(white_tones) do
        local ztone = zombie_tones[i]
        -- select all the frames?

        -- tolerance has to be 5+? or it wont work on brandi
        local tol = 5
        app.command.ReplaceColor {
            ui = false,
            -- channels = FilterChannels.RGBA | FilterChannels.INDEX,
            from = tone,
            to = ztone,
            tolerance = tol
        }
    end

    -- d1 shift head 8 down
    local d1s = {"d1-walk_e", "d1-walk_n", "d1-walk_s", "d1-walk_w"}
    -- print(range_sel.frames)
    local ls = {}
    for i, tname in ipairs(d1s) do
        -- need to select only relevant frames
        local tag = get_tag(zbase.tags, tname)
        local start = tag.fromFrame.frameNumber
        local to = tag.toFrame.frameNumber

        for j = start, to, 1 do 
            local hcel = head_layer:cel(j)
            local bcel = body_layer:cel(j)
            if hcel ~= nil or bcel ~= nil then 
                local pos = hcel.position
                pos.y = pos.y + 8
                hcel.position = pos

                local bpos = bcel.position
                bpos.y = bpos.y + 8
                bcel.position = bpos
            end
        end
    end

    -- TODO: we can mask the body of onto d1 body

    -- reorganize layers to be 1 down
    -- print(head_layer.stackIndex)
    head_layer.stackIndex = 4
    body_layer.stackIndex = 5

    -- SHOULD FIX BAD CROP REGIONS https://github.com/aseprite/aseprite/issues/3206#issuecomment-1069508834
    app.command.CanvasSize {
        ui = false,
        left = 0,
        top = 0,
        right = 0,
        bottom = 0,
        trimOutside = true
    }
    -- close the opened packed image tab
end

-- select your skin tones (will try to auto select if white skinned because it is the most common)
-- eyes are by position though?

-- position the heads and body correctly for all the dismemberment states also

-- no need to do eyes, it is optional becuase we have a ton of eyes! Zed should be faceless?

