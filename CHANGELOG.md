# <span style="color:#109EFF">Changelog</span>

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
- Added three icon packs with the same 100 subjects in each, picked from the
  Button tab's Icon packs view: Classic Device and Classic Tile, which match the
  OS 3 look, and Modern, which matches the X4 look, with on, off and alert
  pictures where a subject has states
- Added Glow and Grayscale to each look: Glow sets a Classic Device picture's
  glow from none to twice its own, and Grayscale draws any picture in grays with
  no glow, its gray version beside the packs' own on and off pictures
- Added the driver's properties to the Button tab, where they can be changed as
  in Composer's Properties tab, with Look Control beside the shown button
