Config = {}

Config.StudioLocation = vector3(628.8900, 1419.6689, 2403.6514) -- Way up in the sky so nobody sees it

Config.OutputSize = 512 -- 256, 512, or 1024
Config.OutputFormat = 'webp'

Config.GreenThreshold = 120
Config.GreenDiff = 40

-- Crop FiveM UI from bottom-right before processing
Config.CropBottom = 80
Config.CropRight = 80

Config.CaptureTextures = false -- toggle with /capture-textures
Config.CaptureDelay = 500

Config.Weather = 'EXTRASUNNY'
Config.Time = { hour = 12, minute = 0, second = 0 }
Config.FreezeTime = true

Config.PedModels = {
    male = 'mp_m_freemode_01',
    female = 'mp_f_freemode_01'
}

-- hideComponents: hide specific parts (0=head, 2=hair, etc.)
Config.ClothingCamera = {
    [0] = { name = 'face', fov = 45, zOffset = 0.65, distance = 20.0, heading = 13.0, hideComponents = {} },
    [1] = { name = 'mask', fov = 45, zOffset = 0.70, distance = 27.8, heading = 339, hideComponents = {0} },
    [2] = { name = 'hair', fov = 45, zOffset = 0.65, distance = 0.8, hideComponents = {} },
    [3] = { name = 'torso', fov = 50, zOffset = 0.3, distance = 60.0, hideComponents = {} },
    [4] = { name = 'legs', fov = 55, zOffset = -0.2, distance = 1.2, hideComponents = {} },
    [5] = { name = 'bag', fov = 50, zOffset = 0.2, distance = 1.0, hideComponents = {} },
    [6] = { name = 'shoes', fov = 50, zOffset = -0.5, distance = 1.0, hideComponents = {} },
    [7] = { name = 'accessory', fov = 45, zOffset = 0.3, distance = 0.9, hideComponents = {} },
    [8] = { name = 'undershirt', fov = 50, zOffset = 0.3, distance = 1.0, hideComponents = {} },
    [9] = { name = 'armor', fov = 50, zOffset = 0.3, distance = 1.0, hideComponents = {} },
    [10] = { name = 'decals', fov = 50, zOffset = 0.3, distance = 1.0, hideComponents = {} },
    [11] = { name = 'top', fov = 50, zOffset = 0.3, distance = 1.0, hideComponents = {} },
}

Config.PedPropCamera = {
    [0] = { name = 'hat', fov = 40, zOffset = 0.74, distance = 27.7, heading = 340.0, hideComponents = {0, 2} },
    [1] = { name = 'glasses', fov = 35, zOffset = 0.68, distance = 18.6, heading = 345.00, hideComponents = {} },
    [2] = { name = 'ears', fov = 35, zOffset = 0.63, distance = 14.1, heading = 36.00, hideComponents = {0, 2} },
    [6] = { name = 'watch', fov = 35, zOffset = 0.04, distance = 21.5, heading = 314.00, hideComponents = {} },
    [7] = { name = 'bracelet', fov = 35, zOffset = 0.05, distance = 21.5, heading = 48.00, hideComponents = {} },
}

-- Vehicle camera settings (per-vehicle overrides)
Config.VehicleCamera = {
    -- ['adder'] = { fov = 50, zOffset = 0.5, distance = 5.0, heading = 25, vehicleHeading = 0, pitch = 0 },
}

-- Default vehicle camera
Config.DefaultVehicleCamera = {
    fov = 50.00,
    zOffset = 1.21,
    distance = 5.0,
    heading = 33.00,
    vehicleHeading = 133.00, -- PLEASE USE FLOAT OTHERWISE THE HEADING WILL NOT WORK. IVE SPEND LIKE 10HRS FIGURING THAT OUT. SHIT
    pitch = 20
}

-- Green screen setup
Config.GreenScreenProp = 'it_greenscreen_120x80'   -- your 120 m x 80 m panel (stream/it_greenscreen_120x80.ydr)
Config.GreenScreenOffsets = {
    vector3(0.0, 0.0, -30.0), -- one panel is big enough for the studio; lowered 30 m from its base at the studio point
}

Config.AdjustControls = {
    rotateLeft = 174,      -- LEFT
    rotateRight = 175,     -- RIGHT
    cameraLeft = 34,       -- A
    cameraRight = 35,      -- D
    moveUp = 27,           -- UP
    moveDown = 173,        -- DOWN
    distanceIn = 241,      -- SCROLL UP
    distanceOut = 242,     -- SCROLL DOWN
    pitchUp = 32,          -- W
    pitchDown = 33,        -- S
    confirm = 191,         -- ENTER
    cancel = 194,          -- BACKSPACE
}

-- Big world props: anything wider, deeper or taller than PropFitSize metres gets a camera fitted to it
-- and a green backdrop wide enough behind it. Set BackdropHeading to 0 if the backdrop shows its back side.
-- PropCamera overrides one model: { distance = 30.0, fov = 40.0 }.
Config.PropFitSize = 3.0
Config.BackdropHeading = 180.0
Config.PropCamera = {}

-- How far the backdrop behind each world prop sits below the prop's centre (metres).
Config.BackdropDrop = -30.0
