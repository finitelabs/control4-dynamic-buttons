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

- **Add Look** opens the editor. Name the look, pick its icon, its icon color,
  its tile shape (`None`, `Circle`, `Rounded Square` or `Square`) and its tile
  color. The preview shows the button as the Control4 app shows it.
- **Included icons** work with no internet. **Search online** searches the free
  icon packs listed under [Icon Licenses](#icon-licenses). If the computer
  running Composer cannot reach the icon service, the search goes through the
  controller.
- **Save Look** draws the picture and sends it to the driver. The button's first
  look shows as soon as it is saved.
- **Show** shows a look now. **Edit**, the arrows and **Delete** change, move
  and remove a look. Deleting the shown look shows the first remaining look.

A look's name can be up to 40 characters, without commas, and each look on a
button has its own name.

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

Returns the driver to a fresh install: it deletes every look and its picture,
shows the driver's own icon, and returns the properties to their defaults. The
button keeps its place in Navigator and the programming that uses it, but
programming that names a deleted look does nothing until it names a new one.

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

The included icons come from
[Material Design Icons](https://github.com/Templarian/MaterialDesign) and
[Material Symbols](https://github.com/google/material-design-icons), both under
the [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0).

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

Each look keeps the name and license of the icon it was drawn from. The `NOTICE`
file in the driver's source repository holds the license notices.

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
  Symbols, and a search across fourteen free icon packs
- Added a Show Look command, a `Look` variable, a Look Changed event and a Look
  Is conditional
