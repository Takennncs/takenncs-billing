local idCardsShown = {}
local QBCore = exports['qb-core']:GetCoreObject()
local tablet = false
local tabletDict = "amb@code_human_in_bus_passenger_idles@female@tablet@base"
local tabletAnim = "base"
local tabletProp = `prop_cs_tablet`
local tabletBone = 60309
local tabletOffset = vector3(0.03, 0.002, -0.0)
local tabletRot = vector3(10.0, 160.0, 0.0)

local Config = {}
local function loadConfig()
    local success, result = pcall(function()
        return require 'config'
    end)
    
    if success and result and type(result) == "table" then
        Config = result
    else
        Config = {
            MaxDistance = 10.0,
            ShowCitizenId = true,
        }
    end
end
loadConfig()

local function toggleTab(toggle)
    if toggle and not tablet then
        tablet = true
        if not IsPedInAnyVehicle(PlayerPedId(), false) then
            Citizen.CreateThread(function()
                RequestAnimDict(tabletDict)
                while not HasAnimDictLoaded(tabletDict) do
                    Citizen.Wait(150)
                end

                RequestModel(tabletProp)
                while not HasModelLoaded(tabletProp) do
                    Citizen.Wait(150)
                end

                local playerPed = PlayerPedId()
                local tabletObj = CreateObject(tabletProp, 0.0, 0.0, 0.0, true, true, false)
                local tabletBoneIndex = GetPedBoneIndex(playerPed, tabletBone)

                SetCurrentPedWeapon(playerPed, `WEAPON_UNARMED`, true)
                AttachEntityToEntity(tabletObj, playerPed, tabletBoneIndex, tabletOffset.x, tabletOffset.y, tabletOffset.z, tabletRot.x, tabletRot.y, tabletRot.z, true, false, false, false, 2, true)
                SetModelAsNoLongerNeeded(tabletProp)

                while tablet do
                    Citizen.Wait(100)
                    playerPed = PlayerPedId()
                    if not IsEntityPlayingAnim(playerPed, tabletDict, tabletAnim, 3) then
                        TaskPlayAnim(playerPed, tabletDict, tabletAnim, 3.0, 3.0, -1, 49, 0, 0, 0, 0)
                    end
                end

                ClearPedSecondaryTask(playerPed)
                Citizen.Wait(450)
                DetachEntity(tabletObj, true, false)
                DeleteEntity(tabletObj)
            end)
        end
    elseif not toggle and tablet then
        tablet = false
    end
end

function openBilling()
    local nearbyPlayers = GetNearbyPlayers()
    TriggerServerEvent("takenncs-billing:server:requestBillingInfo", idCardsShown, nearbyPlayers)
    SendNUIMessage({ action = 'showMenu' })
    SetNuiFocus(true, true)
end

function refreshBills()
    local nearbyPlayers = GetNearbyPlayers()
    TriggerServerEvent("takenncs-billing:server:requestBillingInfo", idCardsShown, nearbyPlayers)
end

exports('OpenBillingMenu', function()
    toggleTab(true)
    openBilling()
end)

exports('CloseBillingMenu', function()
    toggleTab(false)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hideMenu' })
end)

RegisterNetEvent('takenncs-billing:openMenu', function()
    toggleTab(true)
    openBilling()
end)

RegisterNetEvent('takenncs-billing:client:updateAvailableMenus')
AddEventHandler('takenncs-billing:client:updateAvailableMenus', function(canUserCreateBills)
    SendNUIMessage({ action = 'toggleNewBillMenu', value = canUserCreateBills })
end)

RegisterNetEvent('takenncs-billing:client:updateNearbyPlayers')
AddEventHandler('takenncs-billing:client:updateNearbyPlayers', function(players)
    if Config.ShowCitizenId then
        for _, player in ipairs(players or {}) do
            player.displayCitizenId = true
        end
    end
    SendNUIMessage({ action = 'updateNearbyPlayers', nearbyPlayers = players or {} })
end)

RegisterNetEvent('takenncs-billing:client:updateBills')
AddEventHandler('takenncs-billing:client:updateBills', function(bills)
    SendNUIMessage({ action = 'updateBills', bills = bills or {} })
end)

RegisterNUICallback("disableFocus", function(args, cb)
    SetNuiFocus(false, false)
    toggleTab(false)
    refreshBills()
    if cb then cb('ok') end
end)

