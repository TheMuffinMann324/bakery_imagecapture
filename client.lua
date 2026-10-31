local isCapturing = false
local captureTextures = Config.CaptureTextures
local currentCam = nil
local greenScreenProps = {}
local capturePed = nil
local captureEntity = nil
local originalCoords = nil
local originalHeading = nil
local isAdjusting = false
local pendingCapture = nil
local currentCamSettings = nil
local currentVehicleModel = nil

local adjustState = {
    heading = 0.0,
    cameraHeading = 0.0,
    zOffset = 0.0,
    fov = 50.0,
    distance = 0.0,
    pitch = 0.0
}


local function ShowNotification(message, type)
    type = type or 'info'
    SendNUIMessage({
        action = 'notification',
        message = message,
        type = type
    })
end

local function ShowProgress(current, total, itemName, category)
    local text = string.format('[%s] %s', category, itemName)
    SendNUIMessage({
        action = 'showProgress',
        text = text,
        current = current,
        total = total
    })
end

local function HideProgress()
    SendNUIMessage({
        action = 'hideProgress'
    })
end

local function LoadModel(model)
    local hash = type(model) == 'string' and GetHashKey(model) or model
    if not IsModelValid(hash) then
        return false
    end
    RequestModel(hash)
    local timeout = 0
    while not HasModelLoaded(hash) and timeout < 100 do
        Wait(10)
        timeout = timeout + 1
    end
    return HasModelLoaded(hash)
end

local function SetWeatherTime()
    SetRainLevel(0.0)
    SetWeatherTypePersist(Config.Weather)
    SetWeatherTypeNow(Config.Weather)
    SetWeatherTypeNowPersist(Config.Weather)

    NetworkOverrideClockTime(Config.Time.hour, Config.Time.minute, Config.Time.second)

    if Config.FreezeTime then
        NetworkOverrideClockMillisecondsPerGameMinute(999999999)
    end
end


local function GetFileExtension()
    return '.' .. (Config.OutputFormat or 'webp')
end

local function UpdateNUIConfig()
    SendNUIMessage({
        action = 'updateConfig',
        config = {
            greenThreshold = Config.GreenThreshold,
            greenDiff = Config.GreenDiff,
            outputSize = Config.OutputSize,
            outputFormat = Config.OutputFormat or 'webp',
            cropBottom = Config.CropBottom or 80,
            cropRight = Config.CropRight or 80
        }
    })
end

RegisterNUICallback('imageProcessed', function(data, cb)
    if data.success and data.image then
        TriggerServerEvent('sintic-imagecapture:saveImage',
            data.image,
            data.category,
            data.filename
        )
    end
    cb('ok')
end)

RegisterNetEvent('sintic-imagecapture:imageSaved', function(success, filename)
    if pendingCapture then
        pendingCapture(success)
        pendingCapture = nil
    end
end)


local function SetupStudio(withWall)
    local playerPed = PlayerPedId()

    SetWeatherTime()

    originalCoords = GetEntityCoords(playerPed)
    originalHeading = GetEntityHeading(playerPed)

    SetEntityCoords(playerPed, Config.StudioLocation.x, Config.StudioLocation.y, Config.StudioLocation.z + 5.0, false, false, false, false)
    FreezeEntityPosition(playerPed, true)
    SetEntityVisible(playerPed, false, false)

    DisableIdleCamera(true)

    local propHash = GetHashKey(Config.GreenScreenProp)
    LoadModel(propHash)

    if withWall ~= false then
        for _, offset in ipairs(Config.GreenScreenOffsets) do
            local pos = Config.StudioLocation + offset
            local prop = CreateObject(propHash, pos.x, pos.y, pos.z, false, false, false)
            FreezeEntityPosition(prop, true)
            table.insert(greenScreenProps, prop)
        end
    end

    DisplayRadar(false)
    DisplayHud(false)

    UpdateNUIConfig()

    Wait(1000)

    SetWeatherTime()
end

local function CleanupStudio()
    for _, prop in ipairs(greenScreenProps) do
        if DoesEntityExist(prop) then
            DeleteEntity(prop)
        end
    end
    greenScreenProps = {}

    if capturePed and DoesEntityExist(capturePed) then
        DeleteEntity(capturePed)
        capturePed = nil
    end

    if captureEntity and DoesEntityExist(captureEntity) then
        DeleteEntity(captureEntity)
        captureEntity = nil
    end

    if currentCam then
        RenderScriptCams(false, true, 500, true, true)
        DestroyCam(currentCam, true)
        currentCam = nil
    end

    currentCamSettings = nil
    currentVehicleModel = nil

    local playerPed = PlayerPedId()
    if originalCoords then
        SetEntityCoords(playerPed, originalCoords.x, originalCoords.y, originalCoords.z, false, false, false, false)
        SetEntityHeading(playerPed, originalHeading)
    end
    FreezeEntityPosition(playerPed, false)
    SetEntityVisible(playerPed, true, true)

    DisplayRadar(true)
    DisplayHud(true)

    DisableIdleCamera(false)

    if Config.FreezeTime then
        NetworkOverrideClockMillisecondsPerGameMinute(30000) -- Default value
    end

    originalCoords = nil
    originalHeading = nil
    currentCamSettings = nil
    isCapturing = false
    isAdjusting = false
end


local function SetupCamera(entity, camSettings, extraZOffset)
    extraZOffset = extraZOffset or 0.0

    currentCamSettings = camSettings

    if currentCam then
        DestroyCam(currentCam, true)
    end

    local entityCoords = GetEntityCoords(entity)
    local fov = camSettings.fov or 50
    local zOffset = (camSettings.zOffset or 0.0) + extraZOffset
    local distance = camSettings.distance or 1.0

    if isAdjusting then
        zOffset = zOffset + adjustState.zOffset
        distance = distance + adjustState.distance
        fov = adjustState.fov
    end

    if not isAdjusting and camSettings.vehicleHeading then
        SetEntityHeading(entity, camSettings.vehicleHeading)
    end

    local cameraHeading = camSettings.heading or GetEntityHeading(entity)

    local rad = math.rad(cameraHeading + 180)
    local camX = entityCoords.x + math.sin(rad) * distance
    local camY = entityCoords.y + math.cos(rad) * distance
    local camZ = entityCoords.z + zOffset

    local pitch = camSettings.pitch or 0
    if isAdjusting then
        pitch = adjustState.pitch
    end
    local pitchOffset = math.tan(math.rad(pitch)) * distance
    local lookZ = entityCoords.z + zOffset - pitchOffset

    currentCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(currentCam, camX, camY, camZ)
    PointCamAtCoord(currentCam, entityCoords.x, entityCoords.y, lookZ)
    SetCamFov(currentCam, fov)
    SetCamActive(currentCam, true)
    RenderScriptCams(true, true, 500, true, true)

    Wait(500)
end

