-------------------------------------------------
-- X1S CarPlay - Radio Item / Install
-------------------------------------------------
X1SRadio = {}

X1SRadio.Framework = "standalone" -- KEEP STANDALONE

-------------------------------------------------
-- Small helpers
-------------------------------------------------
local function NormalizePlate(plate)
    if type(plate) ~= "string" then return nil end
    plate = plate:gsub("^%s+", ""):gsub("%s+$", "")
    if plate == "" then return nil end
    return plate
end

local function GetPlateFromVehicle(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return nil end
    return NormalizePlate(GetVehicleNumberPlateText(veh))
end

local function GetStandaloneIdentifier(src)
    local id = GetPlayerIdentifierByType(src, "license")
    return id or ("src:" .. tostring(src))
end

local function NotifyPlayer(src, kind, message)
    TriggerClientEvent("x1s:notify", src, kind, message)
end

-------------------------------------------------
-- oxmysql
-------------------------------------------------
local oxmysqlAvailable = GetResourceState("oxmysql") == "started"
local radioSystemActive = (Config.Radio and Config.Radio.RequireInstall) and oxmysqlAvailable or false

if Config.Radio and Config.Radio.RequireInstall and not oxmysqlAvailable then
    print("^1[X1S-CarPlay]^0 Config.Radio.RequireInstall is on but the 'oxmysql' "
        .. "resource isn't running. The radio-install requirement is DISABLED until "
        .. "oxmysql is installed and started - CarPlay will work normally in every "
        .. "vehicle in the meantime. Either start oxmysql, or set "
        .. "Config.Radio.RequireInstall = false in config.lua to silence this.")
end

-------------------------------------------------
-- Database helpers
-------------------------------------------------
local function DbQuery(sql, params)
    local ok, result = pcall(function()
        local p = promise.new()
        exports.oxmysql:query(sql, params or {}, function(queryResult)
            p:resolve(queryResult)
        end)
        return Citizen.Await(p)
    end)
    if not ok then
        print(("^1[X1S-CarPlay]^0 Database query failed: %s"):format(tostring(result)))
        return nil
    end
    return result
end

local function DbScalar(sql, params)
    local ok, result = pcall(function()
        local p = promise.new()
        exports.oxmysql:scalar(sql, params or {}, function(queryResult)
            p:resolve(queryResult)
        end)
        return Citizen.Await(p)
    end)
    if not ok then
        print(("^1[X1S-CarPlay]^0 Database query failed: %s"):format(tostring(result)))
        return nil
    end
    return result
end

-------------------------------------------------
-- Framework Detection
-------------------------------------------------
local ESX = nil
local QBCore = nil
local usingOxInventory = false

local function InitFrameworkBridge()
    if GetResourceState("qb-core") == "started" then
        local ok, core = pcall(function() return exports["qb-core"]:GetCoreObject() end)
        if ok and core then
            QBCore = core
            X1SRadio.Framework = "qbcore"
        end
    elseif GetResourceState("es_extended") == "started" then
        local ok, core = pcall(function() return exports["es_extended"]:getSharedObject() end)
        if ok and core then
            ESX = core
            X1SRadio.Framework = "esx"
        end
    end

    usingOxInventory = GetResourceState("ox_inventory") == "started"

    print(("^2[X1S-CarPlay]^0 Radio item bridge: framework=^3%s^0, ox_inventory=^3%s^0, active=^3%s^0")
        :format(X1SRadio.Framework, tostring(usingOxInventory), tostring(radioSystemActive)))
end

-------------------------------------------------
-- Persistence
-------------------------------------------------
local installedCache = {}

if radioSystemActive then
    CreateThread(function()
        Wait(500)

        DbQuery([[
            CREATE TABLE IF NOT EXISTS x1s_carplay_radios (
                plate VARCHAR(12) NOT NULL PRIMARY KEY,
                installed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
        ]])

        DbQuery([[
            CREATE TABLE IF NOT EXISTS x1s_carplay_standalone_items (
                identifier VARCHAR(64) NOT NULL PRIMARY KEY,
                radio_count INT NOT NULL DEFAULT 0
            )
        ]])

        local rows = DbQuery("SELECT plate FROM x1s_carplay_radios")
        for _, row in ipairs(rows or {}) do
            installedCache[row.plate] = true
        end
    end)
end

function X1SRadio.IsInstalled(plate)
    if not radioSystemActive then return true end
    if not plate then return false end
    if installedCache[plate] then return true end

    local row = DbScalar("SELECT 1 FROM x1s_carplay_radios WHERE plate = ?", { plate })
    if row then
        installedCache[plate] = true
        return true
    end
    return false
end

local function MarkInstalled(plate)
    local result = DbQuery(
        "INSERT INTO x1s_carplay_radios (plate) VALUES (?) ON DUPLICATE KEY UPDATE plate = plate",
        { plate }
    )
    if result == nil then
        print(("^1[X1S-CarPlay]^0 Failed to save the radio install for plate '%s' - "
            .. "it will NOT survive a restart until this is fixed. See the database "
            .. "error printed above."):format(plate))
        return false
    end
    installedCache[plate] = true
    return true
end

-------------------------------------------------
-- Item Removal
-------------------------------------------------
function X1SRadio.RemoveItem(src, itemName)
    if usingOxInventory then
        local ok, removed = pcall(function()
            return exports.ox_inventory:RemoveItem(src, itemName, 1)
        end)
        return ok and removed and true or false
    end

    if X1SRadio.Framework == "esx" and ESX then
        local xPlayer = ESX.GetPlayerFromId(src)
        if not xPlayer then return false end
        local item = xPlayer.getInventoryItem(itemName)
        if not item or (item.count or 0) < 1 then return false end
        xPlayer.removeInventoryItem(itemName, 1)
        return true
    end

    if X1SRadio.Framework == "qbcore" and QBCore then
        local Player = QBCore.Functions.GetPlayer(src)
        if not Player then return false end
        local item = Player.Functions.GetItemByName(itemName)
        if not item or (item.amount or 0) < 1 then return false end
        Player.Functions.RemoveItem(itemName, 1)
        TriggerClientEvent("inventory:client:ItemBox", src, item, "remove")
        return true
    end

    -- Standalone: our own ledger.
    local identifier = GetStandaloneIdentifier(src)
    local count = DbScalar(
        "SELECT radio_count FROM x1s_carplay_standalone_items WHERE identifier = ?", { identifier }
    )
    if not count or count < 1 then return false end
    DbQuery(
        "UPDATE x1s_carplay_standalone_items SET radio_count = radio_count - 1 WHERE identifier = ?",
        { identifier }
    )
    return true
end

-------------------------------------------------
-- Begin Install
-------------------------------------------------
local pendingInstalls = {} -- [src] = { net, plate, itemName, removeOnFinish, startedAt }

function X1SRadio.TryBeginInstall(src, itemName, removeOnFinish)
    if not radioSystemActive then
        NotifyPlayer(src, "error", "Radio installation isn't enabled on this server.")
        return false, "inactive"
    end

    itemName = itemName or Config.Radio.Item
    if removeOnFinish == nil then removeOnFinish = true end

    if pendingInstalls[src] then
        NotifyPlayer(src, "error", "You're already installing a radio.")
        return false, "already_installing"
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false, "no_ped" end

    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then
        NotifyPlayer(src, "error", "You need to be seated in a vehicle to install a radio.")
        return false, "not_in_vehicle"
    end

    if Config.Radio.InstallDriverOnly and GetPedInVehicleSeat(veh, -1) ~= ped then
        NotifyPlayer(src, "error", "You need to be in the driver's seat to install a radio.")
        return false, "not_driver"
    end

    local plate = GetPlateFromVehicle(veh)
    if not plate then
        NotifyPlayer(src, "error", "Couldn't read this vehicle's plate.")
        return false, "no_plate"
    end

    if X1SRadio.IsInstalled(plate) then
        NotifyPlayer(src, "error", "This vehicle already has a radio installed.")
        return false, "already_installed"
    end

    local net = NetworkGetNetworkIdFromEntity(veh)

    pendingInstalls[src] = {
        net = net,
        plate = plate,
        itemName = itemName,
        removeOnFinish = removeOnFinish,
        startedAt = GetGameTimer()
    }

    TriggerClientEvent("x1s:radio:beginInstall", src, net, Config.Radio.InstallTime)
    return true
end

RegisterNetEvent("x1s:radio:finishInstall", function(net)
    local src = source
    local pending = pendingInstalls[src]
    pendingInstalls[src] = nil

    if not pending or pending.net ~= net then return end

    local veh = NetworkGetEntityFromNetworkId(net)
    local plate = GetPlateFromVehicle(veh)

    if not plate or plate ~= pending.plate then
        NotifyPlayer(src, "error", "Installation cancelled.")
        return
    end

    if X1SRadio.IsInstalled(plate) then
        NotifyPlayer(src, "error", "This vehicle already has a radio installed.")
        return
    end

    if pending.removeOnFinish then
        if not X1SRadio.RemoveItem(src, pending.itemName) then
            NotifyPlayer(src, "error", "Couldn't find the radio to install - installation cancelled.")
            return
        end
    end

    if not MarkInstalled(plate) then
        NotifyPlayer(src, "error", "Radio installed, but the server couldn't save it - please tell an admin.")
        return
    end

    NotifyPlayer(src, "success", ("Radio installed! Press %s (or run /%s) to open CarPlay.")
        :format(Config.Keybind ~= "" and ("[" .. Config.Keybind .. "]") or ("/" .. Config.Command), Config.Command))
end)

AddEventHandler("playerDropped", function()
    pendingInstalls[source] = nil
end)

RegisterNetEvent("x1s:radio:tryBeginInstall", function()
    local src = source
    X1SRadio.TryBeginInstall(src, Config.Radio.Item, true)
end)

-------------------------------------------------
-- Open Request
-------------------------------------------------
RegisterNetEvent("x1s:requestOpen", function(net)
    local src = source
    if not radioSystemActive then
        TriggerClientEvent("x1s:openResult", src, net, true)
        return
    end

    local veh = NetworkGetEntityFromNetworkId(net)
    local plate = GetPlateFromVehicle(veh)

    if not plate or not X1SRadio.IsInstalled(plate) then
        TriggerClientEvent("x1s:openResult", src, net, false,
            "This vehicle doesn't have a radio installed.")
        return
    end

    TriggerClientEvent("x1s:openResult", src, net, true)
end)

-------------------------------------------------
-- Framework Hooks
-------------------------------------------------
CreateThread(function()
    InitFrameworkBridge()

    if not radioSystemActive then return end

    if X1SRadio.Framework == "esx" and ESX then
        ESX.RegisterUsableItem(Config.Radio.Item, function(playerId)
            X1SRadio.TryBeginInstall(playerId, Config.Radio.Item, true)
        end)
    elseif X1SRadio.Framework == "qbcore" and QBCore then
        QBCore.Functions.CreateUseableItem(Config.Radio.Item, function(src)
            X1SRadio.TryBeginInstall(src, Config.Radio.Item, true)
        end)
    end

    if X1SRadio.Framework == "standalone" then
        RegisterCommand(Config.Radio.StandaloneUseCommand, function(src)
            if src == 0 then return end -- console has no vehicle to sit in

            local identifier = GetStandaloneIdentifier(src)
            local count = DbScalar(
                "SELECT radio_count FROM x1s_carplay_standalone_items WHERE identifier = ?", { identifier }
            )

            if not count or count < 1 then
                NotifyPlayer(src, "error", "You don't have a radio to install.")
                return
            end

            X1SRadio.TryBeginInstall(src, Config.Radio.Item, true)
        end, false)

        RegisterCommand(Config.Radio.StandaloneGiveCommand, function(src, args)
            local targetId = tonumber(args[1])
            local amount = tonumber(args[2]) or 1
            if not targetId then
                if src == 0 then print("Usage: " .. Config.Radio.StandaloneGiveCommand .. " <serverId> [amount]") end
                return
            end

            local identifier = GetStandaloneIdentifier(targetId)
            DbQuery([[
                INSERT INTO x1s_carplay_standalone_items (identifier, radio_count)
                VALUES (?, ?)
                ON DUPLICATE KEY UPDATE radio_count = radio_count + VALUES(radio_count)
            ]], { identifier, amount })

            NotifyPlayer(targetId, "success", "You received a radio to install.")
            if src ~= 0 then
                NotifyPlayer(src, "success", "Gave a radio to player " .. targetId .. ".")
            end
        end, true)
    end
end)

-------------------------------------------------
-- Generic export
-------------------------------------------------
exports("UseRadioItem", function(src)
    return X1SRadio.TryBeginInstall(src, Config.Radio.Item, false)
end)
