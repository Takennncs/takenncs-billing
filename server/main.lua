local QBCore = exports['qb-core']:GetCoreObject()
local Config = {}

local function LoadConfigFile()
    local success, result = pcall(function()
        return require 'config'
    end)
    
    if success and result and type(result) == "table" then
        Config = result
        return true
    end
    
    local resourceName = GetCurrentResourceName()
    local configFile = LoadResourceFile(resourceName, 'config.lua')
    
    if configFile then
        configFile = configFile:gsub("^\239\187\191", "")
        local configEnv = { Config = {} }
        local loadCFG, err = load(configFile, 'config.lua', 't', configEnv)
        
        if loadCFG then
            local success, loadErr = pcall(loadCFG)
            if success and configEnv.Config and type(configEnv.Config) == "table" then
                Config = configEnv.Config
                return true
            end
        end
    end
    
    Config = {
        AllowedJobs = {
            ["wigwamburger"] = true,
        },
        MaxDistance = 10.0,
        BankTable = 'bank_accounts_new',
        MoneyToJobAccount = true,
        InvoiceTable = 'takenncs_billing_invoices',
        RequireOnDuty = true,
        ShowCitizenId = true,
        JobLabels = {
            ["wigwamburger"] = "Wigwam Burger",
        },
    }
    return false
end

LoadConfigFile()

local function days_since_unix_timestamp(unix_timestamp)
    if not unix_timestamp then return 0 end
    local current_time = os.time()
    local time_difference = current_time - tonumber(unix_timestamp)
    local seconds_in_day = 60 * 60 * 24
    local days_since = math.floor(time_difference / seconds_in_day)
    return days_since < 0 and 0 or days_since
end

local function AddMoneyToJobAccount(jobName, amount)
    if not Config.MoneyToJobAccount then return true end
    
    local success, result = pcall(function()
        local jobAccount = MySQL.Sync.fetchScalar('SELECT id FROM ' .. Config.BankTable .. ' WHERE auth = ?', { 'society_' .. jobName })
        
        if jobAccount then
            MySQL.Sync.execute('UPDATE ' .. Config.BankTable .. ' SET amount = amount + ? WHERE auth = ?', { amount, 'society_' .. jobName })
        else
            MySQL.Sync.execute('INSERT INTO ' .. Config.BankTable .. ' (amount, auth, isFrozen) VALUES (?, ?, ?)', 
                { amount, 'society_' .. jobName, 0 })
        end
        return true
    end)
    
    if not success then
        return false
    end
    return true
end

RegisterNetEvent('takenncs-billing:server:requestBillingInfo', function(idcardshown, nearbyplayers)
    local src = source
    local xPlayer = QBCore.Functions.GetPlayer(src)
    
    if not xPlayer then return end
    
    local data = {}
    
    for _, v in pairs(nearbyplayers) do
        local xTarget = QBCore.Functions.GetPlayer(v)
        
        if xTarget and idcardshown and idcardshown[xTarget.PlayerData.citizenid] then
            if xTarget.PlayerData.source ~= xPlayer.PlayerData.source and 
               idcardshown[xTarget.PlayerData.citizenid].information and 
               idcardshown[xTarget.PlayerData.citizenid].information.cid then
                local inserting = {
                    id = xTarget.PlayerData.source,
                    name = idcardshown[xTarget.PlayerData.citizenid].information.firstname,
                    lastname = idcardshown[xTarget.PlayerData.citizenid].information.lastname or '',
                    identified = idcardshown[xTarget.PlayerData.citizenid].information.cid,
                    citizenid = xTarget.PlayerData.citizenid,
                }
                table.insert(data, inserting)
            end
        end
    end

    TriggerClientEvent('takenncs-billing:client:updateNearbyPlayers', src, data)

    local tableName = Config.InvoiceTable or 'takenncs_billing_invoices'
    
    local statusColumnExists = pcall(function()
        return MySQL.Sync.fetchScalar("SELECT COUNT(*) FROM information_schema.columns WHERE table_name = '" .. tableName .. "' AND column_name = 'status'")
    end)
    
    local query
    if statusColumnExists then
        query = 'SELECT * FROM ' .. tableName .. ' WHERE citizenid = ? AND (status = "pending" OR status IS NULL)'
    else
        query = 'SELECT * FROM ' .. tableName .. ' WHERE citizenid = ?'
    end
    
    MySQL.Async.fetchAll(query, { xPlayer.PlayerData.citizenid }, function(result)
        if result and type(result) == "table" then
            for k, v in pairs(result) do
                result[k].days = days_since_unix_timestamp(tonumber(v.days))
                if not v.status then
                    result[k].status = "pending"
                end
            end
        end
        TriggerClientEvent('takenncs-billing:client:updateBills', src, result or {})
    end)

    local canCreateBills = false
    if Config.AllowedJobs and type(Config.AllowedJobs) == "table" then
        if Config.AllowedJobs[xPlayer.PlayerData.job.name] then
            if Config.RequireOnDuty then
                canCreateBills = xPlayer.PlayerData.onduty or false
            else
                canCreateBills = true
            end
        end
    end
    
    TriggerClientEvent('takenncs-billing:client:updateAvailableMenus', src, canCreateBills)
end)

