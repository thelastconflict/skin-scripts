--[[ TLC Export v1 

This script scans animations and removes/combines CONSECUTIVE duplicates!

]] -- NOTE: The head AND body need to be exactly the same pixels in order for it to be considered duplicate WITHIN the same tag context
-- TODO: check average frame area for head and body and warn that there may be head pixels in the body
local sprite = app.activeSprite
local layers = sprite.layers

local head_layer = layers[1]
local body_layer = layers[2]

local all_tag_names = {}

-- idle animations are optional and will default to blink if not found in game
local all_human_anim_names = {
    "drawn_e", "drawn_n", "drawn_s", "drawn_w", "hurtwalk_e", "hurtwalk_n",
    "hurtwalk_s", "hurtwalk_w", --[[ "idle_e", "idle_n", "idle_s", "idle_w", ]] "run_e",
    "run_n", "run_s", "run_w", "sleep_e", "sleep_n", "sleep_s", "sleep_w",
    "walk_e", "walk_n", "walk_s", "walk_w", "hurtidle_e", "hurtidle_n",
    "hurtidle_s", "hurtidle_w", "tiredidle_e", "tiredidle_n", "tiredidle_s",
    "tiredidle_w", "melee_e", "handgun_e", "machineh_e",
    "shotgun_e", "wink_e", "wink_s", "wink_w", "wink_n", "blink_e", "blink_s", "blink_w", "blink_n"
}

for _, layer in ipairs(layers) do 
    if layer.name == "head" then 
        head_layer = layer;
    elseif layer.name == "body" then 
        body_layer = layer;
    end
end

local everything_is_good = true 

if #layers > 2 then 
    everything_is_good = false

    for _, layer in ipairs(layers) do 
        local is_head = layer.name == "head"
        local is_body = layer.name == "body"
        local is_eyes = layer.name == "eyes"
        local is_legs = layer.name == "legs"
        if (is_head or is_body or is_eyes or is_legs) == false then 
            print("!!!CRITICAL!!!: PLEASE MARK " .. layer.name .. " AS INVISIBLE")
        end
    end
end

-- Stores (index, image)
local unique_heads = {}
local unique_bodies = {}

local IMG = "img"
local INDEX = "index"
local NAME = "name"

