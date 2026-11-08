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
  of the button, `Manual` leaves the look to programming, and `By Value` shows
  the look that follows a value
- Added `By Value` to Look Control: each look gets a Show when expression on
  other devices' variables, the first look whose expression is true shows, and a
  default look shows when none is
- Added Next Look and Previous Look commands, and an In cycle setting for each
  look that presses and both commands pass over when it is off
- Added a Button Link connection for each look: a press of the button taps the
  link of the look it shows, as a keypad button does
- Added `By Link` to Look Control: each look gets a Show while setting, and the
  button shows the first look whose Button Link is on or off as it says, so the
  button follows the device bound to the link whatever changes it
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
- Added a refresh to a picture from a web address: the controller fetches it
  again every minute, 5 minutes, 15 minutes or hour while its look shows, and
  shows it as the site sends it, with Refresh Web Picture and Set Web Address
  commands
- Added Copy To, Export and Import to the Looks card: chosen looks, with their
  own pictures, go to other Dynamic Buttons in the project, added to or
  replacing theirs, or to a file that another button imports
- Added Icon and Badge sections to each look: the picture's colors with its
  shading kept, the glow's color, its size and position, and a badge of up to
  five characters in the size you pick
- Added live badges: a badge's text can hold a variable, and the controller
  draws it on the shown look and keeps it current, at most as often as the
  look's Update setting
- Added the driver's properties to the Button tab, where they can be changed as
  in Composer's Properties tab, with Look Control beside the shown button
- Added a Timer to each look: from 1 second to 24 hours after a press,
  programming or the Button tab shows it, the button shows the look before or
  another look, and under `By Value` the look the values call for
  <!-- #ifdef DRIVERCENTRAL -->
- Added DriverCentral licensing: without an active license the button shows the
  driver's own icon after five minutes and its looks can't change, and a license
  shows its look again at once
  <!-- #endif -->

### Changed

- Changed Log Level in the DriverCentral build to stop at `4 - Debug`:
  `5 - Trace` and `6 - Ultra` are offered only while a Support Code from Finite
  Labs support has the Lua tab open, and a driver set to either goes back to
  `4 - Debug`.