RegisterNetEvent('takenncs-billing:server:payBill', function(billid)
    local src = source
    local xPlayer = QBCore.Functions.GetPlayer(src)
    
    if not xPlayer then return end
    
    local tableName = Config.InvoiceTable or 'takenncs_billing_invoices'
    
    local statusColumnExists = pcall(function()
        return MySQL.Sync.fetchScalar("SELECT COUNT(*) FROM information_schema.columns WHERE table_name = '" .. tableName .. "' AND column_name = 'status'")
    end)
    
    local query
    if statusColumnExists then
        query = 'SELECT * FROM ' .. tableName .. ' WHERE id = ? AND citizenid = ? AND (status = "pending" OR status IS NULL)'
    else
        query = 'SELECT * FROM ' .. tableName .. ' WHERE id = ? AND citizenid = ?'
    end
    
    MySQL.Async.fetchAll(query, { billid, xPlayer.PlayerData.citizenid }, function(result)
        if result and result[1] then
            local amount = result[1].amount
            local sendercitizenid = result[1].sendercitizenid
            local society = result[1].society
            
            if xPlayer.Functions.GetMoney('bank') >= amount then
                xPlayer.Functions.RemoveMoney('bank', amount)
                
                local success = AddMoneyToJobAccount(society, amount)
                
                if success then
                    MySQL.Async.execute('DELETE FROM ' .. tableName .. ' WHERE id = ?', { result[1].id }, function(rowsChanged)
                        if rowsChanged and rowsChanged > 0 then
                            TriggerClientEvent('takenncs-billing:client:showBillPaid', src)
                            
                            MySQL.Async.fetchAll('SELECT * FROM ' .. tableName .. ' WHERE citizenid = ? AND (status = "pending" OR status IS NULL)', 
                                { xPlayer.PlayerData.citizenid }, function(updatedResult)
                                if updatedResult and type(updatedResult) == "table" then
                                    for k, v in pairs(updatedResult) do
                                        updatedResult[k].days = days_since_unix_timestamp(tonumber(v.days))
                                    end
                                end
                                TriggerClientEvent('takenncs-billing:client:updateBills', src, updatedResult or {})
                                
                                local Sender = QBCore.Functions.GetPlayerByCitizenId(sendercitizenid)
                                if Sender then
                                    TriggerClientEvent("chat:addMessage", Sender.PlayerData.source, {
                                        color = { 0, 255, 0 },
                                        multiline = true,
                                        args = { "ARVE", "Isik maksis arve edukalt ära summas: " .. amount .. "$" }
                                    })
                                end
                            end)
                        else
                            xPlayer.Functions.AddMoney('bank', amount)
                            TriggerClientEvent('takenncs-billing:client:FailedBillsent', src)
                        end
                    end)
                else
                    xPlayer.Functions.AddMoney('bank', amount)
                    TriggerClientEvent('takenncs-billing:client:FailedBillsent', src)
                end
            else
                TriggerClientEvent('takenncs-billing:client:showBalanceError', src)
            end
        else
            TriggerClientEvent('takenncs-billing:client:showAlreadyPaid', src)
        end
    end)
end)