function add_unique(ls, compare, frame_index, anim_name)
    local is_unique = true
    for index, test in ipairs(ls) do
        if compare:isEqual(test[IMG]) then
            is_unique = false
            break
        end
    end

    if is_unique then
        local new_entry = {}
        new_entry[IMG] = compare
        new_entry[INDEX] = frame_index
        new_entry[NAME] = anim_name
        ls[#ls + 1] = new_entry
    end
end

for i, tag in ipairs(sprite.tags) do
    local name = tag.name
    all_tag_names[#all_tag_names + 1] = name
    local frames = tag.frames
    local start_index = tag.fromFrame.frameNumber
    local end_index = tag.toFrame.frameNumber
    local tsprite = tag.sprite

    -- print(name, start_index, end_index)

    for frame_index = start_index, end_index do
        local head_cel = head_layer:cel(frame_index)
        local body_cel = body_layer:cel(frame_index)

        -- 20x15 for the head
        -- 21x19 for the body
        local warn_head_w = 20
        local warn_head_h = 15

        local warn_body_w = 21
        local warn_body_h = 19

        local next_index = frame_index + 1
        if next_index > end_index then next_index = nil end

        if head_cel ~= nil and body_cel ~= nil then
            -- print(head_cel.bounds)
            -- print(body_cel.bounds)
            -- WARNS POTENTIALLY THAT THERE MIGHT BE MISPLACED PIXELS IN LAYERS, NOTE THIS IS SOMEWHAT BUGGED BECASUE OF ASEPRITE
            -- https://github.com/aseprite/aseprite/issues/3206
            -- FOR NOW JUST CHECK THE RESULTING OUTPUT TEXTURE
            -- checks if less than 32 because of bugged bounds ^
            local is_head_wide = head_cel.bounds.width > warn_head_w and head_cel.bounds.width < 32
            local is_head_tall = head_cel.bounds.height > warn_head_h and head_cel.bounds.height < 32
            local is_body_wide = body_cel.bounds.width > warn_body_w and body_cel.bounds.width < 32
            local is_body_tall = body_cel.bounds.height > warn_body_h and body_cel.bounds.height < 32

     --[[        print(" head " .. head_cel.bounds.width .. " h " ..
                      head_cel.bounds.height)
            print(" body " .. body_cel.bounds.width .. " h " ..
                      body_cel.bounds.height) ]]
            if is_head_wide or is_head_tall then
                print(
                    "!!!CHECK!!! : Are you sure there arent any misplaced pixels at LAYER " ..
                        "HEAD '" .. name .. "' #" .. frame_index)
            end
            if is_body_wide or is_body_tall then
                print(
                    "!!!CHECK!!!: Are you sure there arent any misplaced pixels at LAYER " ..
                        "BODY '" .. name .. "' #" .. frame_index)
            end

            local h_img = head_cel.image
            local b_img = body_cel.image
            if next_index ~= nil then
                local next_h_cel = head_layer:cel(next_index)
                local next_b_cel = body_layer:cel(next_index)
                local next_h_img = next_h_cel.image
                local next_b_img = next_b_cel.image

                -- THIS SEEMS TO COMPARE THEM TRIMMED :D!
                local is_head_eq = h_img:isEqual(next_h_img)
                local is_body_eq = b_img:isEqual(next_b_img)

                -- print(name, frame_index, next_index, "head ", is_head_eq, "body ", is_body_eq)
                if is_head_eq and is_body_eq then
                    everything_is_good = false
                    print(
                        "!!OPTIMIZE!! '" .. name .. "' " .. frame_index .. " to " ..
                            next_index ..
                            " are the same and can be merged into 1 frame with the combined duration!")
                end
                --[[ if is_body_eq == false then
                    print(b_img.spec.colorMode, next_b_img.spec.colorMode)
                    print(b_img.spec.width, next_b_img.spec.width)
                    print(b_img.spec.height, next_b_img.spec.height)
                    print(b_img.spec.transparentColor, next_b_img.spec.transparentColor)
                end ]]
            end

            add_unique(unique_heads, h_img, frame_index, name)
            add_unique(unique_bodies, b_img, frame_index, name)
        end
        -- print(tsprite)
    end
    -- print(name, start_index, end_index, tsprite, frames)
end

function print_uniques(ls, h_or_b)
    for i, item in ipairs(ls) do
        print(h_or_b .. " " .. item[NAME] .. " index " .. item[INDEX])
    end
end

table.sort(all_human_anim_names)
table.sort(all_tag_names)

-- check to see if there are any missing animations
for index, item in ipairs(all_human_anim_names) do
    local is_missing = true
    for _, j in ipairs(all_tag_names) do
        if j == item then
            is_missing = false
            break
        end
    end
    if is_missing then
        everything_is_good = false
        print("!!!CRITICAL WARNING!!!: The animation " .. item .. " IS MISSING")
    end
end

if everything_is_good then 
    print("WOOO! EVERYTHING IS GOOD :)")
end

print("===STATS===")

print("==UNIQUIE HEADS==")
print_uniques(unique_heads, "unique head")

print("==UNIQUIE BODIES==")
print_uniques(unique_bodies, "unique body")

-- NOTE!: NOT ENTIRELY ACCURATE, CHECK OUTPUT TEXTURE, ITS PROBABLY AN ASEPRITE BUG?
print("Total Unique heads: " .. #unique_heads .. " (average is less than 15)")
print("Total Unique bodys: " .. #unique_bodies .. " (average is less than 60)")
print("Combined " .. #unique_bodies + #unique_bodies)

-- export, popup the file picker to prompt merging of conesutive frames and printing of debug?
-- https://github.com/aseprite/api/blob/main/api/command/ExportSpriteSheet.md#exportspritesheet

local filename = sprite.filename

local name_without_ext = filename:sub(1, -5)

app.command.ExportSpriteSheet {
  ui=true,
  askOverwrite=true,
  type=SpriteSheetType.PACKED,
  columns=0,
  rows=0,
  width=0,
  height=0,
  bestFit=true, -- no idea what this does
  textureFilename=name_without_ext.. ".png",
  dataFilename=name_without_ext.. ".json",
  dataFormat=SpriteSheetDataFormat.JSON_ARRAY,
  borderPadding=0,
  shapePadding=2,
  innerPadding=0,
  trim=true,
  trimSprite=true,
  ignoreEmpty=true,
  filenameFormat="{layer}-{title}_{tag}_{tagframe}_{duration}", --[[ e.g: body-jeff_walk_0_100 ]]
  extrude=false,
  openGenerated=false,
  layer="",
  tag="",
  splitLayers=true,
  listLayers=false,
  listTags=false,
  listSlices=false
}