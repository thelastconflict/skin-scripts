--[[ 
    NOTE!! ASEPRITE COUNTS LAYERS FROM BOTTOM TO TOP, BOTTOM MOST LAYER HAS INDEX OF 1
TODO: option to spread all the blink heads to a layer of choice while automatically positioning them based off top left corner
    - spread the one eyes to tiredidle, hurtwalk, hurtidle
TODO: option to spread all the walk bodies to a layer of choice while automatically positioning them based off BOTTOM RIGHT CORNER?
]] local sprite = app.activeSprite
local layers = sprite.layers

local dlg = Dialog()

local layer_names = {}

for i, layer in ipairs(layers) do
    table.insert(layer_names, i, layer.name)
    -- print(i, layer.name)
end

function get_layer_index(ls, name)
    local res = nil
    for i, layer in ipairs(ls) do
        if layer.name == name then
            res = i
            break
        end
    end
    if res == nil then print("WARNING! COULD NOT FIND LAYER" .. name) end
    return res
end

-- returns tag or nil
function get_tag(ls, name)
    local res = nil
    for i, t in ipairs(ls) do if t.name == name then res = t end end
    if res == nil then print("WARNING! COULD NOT FIND TAG" .. name) end
    return res
end

-- list of tags, tagname -> list<cels>
function get_cels_by_tag(ls, name, layer)
    local res = {}
    local tag = get_tag(ls, name)
    local from_frame = tag.fromFrame.frameNumber
    local to_frame = tag.toFrame.frameNumber
    for index = from_frame, to_frame do
        local cel = layer:cel(index)
        table.insert(res, cel)
    end
    return res
end

-- layer, number, number, layer, list<cel>
-- if 1 cel copy is provided, it will be spread accross all.
function pastey(to_layer, tagname, existing_layer, copies, match_bottom)
    local tag = get_tag(sprite.tags, tagname)
    
    local from_frame = tag.fromFrame.frameNumber
    local to_frame = tag.toFrame.frameNumber

    local count = 1
    for index = from_frame, to_frame do
        local to_cel = existing_layer:cel(index)
        local copy = copies[count]

        local to_cel_bottom_y = to_cel.position.y + to_cel.bounds.height 
        local copy_cel_bottom_y = copy.position.y + copy.bounds.height
        
        -- MATCH THE BOTTOM MOST PIXELS WITH EACH OTHER! SO THEY LINE UP
        local y_offset = (to_cel_bottom_y - copy_cel_bottom_y)
        local position = to_cel.position -- has to be to cel for the head to easily line up, match bottom is for
        if match_bottom then 
            position = copy.position
            position.y = position.y + y_offset
        end
        --[[ print(tagname, to_cel.position, to_cel.image.height,
              to_cel.bounds.height, y_offset) ]]
        if to_cel ~= nil then
            to_layer.sprite:newCel(to_layer, index, copy.image,
                                   position)
            count = count + 1
            if count > #copies then
                -- if only provided 1 copy, then spread that accross
                count = 1
            end
        end
    end
end

local HEAD_LAYER_INDEX = get_layer_index(layers, "head")
local BODY_LAYER_INDEX = get_layer_index(layers, "body")

local HEAD_PASTE_SELECT = "BLINK SPREAD HEAD LAYER PASTE SELECT"
local head_paste_index = #layers --get_layer_index(layers, "head")
local HEAD_PASTE_CONFIRM = "HEAD_PASTE_CONFIRM"
local BODY_PASTE_SELECT = "WALK SPREAD BODY LAYER PASTE SELECT"
local body_paste_index = #layers -- get_layer_index(layers, "body")
local BODY_PASTE_CONFIRM = "BODY_PASTE_CONFIRM"

