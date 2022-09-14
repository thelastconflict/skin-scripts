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