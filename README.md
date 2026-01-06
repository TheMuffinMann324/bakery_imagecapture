# sintic-imagecapture

Captures FiveM clothing, props, and vehicles with green screen removal. Makes transparent PNGs/WEBPs for your inventory/shop UIs.

**Credits:**
- Inspired by [Bentix's fivem-greenscreener](https://github.com/Bentix-cs/fivem-greenscreener) - original concept
- Uses [itschip's screencapture](https://github.com/itschip/screencapture) - screenshot functionality

## Setup

1. Install [screencapture](https://github.com/itschip/screencapture)
2. Drop this in your resources
3. `ensure sintic-imagecapture` in server.cfg
4. Edit `config.lua` to your liking

## Usage

### Clothing
Components: ``face, mask, hair, torso, legs, bag, shoes, accessory, undershirt, armor, decals, top``
```
/capture-clothing male          # all male clothing
/capture-clothing female torso  # just female torsos
/capture-clothing all           # everything (takes a while)
```

### Props
Props: ``hat, glasses, ears, watch, bracelet``
```
/capture-ped-props male hat     # male hats
/capture-ped-props female       # all female props
```

### Vehicles
```
/capture-vehicles adder
/capture-all-vehicles           # batch from in/vehicles.lua
```

### World Props
```
/capture-props prop_chair_01a
/capture-all-props              # batch from in/props.lua
```

### Adjustment Mode

Fine-tune camera for specific items:
```
/capture-adjust-clothing male mask 5
/capture-adjust-prop female hat 8
/capture-adjust-vehicle adder
```

Controls: arrows/scroll to adjust, enter to save config, backspace to cancel.

**Note:** World props use dynamic camera calculation. No manual adjustment available yet.

## Config

`config.lua` has all the settings. Main ones:

```lua
Config.OutputSize = 512        # 256/512/1024
Config.OutputFormat = 'webp'   # or 'png'
Config.GreenThreshold = 120    # lower = more aggressive bg removal
Config.GreenDiff = 40

Config.CropBottom = 80         # removes FiveM UI from bottom-right
Config.CropRight = 80
```

### Hiding Components

For cleaner captures (like hiding head on hats):

```lua
Config.ClothingCamera = {
    [1] = {
        name = 'mask',
        fov = 45,
        zOffset = 0.70,
        distance = 27.8,
        heading = 339,
        hideComponents = {0}  -- hides head
    },
}
```

Component IDs: 0=head, 1=mask, 2=hair, 3=torso, 4=legs, etc.

**Head Hiding Limitation:**
Hiding head (component 0) doesn't work on stable FiveM. This is due to a [crash mitigation](https://forum.cfx.re/t/crash-mitigation-cped-setvariation-invalid-variation/5330523/42) that blocks setting head to -1. FiveM Canary has the `allowEmptyHeadDrawable` convar as a workaround - run `allowEmptyHeadDrawable true` in F8 console before capturing. Check the forum thread for more context from the community.

## How It Works

- Spawns items in a high-altitude green screen studio
- Captures screenshot via screencapture
- Browser-side processing removes green bg and crops to content
- Skips empty slots automatically (no more blank images)
- Pre-crops FiveM UI before processing

## Output

Images go to `images/` folder:
- `images/clothing/male_torso_5.webp`
- `images/props/female_prop_hat_3.webp`
- `images/vehicles/adder.webp`

## Troubleshooting

**Green still visible?** Lower `GreenThreshold` and `GreenDiff` in config.

**FiveM UI in images?** Increase `CropBottom` and `CropRight`.

**Camera framing sucks?** Use adjustment mode for that specific item, copy the printed config.

**Head won't hide?** See "Head Hiding Limitation" above. You'll need Canary build.

**Weather/time not syncing?** If you have other weather scripts (like qb-weathersync), they might conflict. Temporarily disable them during capture or adjust their priority.

## Dev Notes

- Uses `mp_m_freemode_01` and `mp_f_freemode_01` for clothing/props
- Studio location is way up in the sky to avoid interference
- Weather locked to EXTRASUNNY at noon for consistent lighting
- Empty detection checks bounding box (&lt;100px) and opacity (&lt;50 pixels)
- Texture variations optional via `/capture-textures on`

## Batch Lists

Edit `in/vehicles.lua` or `in/props.lua`:

```lua
{
    'adder',
    'zentorno',
    'banshee',
}
```

Then run `/capture-all-vehicles` or `/capture-all-props`.

---