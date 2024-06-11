# 2.0.8
+ mask.ase: now has sit state
+ tlc-char-dmi-import: now copies dummy heads&bodies to sit state
+ tlc-copy-paster: now copies heads&bodies to sit state

# 2.0.7
TLC-ZOMBIFY: Fixed error when replacing colors. 
    ADDED: Selecting the zbase file in scripts folder

# 2.0.6
ADDED: TlC-char-dmi_import.lua to convert character.dmi icons to aseprite files which ALSO cuts heads and bodies.
UPDATED: TLC-COPY-PASTER to account for the new "down/crawl" animation

# 2.0.5
* ADDED: dmi-import.lua and dump_ztxt.exe(https://github.com/thelastconflict/dump_ztxt) to easily import dmi files into aseprite

# 2.0.4
* FIXED: bug where exporting on windows would export to aseprite.exe directory opposed to the .ase path

# 2.0.3
## ADDED: TLC-ZOMBIE-EXPORT
## TLC-ZOMBIFY
* Fixed crashes
* Automatically samples face on specific places
* Ignore replacing the color black
* Fix bug with misplaced `_` seperator, e.g `d1-walk` should really be `d1_walk`
## TLC-COPY-PASTER
* Made wink more easier to do

# 2.0.2
## TLC-COPY-PASTER
* Now properly pastes the blink heads
* Removed version name from file

# 2.0.1
## TLC-IMPORT-ATLAS
* Remove uneeded buggy sorting
* Fixed bug where legs layer would draw eyes
* Improved Ergonomics: Assumes that the json file is in the same dir as the png file
* Fixed CLI on windows

## TLC-EXPORT
* Removed version number from filename
* Run animation is no longer warned missing
* Note that run and idle are optional animations
* Changed shape padding to 1

## TLC-COPY-PASTER
* Run animations are now optional
* Removed other wink directions
* Wink is now 3 frames

# 2.0.0
## TLC-IMPORT-ATLAS
* Reworked entirely to be more robust, placing via animation tags
* Fixed color pallete not being set
* Fixed greenish artifacts
* Now pushes death/corpse animations to the end
* Now imports eyes and legs from zed atlases

## TLC-EXPORT
* No longer nags about idle animations not being present
* Remove exporting of redundant data
* Warns when non-supported layers are visible on export 