RegisterNetEvent('TAKENNCS.Show.IDCard')
AddEventHandler('TAKENNCS.Show.IDCard', function(cidInformation)
    if cidInformation and cidInformation.cid then
        idCardsShown[cidInformation.cid] = { timeInserted = GetGameTimer(), information = cidInformation }
    end
end)

RegisterNetEvent('takenncs-billing:client:showBalanceError')
AddEventHandler('takenncs-billing:client:showBalanceError', function()
    SendNUIMessage({ action = 'showBalanceError' })
    Citizen.Wait(3000)
    SendNUIMessage({ action = 'hideBalanceError' })
end)

RegisterNetEvent('takenncs-billing:client:showAlreadyPaid')
AddEventHandler('takenncs-billing:client:showAlreadyPaid', function()
    SendNUIMessage({ action = 'showAlreadyPaid' })
    Citizen.Wait(3000)
    SendNUIMessage({ action = 'hideAlreadyPaid' })
end)

RegisterNetEvent('takenncs-billing:client:showBillPaid')
AddEventHandler('takenncs-billing:client:showBillPaid', function()
    SendNUIMessage({ action = 'showBillPaid' })
    refreshBills()
    Citizen.Wait(3000)
    SendNUIMessage({ action = 'hideBillPaid' })
end)

RegisterNetEvent('takenncs-billing:client:showBillsent')
AddEventHandler('takenncs-billing:client:showBillsent', function()
    SendNUIMessage({ action = 'showBillsent' })
    Citizen.Wait(3000)
    SendNUIMessage({ action = 'hideBillsent' })
end)

RegisterNetEvent('takenncs-billing:client:FailedBillsent')
AddEventHandler('takenncs-billing:client:FailedBillsent', function()
    SendNUIMessage({ action = 'FailedBillsent' })
    Citizen.Wait(3000)
    SendNUIMessage({ action = 'hideFailedBillsent' })
end)

RegisterNUICallback("payBill", function(args, cb)
    if args and args.billId then
        TriggerServerEvent("takenncs-billing:server:payBill", args.billId)
    end
    if cb then cb('ok') end
end)

RegisterNUICallback("newBill", function(args, cb)
    local nearbyPlayers = GetNearbyPlayers()
    local targetFound = false
    
    for _, playerId in ipairs(nearbyPlayers) do
        if tostring(playerId) == tostring(args.gameId) then
            targetFound = true
            break
        end
    end
    
    if targetFound then
        TriggerServerEvent("takenncs-billing:server:createBill", args.gameId, args.amount, args.description, args.identified)
    else
        SendNUIMessage({ action = 'FailedBillsent' })
        Citizen.Wait(3000)
        SendNUIMessage({ action = 'hideFailedBillsent' })
    end
    if cb then cb('ok') end
end)

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(5000)
        RemoveExpiredIdCardShowings()
    end
end)

function RemoveExpiredIdCardShowings()
    local currentTime = GetGameTimer()
    for k, v in pairs(idCardsShown) do
        if currentTime - v.timeInserted > 120 * 1000 then
            idCardsShown[k] = nil
        end
    end
end

function GetNearbyPlayers()
    local localPlayerCoords = GetEntityCoords(PlayerPedId())
    local localPlayerPed = PlayerPedId()
    local usersNearPlayer = {}

    for _, player in ipairs(GetActivePlayers()) do
        local targetPed = GetPlayerPed(player)
        
        if targetPed ~= localPlayerPed then
            local targetCoords = GetEntityCoords(targetPed)
            local distanceFromPlayer = #(targetCoords - localPlayerCoords)
            
            if distanceFromPlayer < (Config.MaxDistance or 10.0) then
                table.insert(usersNearPlayer, GetPlayerServerId(player))
            end
        end
    end

    return usersNearPlayer
end

Citizen.CreateThread(function()
    Citizen.Wait(5000)
    local xPlayer = QBCore.Functions.GetPlayerData()
    if xPlayer and xPlayer.job then
        if Config.AllowedJobs and Config.AllowedJobs[xPlayer.job.name] then
        end
    end
end)

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(10000)
        if IsNuiFocused() then
            refreshBills()
        end
    end
end)

RegisterCommand("arvetemenu", function()
    TriggerEvent("takenncs-billing:openMenu")
end, false)