RegisterNetEvent('takenncs-billing:server:createBill', function(playerId, amount, description, identified)
    local src = source
    local xPlayer = QBCore.Functions.GetPlayer(src)

    if not xPlayer then return end

    if not Config.AllowedJobs or type(Config.AllowedJobs) ~= "table" then
        TriggerClientEvent('takenncs-billing:client:FailedBillsent', src)
        return
    end

    if not Config.AllowedJobs[xPlayer.PlayerData.job.name] then
        TriggerClientEvent('takenncs-billing:client:FailedBillsent', src)
        return
    end

    if Config.RequireOnDuty and not xPlayer.PlayerData.onduty then
        TriggerClientEvent('takenncs-billing:client:FailedBillsent', src)
        return
    end

    if not amount or amount == 'empty' or tonumber(amount) <= 0 then
        TriggerClientEvent('takenncs-billing:client:FailedBillsent', src)
        return
    end

    if not description or description == 'empty' then
        description = 'Arve'
    end

    local xTarget = QBCore.Functions.GetPlayer(playerId)
    
    if xTarget then
        local charname = xTarget.PlayerData.charinfo.firstname .. ' ' .. xTarget.PlayerData.charinfo.lastname
        local xplayername = xPlayer.PlayerData.charinfo.firstname .. ' ' .. xPlayer.PlayerData.charinfo.lastname
        local society_label = Config.JobLabels and Config.JobLabels[xPlayer.PlayerData.job.name] or xPlayer.PlayerData.job.label
        
        if society_label == nil or society_label == '' then
            society_label = xPlayer.PlayerData.job.name
        end
        
        local tableName = Config.InvoiceTable or 'takenncs_billing_invoices'
        
        local success = pcall(function()
            MySQL.Sync.execute(
                'INSERT INTO ' .. tableName .. ' (citizenid, name, amount, society, sender, sendercitizenid, description, society_label, days, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
                {xTarget.PlayerData.citizenid, charname, amount, xPlayer.PlayerData.job.name, xplayername, xPlayer.PlayerData.citizenid, description, society_label, os.time(), 'pending'}
            )
        end)
        
        if not success then
            success = pcall(function()
                MySQL.Sync.execute(
                    'INSERT INTO ' .. tableName .. ' (citizenid, name, amount, society, sender, sendercitizenid, description, society_label, days) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
                    {xTarget.PlayerData.citizenid, charname, amount, xPlayer.PlayerData.job.name, xplayername, xPlayer.PlayerData.citizenid, description, society_label, os.time()}
                )
            end)
        end
        
        if success then
            TriggerClientEvent('takenncs-billing:client:showBillsent', src)
            TriggerClientEvent("chat:addMessage", src, {
                color = { 0, 255, 0 },
                multiline = true,
                args = { "ARVE", "Saatsid arve summas: " .. amount .. "$" }
            })
            TriggerClientEvent("chat:addMessage", playerId, {
                color = { 255, 255, 0 },
                multiline = true,
                args = { "ARVE", "Sulle esitati arve summas: " .. amount .. "$" }
            })
        else
            TriggerClientEvent('takenncs-billing:client:FailedBillsent', src)
        end
    else
        TriggerClientEvent('takenncs-billing:client:FailedBillsent', src)
    end
end)