local function SetupDynamicCamera(entity, entityType, defaultCamSettings)
    if currentCam then
        DestroyCam(currentCam, false)
        SetCamActive(currentCam, false)
        currentCam = nil
    end

    Wait(100)

    local model = GetEntityModel(entity)
    local min, max = GetModelDimensions(model)
    local width = max.x - min.x
    local height = max.z - min.z
    local depth = max.y - min.y
    local maxDim = math.max(width, depth)

    local distance = math.max(maxDim * 1.4, 2.5)

    -- 40-70 range
    local fov = math.max(40, math.min(70, 65 - (maxDim * 3)))

    if defaultCamSettings then
        if defaultCamSettings.distance then
            distance = defaultCamSettings.distance
        end
        if defaultCamSettings.fov then
            fov = defaultCamSettings.fov
        end
    end

    if isAdjusting then
        fov = adjustState.fov
        if defaultCamSettings then
            distance = (defaultCamSettings.distance or distance) + adjustState.distance
        end
    end

    local entityCoords = GetEntityCoords(entity)

    local vehicleHeading = GetEntityHeading(entity)
    if defaultCamSettings and defaultCamSettings.vehicleHeading and not isAdjusting then
        vehicleHeading = defaultCamSettings.vehicleHeading
        SetEntityHeading(entity, vehicleHeading)
    end

    if isAdjusting then
        SetEntityHeading(entity, adjustState.heading)
    end

    local cameraHeading = GetEntityHeading(entity)
    if defaultCamSettings and defaultCamSettings.heading and not isAdjusting then
        cameraHeading = defaultCamSettings.heading
    end

    local zOffset = height * 0.6
    if defaultCamSettings and defaultCamSettings.zOffset then
        zOffset = defaultCamSettings.zOffset
    end
    if isAdjusting then
        zOffset = (defaultCamSettings and defaultCamSettings.zOffset or (height * 0.6)) + adjustState.zOffset
    end

    -- Camera position (behind entity) - use camera heading, not vehicle heading
    local rad = math.rad(cameraHeading + 180)
    local camX = entityCoords.x + math.sin(rad) * distance
    local camY = entityCoords.y + math.cos(rad) * distance
    local camZ = entityCoords.z + zOffset

    local baseLookZ = entityCoords.z + (defaultCamSettings and defaultCamSettings.zOffset or (height * 0.5))
    if isAdjusting and defaultCamSettings then
        baseLookZ = entityCoords.z + defaultCamSettings.zOffset + adjustState.zOffset
    end

    local pitch = 0.0
    if defaultCamSettings and defaultCamSettings.pitch then
        pitch = defaultCamSettings.pitch
    end
    if isAdjusting then
        pitch = adjustState.pitch
    end
    local pitchOffset = math.tan(math.rad(pitch)) * distance
    local lookZ = baseLookZ - pitchOffset

    currentCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(currentCam, camX, camY, camZ)
    PointCamAtCoord(currentCam, entityCoords.x, entityCoords.y, lookZ)
    SetCamFov(currentCam, fov)
    SetCamActive(currentCam, true)
    RenderScriptCams(true, true, 500, true, true)

    Wait(1000)
end


local function CaptureScreenshot(filename, category, callback)
    pendingCapture = callback

    Wait(100)

    exports['screencapture']:requestScreenshot({ encoding = 'png' }, function(data)
        if data then
            SendNUIMessage({
                action = 'processImage',
                image = data,
                filename = filename,
                category = category
            })
        else
            if pendingCapture == callback then
                pendingCapture = nil
                callback(false)
            end
        end
    end)

    SetTimeout(15000, function()
        if pendingCapture == callback then
            pendingCapture = nil
            callback(false)
        end
    end)
end

local function AwaitCapture(filename, category)
    local done = false
    local success = false

    CaptureScreenshot(filename, category, function(result)
        success = result
        done = true
    end)

    local timeout = 0
    while not done and timeout < 150 do
        Wait(100)
        timeout = timeout + 1
    end

    Wait(500)

    return success
end


local function ResetPedComponents(ped)
    SetPedComponentVariation(ped, 0, 0, 1, 0)    -- Head (keep visible)
    SetPedComponentVariation(ped, 1, 0, 0, 0)    -- Mask
    SetPedComponentVariation(ped, 2, -1, 0, 0)   -- Hair - HIDDEN
    SetPedComponentVariation(ped, 3, -1, 0, 0)   -- Torso - HIDDEN
    SetPedComponentVariation(ped, 4, -1, 0, 0)   -- Legs - HIDDEN
    SetPedComponentVariation(ped, 5, 0, 0, 0)    -- Bags
    SetPedComponentVariation(ped, 6, -1, 0, 0)   -- Shoes - HIDDEN
    SetPedComponentVariation(ped, 7, 0, 0, 0)    -- Accessories
    SetPedComponentVariation(ped, 8, -1, 0, 0)   -- Undershirt - HIDDEN
    SetPedComponentVariation(ped, 9, 0, 0, 0)    -- Armor
    SetPedComponentVariation(ped, 10, 0, 0, 0)   -- Decals
    SetPedComponentVariation(ped, 11, -1, 0, 0)  -- Top - HIDDEN

    for i = 0, 7 do
        ClearPedProp(ped, i)
    end
end

local function LoadComponentVariation(ped, component, drawable, texture)
    texture = texture or 0

    SetPedPreloadVariationData(ped, component, drawable, texture)

    local timeout = 0
    while not HasPedPreloadVariationDataFinished(ped) and timeout < 100 do
        Wait(10)
        timeout = timeout + 1
    end

    SetPedComponentVariation(ped, component, drawable, texture, 0)
end

local function LoadPropVariation(ped, propId, drawable, texture)
    texture = texture or 0

    SetPedPreloadPropData(ped, propId, drawable, texture)

    local timeout = 0
    while not HasPedPreloadPropDataFinished(ped) and timeout < 100 do
        Wait(10)
        timeout = timeout + 1
    end

    ClearPedProp(ped, propId)
    SetPedPropIndex(ped, propId, drawable, texture, true)
end

