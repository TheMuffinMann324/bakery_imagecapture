# bakery_imagecapture

Captures FiveM clothing, props, and vehicles with green screen removal. Makes transparent PNGs/WEBPs for inventory and shop UIs.

This is a fork of [sintic-imagecapture](https://github.com/nethushadev/sintic-imagecapture), maintained for the bakery_racing resource. The changes are listed below.

## Credits

- **[nethushadev](https://github.com/nethushadev)**: author of the original sintic-imagecapture this fork is based on.
- **[Bentix](https://github.com/Bentix-cs/fivem-greenscreener)**: the original concept, from fivem-greenscreener.
- **[itschip](https://github.com/itschip/screencapture)**: screencapture, which provides the screenshot functionality.

Licensed under the GNU General Public License v3.0. See `LICENSE`.

## What this fork changes

- **Completion exports for other resources.** `CaptureVehicle(model, onDone)` and `CaptureProp(model, onDone)` call `onDone(true)` only once the image file is written, and `onDone(false)` if it wasn't. bakery_racing uses these so it knows exactly when a picture is ready.
- **Fitted camera for world props.** Each prop's camera is set so it fills about 70% of the frame, based on its size.
- **A backdrop behind every world prop.** Green screens are placed behind each prop from the camera's point of view. Their number comes from the size of the green screen model, so one large panel can cover the frame.
- **Large green screen model.** The studio uses a streamed model (`stream/it_greenscreen_120x80.ydr`) instead of the built-in screen.
- **Per-model camera override.** `Config.PropCamera` can set the distance and field of view for one prop.

## Setup

1. Install [screencapture](https://github.com/itschip/screencapture).
2. Drop this folder into your resources.
3. Make sure `stream/` contains the green screen model and its archetype file, and that `fxmanifest.lua` declares the archetype with `data_file 'DLC_ITYP_REQUEST'`.
4. Start screencapture, then this resource, before bakery_racing: `ensure screencapture` and `ensure bakery_imagecapture` in `server.cfg`.
5. Edit `config.lua` to your liking.

## Usage

### Clothing
Components: `face, mask, hair, torso, legs, bag, shoes, accessory, undershirt, armor, decals, top`

```
/capture-clothing male          # all male clothing
/capture-clothing female torso  # just female torsos
/capture-clothing all           # everything (takes a while)
```

### Props
Props: `hat, glasses, ears, watch, bracelet`

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

**Note:** World props use dynamic camera calculation. Use `Config.PropCamera` for a manual override instead of the adjustment mode.

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

### Green screen

```lua
Config.GreenScreenProp = 'it_greenscreen_120x80'          -- the streamed model's name
Config.GreenScreenOffsets = { vector3(0.0, 0.0, -30.0) }  -- panel position relative to the studio point
Config.BackdropHeading = 180.0  -- set to 0 if the backdrop shows its back side
Config.BackdropDrop = -30.0     -- how far each prop's backdrop sits below the prop's centre
Config.PropCamera = {}          -- per-model override: { distance = 30.0, fov = 40.0 }
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

## How bakery_racing uses it

bakery_racing takes pictures of shop cars and track-editor props with this resource:

- **Props:** the Admin → Props page has **Picture all** (every prop) and **Picture missing** (only props without a picture).
- **Cars:** the Admin → Shop item form has **Take picture** for a car, so you can check it before adding it to the shop.

For each item, bakery_racing calls `CaptureVehicle` or `CaptureProp`, waits for the completion callback, then reads the file from this resource's `images/` folder and stores it in its own database. The tablet and track editor show the stored pictures, so they don't depend on this folder afterwards.

- Vehicles are written to `images/vehicles/<model>.webp`.
- Props are written to `images/worldprops/<model>.webp`.

The tablet closes during a batch so its overlay stays out of the pictures, and it reopens on the admin page when the batch finishes.

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
- `images/worldprops/prop_chair_01a.webp`

## Troubleshooting

**Green still visible?** Lower `GreenThreshold` and `GreenDiff` in config.

**FiveM UI in images?** Increase `CropBottom` and `CropRight`.

**Camera framing sucks?** Use adjustment mode for that specific item, copy the printed config.

**Props going through the backdrop or at the wrong distance?** Adjust `Config.BackdropDrop` or `Config.PropCamera` for that prop.

**No green panel at all?** Check that the green screen model and its archetype are in `stream/`, that `fxmanifest.lua` declares the archetype, and that `Config.GreenScreenProp` matches the model name exactly.

**Head won't hide?** See "Head Hiding Limitation" above. You'll need Canary build.

**Weather/time not syncing?** If you have other weather scripts (like qb-weathersync), they might conflict. Temporarily disable them during capture or adjust their priority.

## Dev Notes

- Uses `mp_m_freemode_01` and `mp_f_freemode_01` for clothing/props
- Studio location is way up in the sky to avoid interference
- Weather locked to EXTRASUNNY at noon for consistent lighting
- Empty detection checks bounding box (under 100px) and opacity (under 50 pixels)
- Texture variations optional via `/capture-textures on`
- `Config.PropFitSize` is no longer used: every world prop is fitted to the camera now.

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
