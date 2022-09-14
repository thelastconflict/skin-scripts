--[[ 

    - normalizes skin tone color pal

 ]] -- the popular white skin tones
-- replace colors within 4 tolerance with these or within 5 on 1 channel
local tones_pop = {
    Color {r = 180, g = 125, b = 50, a = 255}, -- lower bottom last chin
    Color {r = 213, g = 164, b = 98, a = 255}, -- lower side cheeks, also forehead color
    Color {r = 255, g = 215, b = 165, a = 255}, -- middle nose
    Color {r = 245, g = 190, b = 125, a = 255} -- -1px under eye pupil cheek
}

local sprite = app.activeSprite

app.command.ChangePixelFormat {format = "indexed"}
local image = app.activeImage

image.spec.colorMode = ColorMode.INDEXED

-- Color Color Int -> Bool
function color_within_tol(c1, c2, tol)
    local dr = math.abs((c1.red - c2.red)) <= tol
    local dg = math.abs((c1.green - c2.green)) <= tol
    local db = math.abs((c1.blue - c2.blue)) <= tol
    local da = math.abs((c1.alpha - c2.alpha)) <= tol

    return dr and dg and db and da
end

-- Color Color Int Int -> bool
-- requires N channels to be the same along within hte max tol
function color_within_tol_chan_limit(c1, c2, tol, chan_limit)
    local dr = math.abs((c1.red - c2.red))
    local dg = math.abs((c1.green - c2.green))
    local db = math.abs((c1.blue - c2.blue))
    local da = math.abs((c1.alpha - c2.alpha))

    local ls = {dr, dg, db, da}
    local max_diff = 0
    local count_zeros = 0
    for _, diff in ipairs(ls) do
        max_diff = math.max(max_diff, diff)
        if diff == 0 then count_zeros = count_zeros + 1 end
    end

    return chan_limit == count_zeros and max_diff <= tol
end

--[[ local t1 = color_within_tol(Color {r = 180, g = 125, b = 50, a = 255}, Color {r = 180, g = 120, b = 50, a = 255}, 4); -- false
local t2 = color_within_tol(Color {r = 180, g = 124, b = 50, a = 255}, Color {r = 180, g = 120, b = 50, a = 255}, 4); -- true
local t3 = color_within_tol(Color {r = 180, g = 120, b = 50, a = 255}, Color {r = 180, g = 120, b = 50, a = 255}, 4); -- true, equal
local t4 = color_within_tol(Color {r = 180, g = 124, b = 54, a = 255}, Color {r = 180, g = 120, b = 50, a = 255}, 4); -- true on both chans
print(t1, t2, t3, t4) ]]

function print_pal(pal)
    for i = 0, #pal - 1, 1 do
        local clr = pal:getColor(i);
        print(i, clr.red, clr.green, clr.blue, clr.alpha)
    end
end

local og_pal = sprite.palettes[1]

-- LOOP OVER ALL THE PIXELS INSTEADD
for i = 0, #og_pal - 1, 1 do
    local clr = og_pal:getColor(i);

    for _, norm_col in ipairs(tones_pop) do
        if color_within_tol(clr, norm_col, 4) or
            color_within_tol_chan_limit(clr, norm_col, 5, 3) then
            og_pal:setColor(i, norm_col)
            -- og_pal:setColor(i, Color {r= 0, g= 0, b= 0, a=255})
            -- print("CHANGED", i, clr.red, clr.green, clr.blue, "TO", norm_col.red, norm_col.green, norm_col.blue)
        end
    end
end
sprite:setPalette(og_pal)

-- BEWARE: https://github.com/aseprite/aseprite/issues/3352 IT IS CHANGING THE HAIR COLOR
image:saveAs{filename = sprite.filename, palette = og_pal}
sprite:saveAs(sprite.filename)
-- can change via Sprite:setPalette

--[[ 

image:saveAs{ filename=string,
              palette=Palette }

 ]]
