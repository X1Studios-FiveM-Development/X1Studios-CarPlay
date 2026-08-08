CarPlay v2.0.0 - X1Studios (SheriffX1)

Command - "/carplay"
Keybind - "9" -- Can be changed in "config.lua"

Please join our Discord and open a ticket for any help

X1Studios - https://discord.gg/TqcPD9Xee3


# Server.cfg Requirement
ensure xsound
ensure X1S-CarPlay

# Radio Item / Install Setup

CarPlay can now be bought as an item and installed into
the vehicle (while seated in it) before it will do anything in that
vehicle. This is on by default - set `Config.Radio.RequireInstall = false`
in `config.lua` to go back to the old always-available behavior.

## Standalone Requirement (vMenu)
Set `Config.Radio.RequireInstall = false` in `config.lua` for the script
to become compatible with standalone servers like vMenu.

## Item Requirement
Set `Config.Radio.RequireInstall = true` in `config.lua` for the script
to become compatible with as an item for inventories .

## Requirements

- **oxmysql is optional**, not required. If it isn't installed/started,
  the radio-install requirement automatically disables itself (with a
  clear warning in the server console) and CarPlay works exactly like
  the original always-available version - the resource never fails to
  start over it, and no other vehicle is locked out because of it.
- When oxmysql *is* running and `Config.Radio.RequireInstall = true`, a
  table `x1s_carplay_radios` is created automatically on first start -
  no manual SQL import needed.
- **A vMenu-only / no-framework / no-database server**: just set
  `Config.Radio.RequireInstall = false` in `config.lua`. That alone is
  enough - CarPlay goes back to working in every vehicle immediately,
  no item, no install, no database, nothing else to change.

## Framework detection

Detected automatically, in this order, at resource start:

1. `qb-core` running → QBCore (this also covers **Qbox**, since Qbox's
   `qbx_core` ships a `qb-core`-compatible bridge that answers to the
   same resource name/export).
2. `es_extended` running → ESX.
3. Neither → **standalone** fallback (see below).

`ox_inventory` is detected independently of the above and, if running,
is always used for actually removing the item (regardless of which
framework it's sitting on top of).

## Setting up the item

This resource never creates the item itself - add `car_radio` (or
whatever you set `Config.Radio.Item` to) to your own item list and sell
it however you like (shop script, NPC, admin command, whatever).

### ESX

Add `car_radio` to your items table. That's it - `ESX.RegisterUsableItem`
is wired up automatically, so using the item from any ESX-compatible
inventory will trigger the install.

### QBCore / Qbox

Add `car_radio` to `qb-core/shared/items.lua` (or your `qbx_core` items).
`QBCore.Functions.CreateUseableItem` is wired up automatically.

### ox_inventory

Add this to `ox_inventory/data/items.lua`:

```lua
['car_radio'] = {
    label = 'Car Radio',
    weight = 800,
    stack = false,
    close = true,
    consume = 0, -- important: this resource removes it itself, only
                 -- once the install actually finishes
    client = {
        export = 'X1S-CarPlay.x1s_useRadioItem'
    }
},
```

### Any other inventory

Call the generic server export once your inventory has confirmed the
item is being used (and has removed/consumed it on your end):

```lua
exports['X1S-CarPlay']:UseRadioItem(source)
```

### Standalone (no framework, no ox_inventory)

Two commands are registered automatically:

- `/useradio` - any player, installs a radio they own while seated in a
  vehicle.
- `/giveradioitem <serverId> [amount]` - grants radios. This is
  ACE-restricted, so add a line like this to your `server.cfg`:

  ```
  add_ace group.admin command.giveradioitem allow
  ```

  (swap `group.admin` for whatever principal your admins are in, and
  rename the command via `Config.Radio.StandaloneGiveCommand` if you
  want a different name/permission).

## Config reference (`config.lua` → `Config.Radio`)

| Key | Purpose |
|---|---|
| `RequireInstall` | Master on/off switch for this whole feature. |
| `Item` | Item name to use across every integration path. |
| `InstallTime` | How long (ms) the install takes. |
| `InstallDriverOnly` | Only the driver's seat can install. |
| `StandaloneUseCommand` / `StandaloneGiveCommand` | Standalone-only fallback commands (ignored once a real framework or ox_inventory is detected). |

## How it works, briefly

- Using the item starts a plain on-screen progress bar (no ox_lib or
  other UI dependency) - the player must stay in the same vehicle for
  the whole duration.
- The item is only actually consumed once the install **succeeds** -
  leaving the vehicle early cancels for free, nothing is lost.
- Once installed, the vehicle's plate is stored in `x1s_carplay_radios`
  and survives restarts, garaging, etc. (plates, not net ids, same as
  the existing saved-songs feature).
- Every mutating CarPlay action funnels through one server-side check
  (`ValidateControl` in `server.lua`), so a vehicle without a radio is
  fully locked out - not just from the UI, but from every underlying
  event too.
