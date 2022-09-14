local sprite = app.activeSprite
local layers = sprite.layers
local tags = sprite.tags

-- returns nil if not found or the tag
function get_tag(tags, name)
    local res = nil
    for _, tag in ipairs(tags) do if tag.name == name then res = tag end end
    return res
end

local body_layer = sprite.layers[1]
if body_layer.name ~= "body" then body_layer = sprite.layers[2] end

-- DELETE DEATH ANIMATIONS
function is_death_anim(str)
    return str == "death_e" or str == "death_w" or str == "death_n" or str ==
               "death_s" or str == "corpse_e" or str == "corpse_w" or str ==
               "corpse_n" or str == "corpse_s"
end

-- returns false or the death frame
function has_death_anim(tags)
    local res = false
    for _, tag in ipairs(tags) do
        if is_death_anim(tag.name) then res = tag.fromFrame end
    end
    return res
end

--[[ local start = has_death_anim(tags)
while start ~= false do
    sprite:deleteFrame(start)
    start = has_death_anim(tags)
end ]]

local LAST_WALK_FRAME_NUM = 24
local legs_layer = sprite:newLayer()
legs_layer.name = "legs"

local y_start_leg_point = 20

local c = body_layer:cel(1)
-- CREATE THE LEG LAYERS BY CUTTING OFF AFTER SPECIFIC Y VALUES
for frame_count, frame in ipairs(sprite.frames) do
    if frame_count <= LAST_WALK_FRAME_NUM then
        local cel = body_layer:cel(frame_count)
        local to_cel = sprite:newCel(legs_layer, frame_count)
        local r1 = {x = 0, y = 20, w = 32, h = 5}

        for it in cel.image:pixels() do
            local pixelValue = it() -- get pixel
            -- it(pixelValue) -- set pixel
            if it.y + cel.position.y >= 20 then
                to_cel.image:drawPixel(it.x + cel.position.x,
                                       it.y + cel.position.y, pixelValue)
                -- DELETE THE LEGS FROM THE BODY
                it(0)
            end
        end
    end
end

while #sprite.frames < 66 do local frame = sprite:newEmptyFrame() end

--[[ local walk_w_tag = get_tag(tags, "walk_w")
walk_w_tag.toFrame = LAST_WALK_FRAME_NUM ]]

local FINAL_DEATH_FRAMENUM = 28
local death_w_tag = get_tag(tags, "death_w")
death_w_tag.toFrame = FINAL_DEATH_FRAMENUM

-- todo: need to add the durations for these frames

local insert_dismembered = {
    {name= "d1-walk_e", dur=200},
    {name= "d1-walk_n", dur=200},
    {name= "d1-walk_s", dur=200},
    {name= "d1-walk_w",  dur=200},
    {name= "d1-battack_e", dur=200},
    {name= "d1-battack_n",  dur=200},
    {name= "d1-battack_s",  dur=200},
    {name= "d1-battack_w",  dur=200},
    {name= "d2-walk_e",  dur=200},
    {name= "d2-walk_n", dur=200},
    {name= "d2-walk_s",  dur=200},
    {name= "d2-walk_w",  dur=200},
    {name= "d2-battack_e",  dur=200},
    {name= "d2-battack_n",  dur=200},
    {name= "d2-battack_s", dur=200},
    {name= "d2-battack_w",dur=200},
}

local dismember_counter = FINAL_DEATH_FRAMENUM + 1 -- after the last anim, e.g death anim
for _, info in ipairs(insert_dismembered) do
    local name = info.name
    local duration = info.dur

    local stride = 0
    if string.find(name, "walk") and string.find(name, "d2") then
        -- d2 only has 3 walk frames
        stride = 3
    elseif string.find(name, "walk") then
        stride = 4
    elseif string.find(name, "battack") then
        stride = 2
    end
    local tag = sprite:newTag(dismember_counter, dismember_counter + stride - 1)
    dismember_counter = dismember_counter + stride
    tag.name = name
end

app.command.CanvasSize {
    ui = false,
    left = 0,
    top = 0,
    right = 0,
    bottom = 0,
    trimOutside = true
}

app.command.saveFile()
