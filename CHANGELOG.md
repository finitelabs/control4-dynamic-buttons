# <span style="color:#7C3AED">Changelog</span>

<!--
Template for a new release entry (copy below the heading, fill in, uncomment):

## v[Version] - YYYY-MM-DD

### Added
- Added

### Fixed
- Fixed

### Changed
- Changed

### Removed
- Removed
-->

## Unreleased

### Added

- Added the Dynamic Button driver: a Navigator button with up to eight looks,
  each drawn from an icon in the colors and tile shape you pick, made in its
  Button tab
- Added about 280 included icons from Material Design Icons and Material
  Symbols, and a search across fourteen free icon packs that filters by pack and
  by outline or filled style
- Added a Show Look command, a `Look` variable, a Look Changed event and a Look
  Is conditional
- Added the Look Control property: `On Select` shows the next look on each press
  of the button, and `Manual` leaves the look to programming
- Added Next Look and Previous Look commands, and an In cycle setting for each
  look that presses and both commands pass over when it is off
- Added an event for each look, named for the look, that fires when it becomes
  the shown look
- Added three icon packs with the same 100 subjects in each: Classic Device and
  Classic Tile, which match the OS 3 look, and Modern, which matches the X4
  look, with on, off and alert pictures where a subject has states
- Added one picture list to the look editor, with a source, a category and a
  search across the packs, the included icons and, when asked, the free icon
  libraries online
- Added Glow and Grayscale to each look: Glow sets a Classic Device picture's
  glow from none to twice its own, and Grayscale draws any picture in grays with
  no glow, its gray version beside the packs' own on and off pictures
- Added a color picker for every color: the look's own colors and recent colors
  as swatches, a hex box, and hue, saturation and lightness sliders
- Added Duplicate to each look, which opens a copy of it in the editor
- Added My images: a look's picture can be a file you upload, SVG you paste, or
  a picture from a web address the controller fetches, kept with the button
- Added Icon and Badge sections to each look: the picture's colors with its
  shading kept, the glow's color, its size and position, and a badge of up to
  five characters in the size you pick
- Added live badges: a badge's text can hold a variable, and the controller
  draws it on the shown look and keeps it current, at most as often as the
  look's Update setting
- Added the driver's properties to the Button tab, where they can be changed as
  in Composer's Properties tab, with Look Control beside the shown button
- Added DriverCentral licensing: without an active license the button shows the
  driver's own icon after five minutes and its looks can't change, and a license
  shows its look again at once