local default = layers[#layers].name -- the top most layer
dlg:combobox{
    id = HEAD_PASTE_SELECT,
    label = HEAD_PASTE_SELECT,
    option=default,
    options = layer_names,
    onchange = function()
        local lname = dlg.data[HEAD_PASTE_SELECT]
        head_paste_index = get_layer_index(layers, lname)
    end
}:button{
    id = HEAD_PASTE_CONFIRM,
    label = "",
    text = "paste",
    onclick = function()
        local hlayer = layers[HEAD_LAYER_INDEX]
        local eyes_full_cel_e = hlayer:cel(1)
        local eyes_part_cel_e = hlayer:cel(2)
        local eyes_closed_cel_e = hlayer:cel(3)

        local eyes_full_cel_s = hlayer:cel(7)
        local eyes_part_cel_s = hlayer:cel(8)
        local eyes_closed_cel_s = hlayer:cel(9)

        local eyes_full_cel_w = hlayer:cel(12)
        local eyes_part_cel_w = hlayer:cel(13)
        local eyes_closed_cel_w = hlayer:cel(14)

        local eyes_closed_cel_n = hlayer:cel(6)

        -- NEED TO PASTE FROM MATCHING BOTTOMS, NEED TO OFFSET Y
        local to_layer = layers[head_paste_index]
        pastey(to_layer, "hurtidle_e", hlayer,
               {eyes_part_cel_e, eyes_closed_cel_e}, false)
        pastey(to_layer, "hurtidle_s", hlayer,
               {eyes_part_cel_s, eyes_closed_cel_s}, false)
        pastey(to_layer, "hurtidle_w", hlayer,
               {eyes_part_cel_w, eyes_closed_cel_w}, false)
        pastey(to_layer, "hurtidle_n", hlayer, {eyes_closed_cel_n}, false)

        pastey(to_layer, "hurtwalk_e", hlayer, {eyes_part_cel_e}, false)
        pastey(to_layer, "hurtwalk_w", hlayer, {eyes_part_cel_w}, false)
        pastey(to_layer, "hurtwalk_n", hlayer, {eyes_closed_cel_n}, false)
        pastey(to_layer, "hurtwalk_s", hlayer, {eyes_part_cel_s}, false)

        --[[ pastey(to_layer, "run_e", hlayer, {eyes_full_cel_e}, false)
        pastey(to_layer, "run_w", hlayer, {eyes_full_cel_w}, false)
        pastey(to_layer, "run_n", hlayer, {eyes_closed_cel_n}, false)
        pastey(to_layer, "run_s", hlayer, {eyes_full_cel_s}, false) ]]

        pastey(to_layer, "sit_e", hlayer, {eyes_full_cel_e, eyes_part_cel_e, eyes_closed_cel_e}, false)
        pastey(to_layer, "sit_n", hlayer, {eyes_full_cel_e}, false)
        pastey(to_layer, "sit_s", hlayer, {eyes_full_cel_s, eyes_part_cel_s, eyes_closed_cel_s}, false)
        pastey(to_layer, "sit_w", hlayer, {eyes_full_cel_w, eyes_part_cel_w, eyes_closed_cel_w}, false)

        pastey(to_layer, "sleep_e", hlayer, {eyes_closed_cel_e}, false)
        pastey(to_layer, "sleep_w", hlayer, {eyes_closed_cel_w}, false)
        pastey(to_layer, "sleep_n", hlayer, {eyes_closed_cel_n}, false)
        pastey(to_layer, "sleep_s", hlayer, {eyes_closed_cel_s}, false)

        -- tired idle does not blink, eyes lowered but body bobs
        pastey(to_layer, "tiredidle_e", hlayer, {eyes_part_cel_e}, false)
        pastey(to_layer, "tiredidle_s", hlayer, {eyes_part_cel_s}, false)
        pastey(to_layer, "tiredidle_w", hlayer, {eyes_part_cel_w}, false)
        pastey(to_layer, "tiredidle_n", hlayer, {eyes_closed_cel_n}, false)

        pastey(to_layer, "walk_e", hlayer, {eyes_full_cel_e}, false)
        pastey(to_layer, "walk_w", hlayer, {eyes_full_cel_w}, false)
        pastey(to_layer, "walk_n", hlayer, {eyes_closed_cel_n}, false)
        pastey(to_layer, "walk_s", hlayer, {eyes_full_cel_s}, false)

        --[[ pastey(to_layer, "wink_e", hlayer, {eyes_closed_cel_e}, false)
        pastey(to_layer, "wink_w", hlayer, {eyes_closed_cel_w}, false)
        pastey(to_layer, "wink_n", hlayer, {eyes_closed_cel_n}, false) ]]
        pastey(to_layer, "wink_s", hlayer, {eyes_full_cel_s, eyes_full_cel_s, eyes_full_cel_s}, false)

        pastey(to_layer, "down_n", hlayer, {eyes_closed_cel_n}, false)
        pastey(to_layer, "drawn_e", hlayer, {eyes_full_cel_e}, false)
        pastey(to_layer, "drawn_w", hlayer, {eyes_full_cel_w}, false)
        pastey(to_layer, "drawn_n", hlayer, {eyes_closed_cel_n}, false)
        pastey(to_layer, "drawn_s", hlayer, {eyes_full_cel_s}, false)
        -- WE DONT DO IDLE BECAUSE ITS AN EASY COPY PASTE OF BLINK AND WE CANNOT ASSUME THE LENGTH OF IDLE IS THAT OF BLINK
        -- SKIPPING DRAWN ALSO
    end
}:combobox{
    id = BODY_PASTE_SELECT,
    label = BODY_PASTE_SELECT,
    option=default,
    options = layer_names,
    onchange = function()
        local lname = dlg.data[BODY_PASTE_SELECT]
        body_paste_index = get_layer_index(layers, lname)
    end
}:button{
    id = BODY_PASTE_CONFIRM,
    label = "",
    text = "paste",
    onclick = function()
        local blayer = layers[BODY_LAYER_INDEX]
        local to_layer = layers[body_paste_index]
        -- print(body_paste_index)
        -- todo: paste bodies from walk

        -- WE HAVE TO GET THE WALK FRAMES BECAUSE WE DONT KNOW WHERE THEY MIGHT BE DUE TO IDLE BEING ARBITRARILY LONG
        -- CANNOT ASSUME THE 2 STILLS ARE THE SAME! BECAUSE SOME SKINS MIGHT HAVE SOMETHING ON THE CHARACTER THAT MOVES WITH THE BODY
        local walk_e_cels = get_cels_by_tag(sprite.tags, "walk_e", blayer)
        local leg_spread_e = walk_e_cels[1]
        local leg_still_e1 = walk_e_cels[2]
        local leg_close_e = walk_e_cels[3]
        local leg_still_e2 = walk_e_cels[4]

        --pastey(to_layer, "run_e", blayer, walk_e_cels, true)

        local walk_n_cels = get_cels_by_tag(sprite.tags, "walk_n", blayer)
        local leg_spread_n = walk_n_cels[1]
        local leg_still_n1 = walk_n_cels[2]
        local leg_close_n = walk_n_cels[3]
        local leg_still_n2 = walk_n_cels[4]

        --pastey(to_layer, "run_n", blayer, walk_n_cels, true)

        local walk_s_cels = get_cels_by_tag(sprite.tags, "walk_s", blayer)
        local leg_spread_s = walk_s_cels[1]
        local leg_still_s1 = walk_s_cels[2]
        local leg_close_s = walk_s_cels[3]
        local leg_still_s2 = walk_s_cels[4]
        --pastey(to_layer, "run_s", blayer, walk_s_cels, true)

        local walk_w_cels = get_cels_by_tag(sprite.tags, "walk_w", blayer)
        local leg_spread_w = walk_w_cels[1]
        local leg_still_w1 = walk_w_cels[2]
        local leg_close_w = walk_w_cels[3]
        local leg_still_w2 = walk_w_cels[4]

        -- pastey(to_layer, "run_w", blayer, walk_w_cels, true)

        pastey(to_layer, "blink_e", blayer, {leg_still_e1}, true)
        pastey(to_layer, "blink_n", blayer, {leg_still_n1}, true)
        pastey(to_layer, "blink_s", blayer, {leg_still_s1}, true)
        pastey(to_layer, "blink_w", blayer, {leg_still_w1}, true)

        pastey(to_layer, "hurtidle_e", blayer, {leg_still_e1}, true)
        pastey(to_layer, "hurtidle_n", blayer, {leg_still_n1}, true)
        pastey(to_layer, "hurtidle_s", blayer, {leg_still_s1}, true)
        pastey(to_layer, "hurtidle_w", blayer, {leg_still_w1}, true)

        pastey(to_layer, "sit_e", blayer, {leg_still_e1,leg_still_e1,leg_still_e1}, true)
        pastey(to_layer, "sit_n", blayer, {leg_still_n1}, true)
        pastey(to_layer, "sit_s", blayer, {leg_still_s1,leg_still_s1,leg_still_s1}, true)
        pastey(to_layer, "sit_w", blayer, {leg_still_w1,leg_still_w1,leg_still_w1}, true)

        pastey(to_layer, "sleep_e", blayer, {leg_still_e1}, true)
        pastey(to_layer, "sleep_n", blayer, {leg_still_n1}, true)
        pastey(to_layer, "sleep_s", blayer, {leg_still_s1}, true)
        pastey(to_layer, "sleep_w", blayer, {leg_still_w1}, true)

        --pastey(to_layer, "wink_e", blayer, {leg_still_e1}, true)
        --pastey(to_layer, "wink_n", blayer, {leg_still_n1}, true)
        pastey(to_layer, "wink_s", blayer, {leg_still_s1, leg_still_s1, leg_still_s1}, true)
        --pastey(to_layer, "wink_w", blayer, {leg_still_w1}, true)

        pastey(to_layer, "tiredidle_e", blayer, {leg_still_e1}, true)
        pastey(to_layer, "tiredidle_n", blayer, {leg_still_n1}, true)
        pastey(to_layer, "tiredidle_s", blayer, {leg_still_s1}, true)
        pastey(to_layer, "tiredidle_w", blayer, {leg_still_w1}, true)

        pastey(to_layer, "hurtwalk_e", blayer, {leg_close_e, leg_still_e1}, true)
        pastey(to_layer, "hurtwalk_n", blayer, {leg_close_n, leg_still_n1}, true)
        pastey(to_layer, "hurtwalk_s", blayer, {leg_close_s, leg_still_s1}, true)
        pastey(to_layer, "hurtwalk_w", blayer, {leg_close_w, leg_still_w1}, true)

        pastey(to_layer, "down_n", blayer, {leg_still_n1, leg_close_n, leg_still_n1, leg_spread_n}, false)

        pastey(to_layer, "drawn_e", blayer, {leg_spread_e, leg_close_e}, false)
        pastey(to_layer, "drawn_n", blayer, {leg_spread_n, leg_close_n}, false)
        pastey(to_layer, "drawn_s", blayer, {leg_spread_s, leg_close_s}, false)
        pastey(to_layer, "drawn_w", blayer, {leg_spread_w, leg_close_w}, false)
        -- blayer:cel(1)
    end
}:show()

