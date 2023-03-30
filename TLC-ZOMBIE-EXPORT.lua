--[[ TLC ZOMBIE EXPORT

THIS SCRIPT RENAMES TAGS FOR EXPORT BECAUSE
head-zed-armored-m-0_walk_w_3_400
head-zed-armored-m-0_d1_walk_e_0_400
                    ^ INCOMPATABLE HERE
needs to be "-d1" because dismemberment(d1) needs to be part of the entity name
while "-walk" is wrong, so we need to change the tag names to add explict seperators for export, then revert them

AND ALSO MERGES BLEGS & BBODY! DO NOT SAVE THE RESULTING FILE IF YOU WANT TO PRESERVE KEEPING CLOTHES ON A SEPERATE LAYER

NOTE: THIS SCRIPT REQUIRES THE LAYERS TO BE IN THE FOLLOWING ORDER(FROM TOP TO BOTTOM)
-- TODO: re-arrange these like so, so that we dont have to think about it
eyes
head
body
legs
base
    -bhead
    -bbody
    -blegs
]] 
local sprite = app.activeSprite
local layers = sprite.layers

-- returns tag or nil
function get_tag(ls, name)
    local res = nil
    for _, t in ipairs(ls) do if t.name == name then res = t end end
    if res == nil then print("WARNING! COULD NOT FIND TAG" .. name) end
    return res
end

local function merge_body_legs()
    -- NOTE: We delete death anims because of dismem and them being more dynamic! ONLY RUN THIS ON ZEDS THAT DON'T HAVE A DEATH ANIM
    local deaths = {
        get_tag(sprite.tags, "death_s"),
        get_tag(sprite.tags, "death_n"),
        get_tag(sprite.tags, "death_w"),
        get_tag(sprite.tags, "death_e")
    }
    for _, tag in ipairs(deaths) do 
        if tag ~= nil then
            local curr_frame = tag.fromFrame
            sprite:deleteFrame(curr_frame)
            -- print(curr_frame, to_frame)
            --print(tag.name)
        end
    end

    -- make the base zed grouped layers visible except for bhead
    for _, layer in ipairs(layers) do
        if layer.isGroup then
            local nested = layer.layers
            if nested ~= nil then
                for _, l2 in ipairs(nested) do
                    if l2.name == "bbody" then
                        l2.isVisible = true
                    elseif l2.name == "blegs" then
                        l2.isVisible = true
                    elseif l2.name == "bhead" then
                        l2.isVisible = false 
                    end
                    -- print(l2.name, "nested") 
                    if l2.name ~= "bhead" then
                        l2.parent = sprite -- move it out of the group except bhead
                    end
                end
            end
        end
    end

    -- NOTE: use sprite.layers opposed to layers variable because it makes a clone for some reason?
    for _, layer in ipairs(sprite.layers) do
        -- print(layer.name, layer.stackIndex) 
        local lname = layer.name
        if lname == "blegs" then
            layer.stackIndex = 2
        elseif lname == "bbody" then
            layer.stackIndex = 4
        end
    end
    -- NOTE: previous layer means down, next means up?
    local function get_layer(name) 
        local res = nil;
        for i, layer in ipairs(sprite.layers) do 
            if layer.name == name then 
                res = layer
                break
            end
        end
        return res
    end
    local get_bod = get_layer("body")
    if get_bod ~= nil then 
        app.activeLayer = get_bod
        app.command.MergeDownLayer()
    end
    app.activeLayer.name = "body"

    local get_legs = get_layer("legs")
    if get_legs ~= nil then 
        app.activeLayer = get_legs
        app.command.MergeDownLayer()
        app.activeLayer.name = "legs"   
    end
    -- change blegs to legs because it was merged

end
merge_body_legs()

for i,tag in ipairs(sprite.tags) do
    local tagname = tag.name

    if string.find(tagname, "d1") or string.find(tagname, "d2") then 
        tag.name = "-" .. tagname
    else
        tag.name = "_" .. tagname
    end
end

-- export, popup the file picker to prompt merging of conesutive frames and printing of debug?
-- https://github.com/aseprite/api/blob/main/api/command/ExportSpriteSheet.md#exportspritesheet

local filename = sprite.filename

-- local name_without_ext = filename:sub(1, -5)
local name_without_ext = app.fs.fileTitle(filename)
-- make sure name has no underscore
local normalize_name = string.gsub(name_without_ext, "_", "-")
local format_name = "{layer}-" .. normalize_name .. "{tag}_{tagframe}_{duration}"
-- local format_name = normalize_name .. "{tag}_{tagframe}_{duration}"
--print(format_name)
app.command.ExportSpriteSheet {
    ui = false,
    askOverwrite = true,
    type = SpriteSheetType.PACKED,
    columns = 0,
    rows = 0,
    width = 0,
    height = 0,
    bestFit = true, -- no idea what this does
    textureFilename = normalize_name .. ".png",
    dataFilename = normalize_name .. ".json",
    dataFormat = SpriteSheetDataFormat.JSON_ARRAY,
    borderPadding = 0,
    shapePadding = 1,
    innerPadding = 0,
    trim = true,
    trimSprite = true,
    ignoreEmpty = true,
    filenameFormat = format_name, --[[ e.g: body-jeff_walk_0_100 ]]
    extrude = false,
    openGenerated = false,
    layer = "",
    tag = "",
    splitLayers = true,
    listLayers = false,
    listTags = false,
    listSlices = false
}