<!-- Copyright 2026 Finite Labs, LLC. All rights reserved. -->

<img alt="Dynamic Buttons" src="./images/header.png" width="500"/>

______________________________________________________________________

# <span style="color:#109EFF">Overview</span>

> DISCLAIMER: This software is neither affiliated with nor endorsed by Control4.

Add buttons to Navigator whose picture you design. Each **Dynamic Button** is
one button in a room's Navigator menus. It shows one of its looks: an icon from
a free icon pack, drawn in your colors on the tile shape you pick. Control4
programming changes which look the button shows, and pressing the button runs
the programming you attach to it.

# <span style="color:#109EFF">Index</span>

<div style="font-size: small">

- [System Requirements](#system-requirements)

- [Features](#features)

- [Installer Setup](#installer-setup)

  - [Driver Installation](#driver-installation)
  - [Showing the Button in Navigator](#showing-the-button-in-navigator)
  - [The Button Tab](#the-button-tab)
    - [Looks](#looks)
    - [Look Editor](#look-editor)
    - [Icon Search](#icon-search)
  - [Driver Setup](#driver-setup)
    - [Driver Properties](#driver-properties)
      - [Cloud Settings](#cloud-settings)
      - [Driver Settings](#driver-settings)
      - [Button Settings](#button-settings)
    - [Driver Actions](#driver-actions)
  - [Programming Reference](#programming-reference)

- [Icon Licenses](#icon-licenses)

- [Support](#support)

- [Changelog](#changelog)

</div>

# <span style="color:#109EFF">System Requirements</span>

- Control4 OS 3.3.1 or later
- Composer Pro, to set up each button's looks in its Button tab

# <span style="color:#109EFF">Features</span>

- A Navigator button with up to eight looks, each drawn from an icon in the
  colors and tile shape you pick
- About 280 included icons that work with no internet, and a search across
  fourteen free icon packs
- A Show Look programming command, a Look variable, a Look Changed event and a
  Look Is conditional
- The button's picture updates in Navigator as soon as programming changes it

# <span style="color:#109EFF">Installer Setup</span>

## Driver Installation

1. Download the latest `control4-dynamic-buttons.zip` from
   [GitHub](https://github.com/finitelabs/control4-dynamic-buttons/releases/latest).

1. Extract and
   [install](https://www.control4.com/help/c4/software/cpro/dealer-composer-help/content/composerpro_userguide/adding_drivers_manually.htm)
   the `.c4z` file.

1. Use the "Search" tab to find the "Dynamic Button" driver and add it to the
   room the button belongs in. Add one driver for each button.

## Showing the Button in Navigator

A new button starts hidden in every Navigator menu. To show it:

1. Select the room in the "System Design" tab and open its "Navigator" tab.
1. Pick the menu the button belongs in under "Experience Menus".
1. Select "Modify...", move the button from "Hidden Devices" to the visible list
   with "Show", and select "OK".
1. Refresh Navigators.

Until the button has a look, it shows the driver's own icon.

## The Button Tab

Select the driver in the "System Design" tab and open its "Button" tab to make
the button's looks.

### Looks

<img alt="Button tab - Looks" src="./images/ui-looks.png" width="640"/>

1. **Shown now** - the button as the Control4 app shows it, with the name of the
   look it shows, or `Driver icon` until a look has a picture.
1. **Looks** - each look with its picture, name, icon and tile shape. `Shown`
   marks the look the button shows. `No picture yet` marks a look whose picture
   has not reached the driver, and `Picture out of date` a look edited since its
   picture was sent: Navigator shows the earlier picture until the look is saved
   again.
1. **Show** - shows the look now. It is off for the shown look and for a look
   with no picture.
1. **Edit** - opens the look in the editor.
1. **↑ / ↓** - moves the look up or down. Programming lists the looks in this
   order.
1. **Delete** - deletes the look and its picture, after a second press on
   `Confirm Delete`. Deleting the shown look shows the first remaining look with
   a picture, or the driver's own icon when none has one.
1. **Add Look** - opens the editor for a new look. A button has up to eight
   looks.

### Look Editor

<img alt="Button tab - Look Editor" src="./images/ui-look-editor.png" width="640"/>

1. **Name** - the look's name in programming: up to 40 characters, without
   commas, and different from the button's other looks. Picking an icon fills it
   in when it is empty.
1. **Tile shape** - `None`, `Circle`, `Rounded Square` or `Square`. With `None`
   the icon is drawn on its own, larger.
1. **Icon color** - the color the icon is drawn in.
1. **Tile color** - the color of the tile behind the icon.
1. **Included icons / Search online** - picks from the icons included with the
   driver, which work with no internet, or from the free icon packs online. See
   [Icon Search](#icon-search).
1. **All categories / Filter by name** - narrow the included icons by category
   and by name.
1. **Icons** - select one to use it for the look.
1. **Icon** - the picked icon and its license.
1. **Preview** - the look as the Control4 app shows it.
1. **Picture** - the picture the driver keeps, at the 300 pixels the app loads.
1. **Save Look / Cancel** - `Save Look` saves the look and sends its picture to
   the driver. A look renamed without other changes keeps its picture. The
   button's first look shows as soon as its picture arrives.

### Icon Search

<img alt="Button tab - Icon Search" src="./images/ui-icon-search.png" width="640"/>

1. **Search** - searches the packs chosen under `Packs` for icons whose names
   match. If the computer running Composer cannot reach the icon service, the
   search goes through the controller.
1. **Style** - `Any`, `Outline` or `Filled`. Shows only the outline or the
   filled icons among those found, as each pack marks them in its icon names. An
   icon whose name does not say shows under both. It filters the icons found
   without searching again.
1. **Packs** - the packs to search, all fourteen by default. `All` and `None`
   set every pack at once, and a change searches again.
1. **Icons** - the icons found that match the style. Select one to use it for
   the look.
1. **Icons found** - how many icons the search found, and how many of them the
   style shows.

## Driver Setup

### Driver Properties

#### Cloud Settings

##### Automatic Updates \[ Off | **_On_** \]

Turns automatic driver updates on or off. Changing it on one Dynamic Button
changes it on all of them.

##### Update Channel \[ **_Production_** | Prerelease \]

Selects which releases the driver installs: `Production` installs releases only,
and `Prerelease` also installs test builds.

#### Driver Settings

##### Driver Status (read-only)

Displays `Ready` once the driver has started.

##### Driver Version (read-only)

Displays the current version of the driver.

##### Log Level \[ 0 - Fatal | 1 - Error | 2 - Warning | **_3 - Info_** | 4 - Debug | 5 - Trace | 6 - Ultra \]

Sets the logging level. Default is `3 - Info`.

##### Log Mode \[ **_Off_** | Print | Log | Print and Log \]

Sets the logging mode. Default is `Off`. It turns itself off after three hours.

#### Button Settings

##### Shown Look (read-only)

Displays the name of the look the button shows, or nothing while it shows the
driver's own icon.

### Driver Actions

#### Update Drivers

Installs the latest release on the Update Channel from GitHub for every Dynamic
Button, regardless of the current version.

#### Reset Driver

> WARNING: Reset Driver deletes every look and its picture. They cannot be
> brought back.

Returns the driver to a fresh install: it deletes every look and its picture,
shows the driver's own icon, and returns the properties to their defaults. The
button keeps its place in Navigator and the programming that uses it.
Programming that names a deleted look does nothing, even after a new look takes
the same name: choose the new look in that programming.

**Parameters:**

- **Are You Sure?** \[ **_No_** | Yes \] - Confirmation to reset the driver.

## Programming Reference

### Commands

| Command   | Parameters | Description                  |
| --------- | ---------- | ---------------------------- |
| Show Look | Look       | Shows the look on the button |

Looks show in programming as their name and number. The command finds the look
by its number, so programming keeps working after the look is renamed.

### Variables

| Variable | Type   | Description                                                      |
| -------- | ------ | ---------------------------------------------------------------- |
| Look     | STRING | The name of the look the button shows, or empty for its own icon |

### Events

| Event        | Description                                                        |
| ------------ | ------------------------------------------------------------------ |
| Look Changed | Fires when the button shows a different look                       |
| Selected     | The button's own event in Navigator: fires when someone presses it |

### Conditionals

| Conditional | Description                                        |
| ----------- | -------------------------------------------------- |
| Look Is     | Tests whether the button shows a look, or does not |

# <span style="color:#109EFF">Icon Licenses</span>

The included icons come from two collections, both under the
[Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0):

- [Material Design Icons](https://github.com/Templarian/MaterialDesign),
  copyright Pictogrammers
- [Material Symbols](https://github.com/google/material-design-icons), copyright
  Google LLC

The driver includes these notices and the full license text in its
`LICENSES.txt` file.

**Search online** uses the free [Iconify](https://iconify.design) service and
offers only these packs, whose licenses allow their icons to be used without
credit on each one:

| Pack                   | License                                                       |
| ---------------------- | ------------------------------------------------------------- |
| Material Symbols       | [Apache 2.0](https://github.com/google/material-design-icons) |
| Material Design Icons  | [Apache 2.0](https://github.com/Templarian/MaterialDesign)    |
| Fluent UI System Icons | [MIT](https://github.com/microsoft/fluentui-system-icons)     |
| Phosphor               | [MIT](https://github.com/phosphor-icons/core)                 |
| Tabler Icons           | [MIT](https://github.com/tabler/tabler-icons)                 |
| MingCute               | [Apache 2.0](https://github.com/Richard9394/MingCute)         |
| Carbon                 | [Apache 2.0](https://github.com/carbon-design-system/carbon)  |
| Bootstrap Icons        | [MIT](https://github.com/twbs/icons)                          |
| Lucide                 | [ISC](https://github.com/lucide-icons/lucide)                 |
| Iconoir                | [MIT](https://github.com/iconoir-icons/iconoir)               |
| Ionicons               | [MIT](https://github.com/ionic-team/ionicons)                 |
| Heroicons              | [MIT](https://github.com/tailwindlabs/heroicons)              |
| Meteocons              | [MIT](https://github.com/basmilius/weather-icons)             |
| Weather Icons          | [OFL 1.1](https://github.com/erikflowers/weather-icons)       |

Each look keeps the name and license of the icon it was drawn from.

# <span style="color:#109EFF">Support</span>

If you have any questions or issues integrating this driver with Control4, you
can file an issue on GitHub:

https://github.com/finitelabs/control4-dynamic-buttons/issues/new

<a href="https://www.buymeacoffee.com/derek.miller" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>

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
