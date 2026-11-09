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
  set up in its Button tab
- Added included icons, three icon packs that match the OS 3 and X4 looks, and a
  search of free icon libraries online
- Added colors, tile shapes, glow and grayscale for each look, with a color
  picker
- Added badges, and live badges that show a variable's value
- Added My images: a look's picture can be an uploaded file, pasted SVG, or a
  picture from a web address that can refresh on a schedule
- Added Look Control: `On Select` shows the next look on each press, `Manual`
  leaves the look to programming, `By Value` follows other devices' variables,
  and `By Link` follows the devices bound to the looks' Button Links
- Added a Button Link for each look, which a press of the button taps as a
  keypad button does
- Added a timer on each look that shows another look after a set time
- Added Show Look, Next Look and Previous Look commands, a `Look` variable, a
  Look Changed event, an event for each look and a Look Is conditional
- Added Duplicate, Copy To, Export and Import for looks
- Added the driver's properties to the Button tab
  <!-- #ifdef DRIVERCENTRAL -->
- Added a license check: after five minutes without an active DriverCentral
  license the button shows the driver's own icon and its looks can't change, and
  a license shows its look again at once
  <!-- #endif -->

### Changed

- Changed Log Level in the DriverCentral build to stop at `4 - Debug`:
  `5 - Trace` and `6 - Ultra` are offered only while a Support Code from Finite
  Labs support has the Lua tab open, and a driver set to either goes back to
  `4 - Debug`.