exports('BillPlayer', function(sourceId, targetId, amount, description)
    local xPlayer = QBCore.Functions.GetPlayer(sourceId)
    local xTarget = QBCore.Functions.GetPlayer(targetId)
    
    if xPlayer and xTarget and tonumber(amount) > 0 then
        local charname = xTarget.PlayerData.charinfo.firstname .. ' ' .. xTarget.PlayerData.charinfo.lastname
        local xplayername = xPlayer.PlayerData.charinfo.firstname .. ' ' .. xPlayer.PlayerData.charinfo.lastname
        local society_label = Config.JobLabels and Config.JobLabels[xPlayer.PlayerData.job.name] or xPlayer.PlayerData.job.label
        local tableName = Config.InvoiceTable or 'takenncs_billing_invoices'
        
        local success = pcall(function()
            MySQL.Sync.execute(
                'INSERT INTO ' .. tableName .. ' (citizenid, name, amount, society, sender, sendercitizenid, description, society_label, days, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
                {xTarget.PlayerData.citizenid, charname, amount, xPlayer.PlayerData.job.name, xplayername, xPlayer.PlayerData.citizenid, description or 'Arve', society_label, os.time(), 'pending'}
            )
        end)
        
        if success then
            TriggerClientEvent("chat:addMessage", xTarget.PlayerData.source, {
                color = { 255, 255, 0 },
                multiline = true,
                args = { "ARVE", "Sulle esitati arve summas " .. amount .. "$" }
            })
            return true
        end
    end
    return false
end)

exports('BillPlayerOffline', function(sourceId, targetcid, amount, description)
    local xPlayer = QBCore.Functions.GetPlayer(sourceId)
    
    if not xPlayer or tonumber(amount) <= 0 then return false end
    
    local result = MySQL.Sync.fetchAll('SELECT charinfo FROM players WHERE citizenid = ?', { targetcid })
    
    if result and result[1] then
        local charinfo = json.decode(result[1].charinfo)
        local charname = charinfo.firstname .. ' ' .. charinfo.lastname
        local xplayername = xPlayer.PlayerData.charinfo.firstname .. ' ' .. xPlayer.PlayerData.charinfo.lastname
        local society_label = Config.JobLabels and Config.JobLabels[xPlayer.PlayerData.job.name] or xPlayer.PlayerData.job.label
        local tableName = Config.InvoiceTable or 'takenncs_billing_invoices'
        
        local success = pcall(function()
            MySQL.Sync.execute(
                'INSERT INTO ' .. tableName .. ' (citizenid, name, amount, society, sender, sendercitizenid, description, society_label, days, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
                {targetcid, charname, amount, xPlayer.PlayerData.job.name, xplayername, xPlayer.PlayerData.citizenid, description or 'Arve', society_label, os.time(), 'pending'}
            )
        end)
        
        return success
    end
    return false
end)

lib.callback.register('takenncs-billing:getDeptor', function(source, target)
    local src = source
    local xPlayer = QBCore.Functions.GetPlayer(src)
    local returnable = false

    if xPlayer then
        local tableName = Config.InvoiceTable or 'takenncs_billing_invoices'
        local rowCount = MySQL.Sync.fetchScalar('SELECT COUNT(*) FROM ' .. tableName .. ' WHERE citizenid = ? AND society = ? AND (status = "pending" OR status IS NULL)', 
            { xPlayer.PlayerData.citizenid, target })
        returnable = (rowCount and rowCount > 0) or false
    end

    return returnable
end)

lib.callback.register('takenncs-billing:getUnpaidBills', function(source, cid, society)
    local returnable = {}

    if cid then
        local tableName = Config.InvoiceTable or 'takenncs_billing_invoices'
        MySQL.Async.fetchAll('SELECT * FROM ' .. tableName .. ' WHERE citizenid = ? AND society = ? AND (status = "pending" OR status IS NULL)', 
            { cid, society }, function(result)
            local unpaidBills = {}
            if result and type(result) == "table" then
                for _, bill in ipairs(result) do
                    if tonumber(bill.amount) > 0 then
                        table.insert(unpaidBills, {
                            id = bill.id,
                            amount = tonumber(bill.amount),
                            amount_formatted = tonumber(bill.amount) .. '$',
                            description = bill.description,
                            days = days_since_unix_timestamp(tonumber(bill.days)),
                            sender = bill.sender,
                            date = os.date("%d.%m.%Y", tonumber(bill.days or os.time()))
                        })
                    end
                end
            end
            returnable = unpaidBills
        end)
    end

    while #returnable == 0 do
        Citizen.Wait(50)
        if #returnable > 0 or not cid then break end
    end
    return returnable
end)