-- hiding head (0) needs 'allowEmptyHeadDrawable true' in F8 (Canary only, won't work on stable)
local function HidePedComponents(ped, componentIds)
    if not DoesEntityExist(ped) or not componentIds or #componentIds == 0 then return end

    for _, componentId in ipairs(componentIds) do
        if componentId == 0 then
            for i = 0, 12 do SetPedHeadOverlay(ped, i, 0, 0.0) end
        end
        SetPedComponentVariation(ped, componentId, -1, 0, 0)
    end

    Wait(50)
end


local function CreateCapturePed(gender)
    local modelName = Config.PedModels[gender]
    local modelHash = GetHashKey(modelName)

    if not LoadModel(modelHash) then
        return nil
    end

    local pos = Config.StudioLocation
    local ped = CreatePed(4, modelHash, pos.x, pos.y, pos.z, 0.0, false, true)

    SetEntityHeading(ped, 0.0)
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdollFromPlayerImpact(ped, false)

    SetPedConfigFlag(ped, 32, true)
    TaskStandStill(ped, -1)
    SetEntityInvincible(ped, true)
    SetEntityRotation(ped, 0.0, 0.0, 0.0, 2, true)

    ResetPedComponents(ped)

    capturePed = ped
    return ped
end


local function AdjustClothing(gender, componentName, drawable)
    if not gender or not componentName or not drawable then
        ShowNotification('Usage: /capture-adjust-clothing [male|female] [component_name] [drawable]')
        return
    end

    if isCapturing or isAdjusting then
        ShowNotification('Already in capture or adjustment mode')
        return
    end

    -- Find component ID by name
    local componentId = nil
    local camSettings = nil
    for id, settings in pairs(Config.ClothingCamera) do
        if settings.name:lower() == componentName:lower() then
            componentId = id
            camSettings = settings
            break
        end
    end

    if not componentId then
        ShowNotification('Invalid component name: ' .. componentName)
        return
    end

    SetupStudio()

    local ped = CreateCapturePed(gender)
    if not ped then
        CleanupStudio()
        return
    end

    -- Set adjusting flag BEFORE starting thread
    isAdjusting = true

    -- Start continuous task clearing thread to prevent ped rotation (same as capture)
    CreateThread(function()
        while isAdjusting and capturePed do
            ClearPedTasksImmediately(capturePed)
            Wait(0)
        end
    end)

    Wait(500)

    -- Match exact capture flow: reset first, then load component
    ResetPedComponents(ped)
    Wait(150)

    -- Load the specific component
    LoadComponentVariation(ped, componentId, tonumber(drawable), 0)
    Wait(100)

    -- Hide components if configured
    if camSettings.hideComponents and #camSettings.hideComponents > 0 then
        HidePedComponents(ped, camSettings.hideComponents)
    end

    -- Ensure entity heading is at 0 (same as capture)
    SetEntityHeading(ped, 0.0)
    SetEntityRotation(ped, 0.0, 0.0, 0.0, 2, true)
    Wait(100)

    -- Initialize adjustment state BEFORE SetupCamera (critical!)
    -- For clothing: entity starts at 0, camera orbit uses config heading
    adjustState.heading = 0.0  -- Entity heading (what left/right arrows control)
    adjustState.zOffset = 0.0
    adjustState.distance = 0.0
    adjustState.fov = camSettings.fov or 50.0

    -- Setup camera (entity heading stays at 0, camera uses config heading)
    SetupCamera(ped, camSettings)
    currentCamSettings = camSettings

    ShowNotification('Clothing adjustment mode ON')

    SendNUIMessage({
        action = 'showControls',
        title = 'ADJUSTMENT MODE - CLOTHING/PROPS',
        controls = {
            { key = '← →', desc = 'Rotate' },
            { key = '↑ ↓', desc = 'Height' },
            { key = 'Scroll', desc = 'Distance' },
            { key = 'Enter', desc = 'Save' },
            { key = 'Backspace', desc = 'Cancel' }
        }
    })

    print(string.format('[Adjust] %s %s #%s | FOV: %.0f Z: %.2f Dist: %.1f Head: %.2f',
        gender, componentName, drawable,
        camSettings.fov or 50,
        camSettings.zOffset or 0,
        camSettings.distance or 1.0,
        camSettings.heading or 0))

    CreateThread(function()
        while isAdjusting do
            local entity = capturePed
            if not entity or not DoesEntityExist(entity) then
                isAdjusting = false
                break
            end

            local valueChanged = false

            -- Rotate left/right (entity rotation)
            if IsControlPressed(0, Config.AdjustControls.rotateLeft) then
                adjustState.heading = (adjustState.heading + 1.0) % 360
                SetEntityHeading(entity, adjustState.heading)
                valueChanged = true
            end

            if IsControlPressed(0, Config.AdjustControls.rotateRight) then
                adjustState.heading = (adjustState.heading - 1.0) % 360
                SetEntityHeading(entity, adjustState.heading)
                valueChanged = true
            end

            -- Z offset
            if IsControlPressed(0, Config.AdjustControls.moveUp) then
                adjustState.zOffset = adjustState.zOffset + 0.01
                valueChanged = true
            end

            if IsControlPressed(0, Config.AdjustControls.moveDown) then
                adjustState.zOffset = adjustState.zOffset - 0.01
                valueChanged = true
            end

            -- Distance
            if IsControlJustPressed(0, Config.AdjustControls.distanceIn) then
                adjustState.distance = adjustState.distance - 0.1
                valueChanged = true
            end

            if IsControlJustPressed(0, Config.AdjustControls.distanceOut) then
                adjustState.distance = adjustState.distance + 0.1
                valueChanged = true
            end

            -- Update camera if values changed
            if valueChanged then
                local entityCoords = GetEntityCoords(entity)
                local distance = (camSettings.distance or 1.0) + adjustState.distance
                local zOffset = (camSettings.zOffset or 0.0) + adjustState.zOffset

                -- For clothing: camera orbit uses config heading (not entity heading)
                -- Entity rotates with left/right arrows, camera stays fixed at config position
                local cameraHeading = camSettings.heading or 0
                local rad = math.rad(cameraHeading + 180)
                local camX = entityCoords.x + math.sin(rad) * distance
                local camY = entityCoords.y + math.cos(rad) * distance
                local camZ = entityCoords.z + zOffset

                SetCamCoord(currentCam, camX, camY, camZ)
                PointCamAtCoord(currentCam, entityCoords.x, entityCoords.y, entityCoords.z + zOffset)
                SetCamFov(currentCam, adjustState.fov)

            end

            -- Confirm
            if IsControlJustPressed(0, Config.AdjustControls.confirm) then
                isAdjusting = false
                SendNUIMessage({ action = 'hideControls' })
                local finalDistance = (camSettings.distance or 1.0) + adjustState.distance
                local finalZOffset = (camSettings.zOffset or 0.0) + adjustState.zOffset

                print(string.format('[Config] [%d] = { name = \'%s\', fov = %.0f, zOffset = %.2f, distance = %.1f, heading = %.2f, hideComponents = %s },',
                    componentId,
                    camSettings.name,
                    adjustState.fov,
                    finalZOffset,
                    finalDistance,
                    camSettings.heading or 0,
                    camSettings.hideComponents and ('{'.. table.concat(camSettings.hideComponents, ', ') ..'}') or '{}'))

                ShowNotification('Config printed to console', 'success')
            end

            -- Cancel
            if IsControlJustPressed(0, Config.AdjustControls.cancel) then
                isAdjusting = false
                SendNUIMessage({ action = 'hideControls' })
                ShowNotification('Adjustment cancelled')
            end

            Wait(0)
        end

        SendNUIMessage({ action = 'hideControls' })
        CleanupStudio()
    end)
end


local function AdjustProp(gender, propName, drawable)
    if not gender or not propName or not drawable then
        ShowNotification('Usage: /capture-adjust-prop [male|female] [prop_name] [drawable]')
        return
    end

    if isCapturing or isAdjusting then
        ShowNotification('Already in capture or adjustment mode')
        return
    end

    -- Find prop ID by name
    local propId = nil
    local camSettings = nil
    for id, settings in pairs(Config.PedPropCamera) do
        if settings.name:lower() == propName:lower() then
            propId = id
            camSettings = settings
            break
        end
    end

    if not propId then
        ShowNotification('Invalid prop name: ' .. propName)
        return
    end

    SetupStudio()

    local ped = CreateCapturePed(gender)
    if not ped then
        CleanupStudio()
        return
    end

    isAdjusting = true

    CreateThread(function()
        while isAdjusting and capturePed do
            ClearPedTasksImmediately(capturePed)
            Wait(0)
        end
    end)

    Wait(500)

    ResetPedComponents(ped)
    Wait(150)

    LoadPropVariation(ped, propId, tonumber(drawable), 0)
    Wait(100)

    if camSettings.hideComponents and #camSettings.hideComponents > 0 then
        HidePedComponents(ped, camSettings.hideComponents)
    end

    SetEntityHeading(ped, 0.0)
    SetEntityRotation(ped, 0.0, 0.0, 0.0, 2, true)
    Wait(100)

    -- For props: entity stays at 0, camera orbit uses config heading (same as clothing)
    adjustState.heading = 0.0  -- Entity heading (what left/right arrows control)
    adjustState.zOffset = 0.0
    adjustState.distance = 0.0
    adjustState.fov = camSettings.fov or 50.0

    SetupCamera(ped, camSettings)
    currentCamSettings = camSettings

    ShowNotification('Prop adjustment mode ON')

    SendNUIMessage({
        action = 'showControls',
        title = 'ADJUSTMENT MODE - CLOTHING/PROPS',
        controls = {
            { key = '← →', desc = 'Rotate' },
            { key = '↑ ↓', desc = 'Height' },
            { key = 'Scroll', desc = 'Distance' },
            { key = 'Enter', desc = 'Save' },
            { key = 'Backspace', desc = 'Cancel' }
        }
    })

    print(string.format('[Adjust] %s %s #%s | FOV: %.0f Z: %.2f Dist: %.1f Head: %.2f',
        gender, propName, drawable,
        camSettings.fov or 50,
        camSettings.zOffset or 0,
        camSettings.distance or 1.0,
        camSettings.heading or 0))

    CreateThread(function()
        while isAdjusting do
            local entity = capturePed
            if not entity or not DoesEntityExist(entity) then
                isAdjusting = false
                break
            end

            local valueChanged = false

            -- Rotate left/right (entity rotation)
            if IsControlPressed(0, Config.AdjustControls.rotateLeft) then
                adjustState.heading = (adjustState.heading + 1.0) % 360
                SetEntityHeading(entity, adjustState.heading)
                valueChanged = true
            end

            if IsControlPressed(0, Config.AdjustControls.rotateRight) then
                adjustState.heading = (adjustState.heading - 1.0) % 360
                SetEntityHeading(entity, adjustState.heading)
                valueChanged = true
            end

            -- Z offset
            if IsControlPressed(0, Config.AdjustControls.moveUp) then
                adjustState.zOffset = adjustState.zOffset + 0.01
                valueChanged = true
            end

            if IsControlPressed(0, Config.AdjustControls.moveDown) then
                adjustState.zOffset = adjustState.zOffset - 0.01
                valueChanged = true
            end

            -- Distance
            if IsControlJustPressed(0, Config.AdjustControls.distanceIn) then
                adjustState.distance = adjustState.distance - 0.1
                valueChanged = true
            end

            if IsControlJustPressed(0, Config.AdjustControls.distanceOut) then
                adjustState.distance = adjustState.distance + 0.1
                valueChanged = true
            end

            -- Update camera if values changed
            if valueChanged then
                local entityCoords = GetEntityCoords(entity)
                local distance = (camSettings.distance or 1.0) + adjustState.distance
                local zOffset = (camSettings.zOffset or 0.0) + adjustState.zOffset

                -- For props: camera orbit uses config heading (same as clothing)
                -- Entity rotates with left/right arrows, camera stays fixed at config position
                local cameraHeading = camSettings.heading or 0
                local rad = math.rad(cameraHeading + 180)
                local camX = entityCoords.x + math.sin(rad) * distance
                local camY = entityCoords.y + math.cos(rad) * distance
                local camZ = entityCoords.z + zOffset

                SetCamCoord(currentCam, camX, camY, camZ)
                PointCamAtCoord(currentCam, entityCoords.x, entityCoords.y, entityCoords.z + zOffset)
                SetCamFov(currentCam, adjustState.fov)
            end

            -- Confirm
            if IsControlJustPressed(0, Config.AdjustControls.confirm) then
                isAdjusting = false
                local finalDistance = (camSettings.distance or 1.0) + adjustState.distance
                local finalZOffset = (camSettings.zOffset or 0.0) + adjustState.zOffset

                print(string.format('[Config] [%d] = { name = \'%s\', fov = %.0f, zOffset = %.2f, distance = %.1f, heading = %.2f, hideComponents = %s },',
                    propId,
                    camSettings.name,
                    adjustState.fov,
                    finalZOffset,
                    finalDistance,
                    camSettings.heading or 0,
                    camSettings.hideComponents and ('{'.. table.concat(camSettings.hideComponents, ', ') ..'}') or '{}'))

                ShowNotification('Config printed to console')
            end

            -- Cancel
            if IsControlJustPressed(0, Config.AdjustControls.cancel) then
                isAdjusting = false
                SendNUIMessage({ action = 'hideControls' })
                ShowNotification('Adjustment cancelled')
            end

            Wait(0)
        end

        SendNUIMessage({ action = 'hideControls' })
        CleanupStudio()
    end)
end


local function CaptureClothing(gender, componentFilter)
    if isCapturing then
        ShowNotification('Capture already in progress')
        return
    end

    isCapturing = true

    SetupStudio()

    local genders = gender == 'all' and {'male', 'female'} or {gender}
    local totalCaptures = 0

    for _, g in ipairs(genders) do
        local ped = CreateCapturePed(g)
        if not ped then
            goto continue_gender
        end

        CreateThread(function()
            while isCapturing and capturePed do
                ClearPedTasksImmediately(capturePed)
                Wait(0)
            end
        end)

        Wait(500)

        local totalItems = 0
        for componentId, camSettings in pairs(Config.ClothingCamera) do
            if not componentFilter or camSettings.name:lower() == componentFilter:lower() then
                totalItems = totalItems + GetNumberOfPedDrawableVariations(ped, componentId)
            end
        end

        local currentItem = 0

        for componentId, camSettings in pairs(Config.ClothingCamera) do
            -- Skip if filter specified and doesn't match
            if componentFilter and camSettings.name:lower() ~= componentFilter:lower() then
                goto continue_component
            end

            local drawableCount = GetNumberOfPedDrawableVariations(ped, componentId)

            for drawable = 0, drawableCount - 1 do
                currentItem = currentItem + 1
                ShowProgress(currentItem, totalItems, string.format('%s %s #%d', g, camSettings.name, drawable), 'Clothing')
                -- 1. Reset all components to hide everything except what we're capturing
                ResetPedComponents(ped)
                Wait(150)

                local textureCount = GetNumberOfPedTextureVariations(ped, componentId, drawable)

                if captureTextures then
                    -- Capture all textures
                    for texture = 0, textureCount - 1 do
                        -- 2. Preload and set ONLY the specific component
                        LoadComponentVariation(ped, componentId, drawable, texture)
                        Wait(100)

                        -- Hide components based on config (e.g., head for masks)
                        if camSettings.hideComponents and #camSettings.hideComponents > 0 then
                            HidePedComponents(ped, camSettings.hideComponents)
                        end

                        -- 3. Setup camera AFTER component is loaded
                        SetupCamera(ped, camSettings)

                        -- 4. Capture
                        local filename = string.format('%s_%s_%d_%d%s', g, camSettings.name, drawable, texture, GetFileExtension())

                        if not isCapturing then goto cleanup end

                        AwaitCapture(filename, 'clothing')
                        totalCaptures = totalCaptures + 1

                        Wait(Config.CaptureDelay)
                    end
                else
                    -- 2. Preload and set ONLY the specific component (texture 0)
                    LoadComponentVariation(ped, componentId, drawable, 0)
                    Wait(100)

                    -- Hide components based on config (e.g., head for masks)
                    if camSettings.hideComponents and #camSettings.hideComponents > 0 then
                        HidePedComponents(ped, camSettings.hideComponents)
                    end

                    -- 3. Setup camera AFTER component is loaded
                    SetupCamera(ped, camSettings)

                    -- 4. Capture
                    local filename = string.format('%s_%s_%d%s', g, camSettings.name, drawable, GetFileExtension())

                    if not isCapturing then goto cleanup end

                    AwaitCapture(filename, 'clothing')
                    totalCaptures = totalCaptures + 1

                    Wait(Config.CaptureDelay)
                end
            end

            ::continue_component::
        end

        -- Delete this ped before creating next
        if capturePed and DoesEntityExist(capturePed) then
            DeleteEntity(capturePed)
            capturePed = nil
        end

        ::continue_gender::
    end

    ::cleanup::
    HideProgress()
    CleanupStudio()
    ShowNotification('Clothing capture complete: ' .. totalCaptures .. ' images')
end


local function CapturePedProps(gender, propFilter)
    if isCapturing then
        ShowNotification('Capture already in progress')
        return
    end

    isCapturing = true

    SetupStudio()

    local genders = gender == 'all' and {'male', 'female'} or {gender}
    local totalCaptures = 0

    for _, g in ipairs(genders) do
        local ped = CreateCapturePed(g)
        if not ped then
            goto continue_gender
        end

        CreateThread(function()
            while isCapturing and capturePed do
                ClearPedTasksImmediately(capturePed)
                Wait(0)
            end
        end)

        Wait(500)

        local totalItems = 0
        for propId, camSettings in pairs(Config.PedPropCamera) do
            if not propFilter or camSettings.name:lower() == propFilter:lower() then
                totalItems = totalItems + GetNumberOfPedPropDrawableVariations(ped, propId)
            end
        end

        local currentItem = 0

        for propId, camSettings in pairs(Config.PedPropCamera) do
            -- Skip if filter specified and doesn't match
            if propFilter and camSettings.name:lower() ~= propFilter:lower() then
                goto continue_prop
            end

            local drawableCount = GetNumberOfPedPropDrawableVariations(ped, propId)

            for drawable = 0, drawableCount - 1 do
                currentItem = currentItem + 1
                ShowProgress(currentItem, totalItems, string.format('%s %s #%d', g, camSettings.name, drawable), 'Props')
                -- 1. Reset all components and props to hide everything except what we're capturing
                ResetPedComponents(ped)
                Wait(150)

                local textureCount = GetNumberOfPedPropTextureVariations(ped, propId, drawable)

                if captureTextures then
                    -- Capture all textures
                    for texture = 0, textureCount - 1 do
                        -- 2. Preload and set ONLY the specific prop
                        LoadPropVariation(ped, propId, drawable, texture)
                        Wait(100)

                        -- Hide components based on config (e.g., head & hair for hats/ears)
                        if camSettings.hideComponents then
                            HidePedComponents(ped, camSettings.hideComponents)
                        end

                        -- 3. Setup camera AFTER prop is loaded
                        SetupCamera(ped, camSettings)

                        -- 4. Capture
                        local filename = string.format('%s_prop_%s_%d_%d%s', g, camSettings.name, drawable, texture, GetFileExtension())

                        if not isCapturing then goto cleanup end

                        AwaitCapture(filename, 'props')
                        totalCaptures = totalCaptures + 1

                        Wait(Config.CaptureDelay)
                    end
                else
                    -- 2. Preload and set ONLY the specific prop (texture 0)
                    LoadPropVariation(ped, propId, drawable, 0)
                    Wait(100)

                    -- Hide components based on config (e.g., head & hair for hats/ears)
                    if camSettings.hideComponents then
                        HidePedComponents(ped, camSettings.hideComponents)
                    end

                    -- 3. Setup camera AFTER prop is loaded
                    SetupCamera(ped, camSettings)

                    -- 4. Capture
                    local filename = string.format('%s_prop_%s_%d%s', g, camSettings.name, drawable, GetFileExtension())

                    if not isCapturing then goto cleanup end

                    AwaitCapture(filename, 'props')
                    totalCaptures = totalCaptures + 1

                    Wait(Config.CaptureDelay)
                end
            end

            ::continue_prop::
        end

        -- Delete this ped before creating next
        if capturePed and DoesEntityExist(capturePed) then
            DeleteEntity(capturePed)
            capturePed = nil
        end

        ::continue_gender::
    end

    ::cleanup::
    HideProgress()
    CleanupStudio()
    ShowNotification('Ped props capture complete: ' .. totalCaptures .. ' images')
end


local function CaptureVehicle(modelName, onDone)
    if isCapturing then
        ShowNotification('Capture already in progress')
        if onDone then onDone(false) end
        return
    end

    isCapturing = true

    SetupStudio()

    local totalCaptures = 0

    local function CaptureOneVehicle(model)
        local hash = GetHashKey(model)

        if not IsModelAVehicle(hash) then
            ShowNotification('Not a valid vehicle: ' .. model)
            return false
        end

        if not LoadModel(hash) then
            ShowNotification('Failed to load vehicle: ' .. model)
            return false
        end

        local camSettings = Config.VehicleCamera[model] or Config.DefaultVehicleCamera
        currentCamSettings = camSettings

        local pos = Config.StudioLocation
        local vehicle = CreateVehicle(hash, pos.x, pos.y, pos.z + 5.0, camSettings.vehicleHeading, false, false)
        -- SetVehicleSteerBias(vehicle, -1.0) 0 -- SHIT IS NOT WORKING FUCK NATIVES

        if not DoesEntityExist(vehicle) then
            ShowNotification('Failed to create vehicle: ' .. model)
            return false
        end

        captureEntity = vehicle
        currentVehicleModel = model
        FreezeEntityPosition(vehicle, true)
        SetVehicleOnGroundProperly(vehicle)
        SetVehicleWindowTint(vehicle, 1)

        Wait(100)

        if camSettings.vehicleHeading then
            SetEntityHeading(vehicle, camSettings.vehicleHeading)
        end

        SetupCamera(vehicle, camSettings)

        Wait(500)

        local filename = model .. GetFileExtension()

        if not isCapturing then
            if DoesEntityExist(vehicle) then
                DeleteEntity(vehicle)
            end
            captureEntity = nil
            return false
        end

        if AwaitCapture(filename, 'vehicles') then
            totalCaptures = totalCaptures + 1
        end

        Wait(500)

        if DoesEntityExist(vehicle) then
            DeleteEntity(vehicle)
        end
        captureEntity = nil

        Wait(Config.CaptureDelay)
        return true
    end

    if modelName and modelName ~= 'all' then
        CaptureOneVehicle(modelName)
    else
        ShowNotification('Please specify a vehicle model name')
    end

    CleanupStudio()
    ShowNotification('Vehicle capture complete: ' .. totalCaptures .. ' images')
    if onDone then onDone(totalCaptures > 0) end
end


-- Big props get a green backdrop behind them, wide and tall enough to fill the frame from the camera
-- distance used. Screens are sized from the model; the heading is the camera's, flipped to face it.
local function SpawnPropBackdrop(entity, camDistance, fov, size)
    local screenHash = GetHashKey(Config.GreenScreenProp)
    local smin, smax = GetModelDimensions(screenHash)
    local sw = math.max(smax.x - smin.x, 0.5)
    local sh = math.max(smax.z - smin.z, 0.5)

    local heading = GetEntityHeading(entity)
    local rad = math.rad(heading + 180)
    local view = vector3(-math.sin(rad), -math.cos(rad), 0.0)      -- camera -> prop
    local across = vector3(math.cos(rad), -math.sin(rad), 0.0)     -- across the view
    local min, max = GetModelDimensions(GetEntityModel(entity))
    local c = GetEntityCoords(entity)
    local centreZ = c.z + (min.z + max.z) / 2 + Config.BackdropDrop

    local camPos = c - view * camDistance
    local backDist = camDistance + size * 0.5 + 1.0
    local span = 2.0 * backDist * math.tan(math.rad(fov / 2)) * 1.15
    local cols = math.ceil(span / sw)
    local rows = math.ceil(span / sh)
    local centre = camPos + view * backDist

    for col = 0, cols - 1 do
        for row = 0, rows - 1 do
            local across_offset = (col - (cols - 1) / 2) * sw
            local up_offset = (row - (rows - 1) / 2) * sh
            local p = centre + across * across_offset
            local screen = CreateObject(screenHash, p.x, p.y, centreZ + up_offset, false, false, false)
            FreezeEntityPosition(screen, true)
            SetEntityHeading(screen, -heading + Config.BackdropHeading)
            table.insert(greenScreenProps, screen)
        end
    end
end

local function CaptureWorldProp(modelName, onDone)
    if isCapturing then
        ShowNotification('Capture already in progress')
        if onDone then onDone(false) end
        return
    end

    if not modelName then
        ShowNotification('Please specify a prop model name')
        if onDone then onDone(false) end
        return
    end

    isCapturing = true

    SetupStudio(false)

    local hash = GetHashKey(modelName)

    if not LoadModel(hash) then
        ShowNotification('Failed to load model: ' .. modelName)
        CleanupStudio()
        if onDone then onDone(false) end
        return
    end

    local pos = Config.StudioLocation
    local prop = CreateObject(hash, pos.x, pos.y, pos.z + 10.0, false, false, false)

    if not DoesEntityExist(prop) then
        ShowNotification('Failed to create prop: ' .. modelName)
        CleanupStudio()
        if onDone then onDone(false) end
        return
    end

    captureEntity = prop
    FreezeEntityPosition(prop, true)
    SetEntityHeading(prop, 25.0) -- Good viewing angle

    Wait(1000)

    -- Every world prop gets a camera that fills about 70% of the frame, and a backdrop placed behind
    -- the prop itself, so the backdrop follows each prop instead of sitting at a fixed spot.
    local min, max = GetModelDimensions(GetEntityModel(prop))
    local size = math.max(max.x - min.x, max.y - min.y, max.z - min.z)
    local override = Config.PropCamera and Config.PropCamera[modelName]
    local camSettings = override
    if not camSettings then
        local fov = 40.0
        camSettings = { fov = fov, distance = math.max((size * 0.5) / 0.7 / math.tan(math.rad(fov / 2)), 2.5) }
    end
    SetupDynamicCamera(prop, 'prop', camSettings)
    SpawnPropBackdrop(prop, camSettings.distance, camSettings.fov or 40.0, size)

    -- Extra wait before capture
    Wait(500)

    local filename = modelName .. GetFileExtension()

    local saved = AwaitCapture(filename, 'worldprops')

    Wait(500)

    if DoesEntityExist(prop) then
        DeleteEntity(prop)
    end
    captureEntity = nil

    CleanupStudio()
    ShowNotification('Prop capture complete: ' .. modelName)
    if onDone then onDone(saved) end
end


local function UpdateVehicleAdjustmentCamera(camSettings, baseCameraHeading)
    if not currentCam or not camSettings then return end

    local entity = captureEntity
    if not entity or not DoesEntityExist(entity) then return end

    local entityCoords = GetEntityCoords(entity)
    local distance = (camSettings.distance or 5.0) + adjustState.distance

    -- Calculate zOffset
    local model = GetEntityModel(entity)
    local min, max = GetModelDimensions(model)
    local height = max.z - min.z
    local zOffset = (camSettings.zOffset or (height * 0.6)) + adjustState.zOffset

    SetEntityHeading(entity, adjustState.heading)

    local finalCameraHeading = baseCameraHeading + adjustState.cameraHeading
    local rad = math.rad(finalCameraHeading + 180)
    local camX = entityCoords.x + math.sin(rad) * distance
    local camY = entityCoords.y + math.cos(rad) * distance
    local camZ = entityCoords.z + zOffset

    -- Calculate look at point based on pitch
    -- Pitch: positive = looking down, negative = looking up
    local baseLookZ = entityCoords.z + (camSettings.zOffset or (height * 0.5)) + adjustState.zOffset
    local pitchOffset = math.tan(math.rad(adjustState.pitch)) * distance
    local lookZ = baseLookZ - pitchOffset

    -- Update camera
    SetCamCoord(currentCam, camX, camY, camZ)
    PointCamAtCoord(currentCam, entityCoords.x, entityCoords.y, lookZ)
    SetCamFov(currentCam, adjustState.fov)
end

local function AdjustVehicle(modelName)
    if not modelName then
        ShowNotification('Usage: /capture-adjust-vehicle [model_name]')
        return
    end

    if isCapturing or isAdjusting then
        ShowNotification('Already in capture or adjustment mode')
        return
    end

    local hash = GetHashKey(modelName)

    if not IsModelAVehicle(hash) then
        ShowNotification('Not a valid vehicle: ' .. modelName)
        return
    end

    if not LoadModel(hash) then
        ShowNotification('Failed to load vehicle: ' .. modelName)
        return
    end

    SetupStudio()

    local camSettings = Config.VehicleCamera[modelName] or Config.DefaultVehicleCamera
    currentCamSettings = camSettings

    local pos = Config.StudioLocation
    local vehicle = CreateVehicle(hash, pos.x, pos.y, pos.z + 5.0, camSettings.heading, false, false)
    -- SetVehicleSteerBias(vehicle, -1.0) 0 -- SHIT IS NOT WORKING FUCK NATIVES

    if not DoesEntityExist(vehicle) then
        ShowNotification('Failed to create vehicle: ' .. modelName)
        CleanupStudio()
        return
    end

    captureEntity = vehicle
    currentVehicleModel = modelName
    FreezeEntityPosition(vehicle, true)
    SetVehicleOnGroundProperly(vehicle)
    SetVehicleWindowTint(vehicle, 1)

    Wait(1000)

    SetupDynamicCamera(vehicle, 'vehicle', camSettings)

    local baseCameraHeading = camSettings.heading or GetEntityHeading(vehicle)
    local baseVehicleHeading = camSettings.vehicleHeading or 0

    local entity = captureEntity
    adjustState.heading = baseVehicleHeading        -- Vehicle rotation (from config)
    adjustState.cameraHeading = 0.0                 -- Camera orbit (delta from config)
    adjustState.zOffset = 0.0
    adjustState.distance = 0.0
    adjustState.fov = camSettings.fov or 50.0
    adjustState.pitch = camSettings.pitch or 0.0

    isAdjusting = true
    ShowNotification('Vehicle adjustment mode ON - Use arrows to adjust, Enter to save, Backspace to cancel')

    print(string.format('[Adjust] Vehicle: %s | FOV: %.0f Z: %.2f Dist: %.1f Head: %.0f',
        modelName,
        currentCamSettings.fov or 50,
        currentCamSettings.zOffset or 0.0,
        currentCamSettings.distance or 5.0,
        currentCamSettings.heading or 25))

    CreateThread(function()
        while isAdjusting do
            local entity = captureEntity
            if not entity or not DoesEntityExist(entity) then
                isAdjusting = false
                break
            end

            local valueChanged = false

            -- Vehicle rotation controls
            if IsControlPressed(0, Config.AdjustControls.rotateLeft) then
                adjustState.heading = (adjustState.heading - 1.0) % 360
                valueChanged = true
            end

            if IsControlPressed(0, Config.AdjustControls.rotateRight) then
                adjustState.heading = (adjustState.heading + 1.0) % 360
                valueChanged = true
            end

            -- Camera orbit controls (A/D)
            if IsControlPressed(0, Config.AdjustControls.cameraLeft) then
                adjustState.cameraHeading = (adjustState.cameraHeading - 1.0) % 360
                valueChanged = true
            end

            if IsControlPressed(0, Config.AdjustControls.cameraRight) then
                adjustState.cameraHeading = (adjustState.cameraHeading + 1.0) % 360
                valueChanged = true
            end

            -- Z offset controls
            if IsControlPressed(0, Config.AdjustControls.moveUp) then
                adjustState.zOffset = adjustState.zOffset + 0.01
                valueChanged = true
            end

            if IsControlPressed(0, Config.AdjustControls.moveDown) then
                adjustState.zOffset = adjustState.zOffset - 0.01
                valueChanged = true
            end

            -- Distance controls
            if IsControlJustPressed(0, Config.AdjustControls.distanceIn) then
                adjustState.distance = adjustState.distance - 1.0
                valueChanged = true
            end

            if IsControlJustPressed(0, Config.AdjustControls.distanceOut) then
                adjustState.distance = adjustState.distance + 1.0
                valueChanged = true
            end

            -- Pitch controls (vertical angle)
            if IsControlPressed(0, Config.AdjustControls.pitchUp) then
                adjustState.pitch = math.min(adjustState.pitch + 1.0, 89.0)  -- Max 89 degrees down
                valueChanged = true
            end

            if IsControlPressed(0, Config.AdjustControls.pitchDown) then
                adjustState.pitch = math.max(adjustState.pitch - 1.0, -89.0)  -- Max 89 degrees up
                valueChanged = true
            end

            -- Update camera with new settings
            if valueChanged then
                UpdateVehicleAdjustmentCamera(currentCamSettings, baseCameraHeading)
            end

            -- Confirm
            if IsControlJustPressed(0, Config.AdjustControls.confirm) then
                isAdjusting = false
                local finalDistance = (currentCamSettings.distance or 5.0) + adjustState.distance
                local finalZOffset = (currentCamSettings.zOffset or 0.0) + adjustState.zOffset
                local finalCameraHeading = (baseCameraHeading + adjustState.cameraHeading) % 360

                print(string.format('[Config] [\'%s\'] = { fov = %.0f, zOffset = %.2f, distance = %.1f, heading = %.0f, vehicleHeading = %.0f, pitch = %.0f },',
                    currentVehicleModel,
                    adjustState.fov,
                    finalZOffset,
                    finalDistance,
                    finalCameraHeading,
                    adjustState.heading,
                    adjustState.pitch))

                ShowNotification('Config printed to console')
            end

            -- Cancel
            if IsControlJustPressed(0, Config.AdjustControls.cancel) then
                isAdjusting = false
                ShowNotification('Adjustment cancelled')
            end

            Wait(0)
        end

        -- Cleanup when exiting adjustment mode
        CleanupStudio()
    end)
end


RegisterCommand('capture-clothing', function(source, args)
    local gender = args[1] or 'all'
    local component = args[2] or nil

    if gender ~= 'male' and gender ~= 'female' and gender ~= 'all' then
        ShowNotification('Usage: /capture-clothing [male|female|all] [component]')
        return
    end

    CreateThread(function()
        CaptureClothing(gender, component)
    end)
end, false)

RegisterCommand('capture-ped-props', function(source, args)
    local gender = args[1] or 'all'
    local prop = args[2] or nil

    if gender ~= 'male' and gender ~= 'female' and gender ~= 'all' then
        ShowNotification('Usage: /capture-ped-props [male|female|all] [prop]')
        return
    end

    CreateThread(function()
        CapturePedProps(gender, prop)
    end)
end, false)

RegisterCommand('capture-vehicles', function(source, args)
    local model = args[1] or nil

    CreateThread(function()
        CaptureVehicle(model)
    end)
end, false)

RegisterCommand('capture-props', function(source, args)
    local model = args[1] or nil

    if not model then
        ShowNotification('Usage: /capture-props [model_name]')
        return
    end

    CreateThread(function()
        CaptureWorldProp(model)
    end)
end, false)

RegisterCommand('capture-textures', function(source, args)
    local toggle = args[1]

    if toggle == 'on' then
        captureTextures = true
        ShowNotification('Texture capture: ON')
    elseif toggle == 'off' then
        captureTextures = false
        ShowNotification('Texture capture: OFF')
    else
        ShowNotification('Usage: /capture-textures [on|off]')
    end
end, false)

RegisterCommand('capture-adjust-clothing', function(source, args)
    local gender = args[1] or nil
    local component = args[2] or nil
    local drawable = args[3] or nil

    CreateThread(function()
        AdjustClothing(gender, component, drawable)
    end)
end, false)

RegisterCommand('capture-adjust-prop', function(source, args)
    local gender = args[1] or nil
    local prop = args[2] or nil
    local drawable = args[3] or nil

    CreateThread(function()
        AdjustProp(gender, prop, drawable)
    end)
end, false)

RegisterCommand('capture-adjust-vehicle', function(source, args)
    local model = args[1] or nil

    CreateThread(function()
        AdjustVehicle(model)
    end)
end, false)

RegisterCommand('capture-all-vehicles', function()
    if isCapturing then
        ShowNotification('Capture already in progress')
        return
    end

    CreateThread(function()
        local vehicleList = LoadResourceFile(GetCurrentResourceName(), 'in/vehicles.lua')
        if not vehicleList then
            ShowNotification('Error: in/vehicles.lua not found')
            return
        end

        -- Parse the Lua table
        local func, err = load('return ' .. vehicleList)
        if not func then
            ShowNotification('Error parsing vehicles.lua: ' .. tostring(err))
            return
        end

        local vehicles = func()
        if not vehicles or type(vehicles) ~= 'table' then
            ShowNotification('Error: vehicles.lua must return a table')
            return
        end

        isCapturing = true
        SetupStudio()

        local totalCaptures = 0

        ShowNotification('Starting batch capture of ' .. #vehicles .. ' vehicles...')

        for i, model in ipairs(vehicles) do
            if not isCapturing then break end

            ShowProgress(i, #vehicles, model, 'Vehicles')
            print(string.format('[Batch] Capturing vehicle %d/%d: %s', i, #vehicles, model))

            -- Capture this vehicle
            local hash = GetHashKey(model)

            -- Check if vehicle has specific camera config, otherwise use default
            local camSettings = Config.VehicleCamera[model] or Config.DefaultVehicleCamera
            currentCamSettings = camSettings

            if IsModelAVehicle(hash) and LoadModel(hash) then
                local pos = Config.StudioLocation
                local vehicle = CreateVehicle(hash, pos.x, pos.y, pos.z + 5.0, camSettings.vehicleHeading, false, false)
                -- SetVehicleSteerBias(vehicle, -1.0) 0 -- SHIT IS NOT WORKING FUCK NATIVES

                if DoesEntityExist(vehicle) then
                    captureEntity = vehicle
                    currentVehicleModel = model
                    FreezeEntityPosition(vehicle, true)
                    SetVehicleOnGroundProperly(vehicle)
                    SetVehicleWindowTint(vehicle, 1)

                    Wait(100)

                    -- Set vehicle heading from config
                    if camSettings.vehicleHeading then
                        SetEntityHeading(vehicle, camSettings.vehicleHeading)
                    end

                    -- Setup camera with config settings
                    SetupCamera(vehicle, camSettings)

                    Wait(500)

                    local filename = model .. GetFileExtension()
                    AwaitCapture(filename, 'vehicles')
                    totalCaptures = totalCaptures + 1

                    Wait(500)

                    -- Delete vehicle
                    if DoesEntityExist(vehicle) then
                        DeleteEntity(vehicle)
                    end
                    captureEntity = nil

                    Wait(Config.CaptureDelay)
                else
                    ShowNotification('Failed to create vehicle: ' .. model)
                end

                SetModelAsNoLongerNeeded(hash)
            else
                ShowNotification('Not a valid vehicle: ' .. model)
            end
        end

        HideProgress()
        CleanupStudio()
        ShowNotification('Batch vehicle capture complete: ' .. totalCaptures .. ' images')
    end)
end, false)

RegisterCommand('capture-all-props', function()
    if isCapturing then
        ShowNotification('Capture already in progress')
        return
    end

    CreateThread(function()
        local propList = LoadResourceFile(GetCurrentResourceName(), 'in/props.lua')
        if not propList then
            ShowNotification('Error: in/props.lua not found')
            return
        end

        -- Parse the Lua table
        local func, err = load('return ' .. propList)
        if not func then
            ShowNotification('Error parsing props.lua: ' .. tostring(err))
            return
        end

        local props = func()
        if not props or type(props) ~= 'table' then
            ShowNotification('Error: props.lua must return a table')
            return
        end

        isCapturing = true
        SetupStudio()

        local totalCaptures = 0

        ShowNotification('Starting batch capture of ' .. #props .. ' props...')

        for i, model in ipairs(props) do
            if not isCapturing then break end

            ShowProgress(i, #props, model, 'Props')
            print(string.format('[Batch] Capturing prop %d/%d: %s', i, #props, model))

            -- Capture this prop
            local hash = GetHashKey(model)

            if LoadModel(hash) then
                local pos = Config.StudioLocation
                local prop = CreateObject(hash, pos.x, pos.y, pos.z + 10.0, false, false, false)

                if DoesEntityExist(prop) then
                    captureEntity = prop
                    FreezeEntityPosition(prop, true)
                    SetEntityHeading(prop, 25.0)

                    Wait(1000)

                    -- Setup camera
                    SetupDynamicCamera(prop, 'prop')

                    Wait(500)

                    local filename = model .. GetFileExtension()
                    AwaitCapture(filename, 'worldprops')
                    totalCaptures = totalCaptures + 1

                    Wait(500)

                    -- Delete prop
                    if DoesEntityExist(prop) then
                        DeleteEntity(prop)
                    end
                    captureEntity = nil

                    Wait(Config.CaptureDelay)
                else
                    ShowNotification('Failed to create prop: ' .. model)
                end

                SetModelAsNoLongerNeeded(hash)
            else
                ShowNotification('Failed to load model: ' .. model)
            end
        end

        HideProgress()
        CleanupStudio()
        ShowNotification('Batch prop capture complete: ' .. totalCaptures .. ' images')
    end)
end, false)

CreateThread(function()
    while true do
        Wait(0)
        if isCapturing and not isAdjusting then
            if IsControlJustPressed(0, Config.AdjustControls.cancel) then
                isCapturing = false
                ShowNotification('Capture stopped')
                HideProgress()
            end
        else
            Wait(100)
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        CleanupStudio()
    end
end)

CreateThread(function()
    TriggerEvent('chat:addSuggestion', '/capture-clothing', 'Capture clothing images', {
        { name = 'gender', help = 'male / female / all' },
        { name = 'component', help = 'face, mask, hair, torso, legs, bag, shoes, accessory, undershirt, armor, decals, top' }
    })

    TriggerEvent('chat:addSuggestion', '/capture-ped-props', 'Capture ped prop images (hats, glasses, etc)', {
        { name = 'gender', help = 'male / female / all' },
        { name = 'prop', help = 'hat, glasses, ears, watch, bracelet' }
    })

    TriggerEvent('chat:addSuggestion', '/capture-vehicles', 'Capture vehicle images', {
        { name = 'model', help = 'Vehicle model name (e.g. adder, zentorno)' }
    })

    TriggerEvent('chat:addSuggestion', '/capture-props', 'Capture world prop images', {
        { name = 'model', help = 'Prop model name (e.g. prop_chair_01a)' }
    })

    TriggerEvent('chat:addSuggestion', '/capture-textures', 'Toggle texture variation capture', {
        { name = 'toggle', help = 'on / off' }
    })

    TriggerEvent('chat:addSuggestion', '/capture-adjust-clothing', 'Adjust camera settings for specific clothing item', {
        { name = 'gender', help = 'male / female' },
        { name = 'component', help = 'face, mask, hair, torso, legs, bag, shoes, accessory, undershirt, armor, decals, top' },
        { name = 'drawable', help = 'Drawable ID number' }
    })

    TriggerEvent('chat:addSuggestion', '/capture-adjust-prop', 'Adjust camera settings for specific prop', {
        { name = 'gender', help = 'male / female' },
        { name = 'prop', help = 'hat, glasses, ears, watch, bracelet' },
        { name = 'drawable', help = 'Drawable ID number' }
    })

    TriggerEvent('chat:addSuggestion', '/capture-adjust-vehicle', 'Adjust vehicle camera settings', {
        { name = 'model', help = 'Vehicle model name' }
    })

    TriggerEvent('chat:addSuggestion', '/capture-all-vehicles', 'Capture all vehicles from in/vehicles.lua', {})

    TriggerEvent('chat:addSuggestion', '/capture-all-props', 'Capture all props from in/props.lua', {})
end)

-- Exports for other resources (bakery_racing). Takes one picture and calls onDone(true) only once
-- the image file has been written, or onDone(false) if it wasn't.
exports('CaptureVehicle', function(modelName, onDone)
    CreateThread(function() CaptureVehicle(modelName, onDone) end)
end)

exports('CaptureProp', function(modelName, onDone)
    CreateThread(function() CaptureWorldProp(modelName, onDone) end)
end)
