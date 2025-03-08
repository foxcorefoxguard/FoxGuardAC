-- FoxGuard Integration for FoxCore Framework
-- Created on March 7, 2025

local FoxCore = exports["foxcore_framework"]
local FoxInventory = exports["foxcore_inventory"]
local initalizedPlayers = {}

-- Configuration
local Config = {
    enabled = true,
    checkInterval = 60000, -- Check every 60 seconds
    apiEndpoint = "https://api.foxguard.com/v1/verify",
    apiKey = "YOUR_API_KEY", -- Replace with your actual API key
    debug = false,
    globalBanEnabled = true, -- Enable global banning system
    banRequestEndpoint = "/ban/global", -- API endpoint for global bans
    banDatabasePanel = "https://panel.foxguard.com", -- Ban database panel URL
    bannedSoftware = {
        "RedEngine",
        "Cheat Engine", 
        "CheatEngine", 
        "CE", 
        "EulenCheats", 
        "Eulen", 
        "HamMafia", 
        "DesudoV", 
        "Lumia", 
        "LumiaENG", 
        "RedENGINE", 
        "Injection", 
        "Injector", 
        "Mod Menu"
    }
}

-- Debug logging function
local function DebugLog(message)
    if Config.debug then
        print("[FoxGuard] " .. message)
    end
end

-- Function to make API calls to FoxGuard website
local function CallFoxGuardAPI(endpoint, data)
    DebugLog("Making API call to: " .. endpoint)
    
    -- This is a placeholder for actual HTTP request
    -- In a real implementation, you would use the FiveM native PerformHttpRequest
    PerformHttpRequest(Config.apiEndpoint .. endpoint, function(statusCode, responseText, headers)
        if statusCode == 200 then
            local response = json.decode(responseText)
            DebugLog("API Response: " .. responseText)
            return response
        else
            DebugLog("API Error: " .. statusCode .. " - " .. responseText)
            return nil
        end
    end, "POST", json.encode(data), {["Content-Type"] = "application/json", ["Authorization"] = "Bearer " .. Config.apiKey})
end

-- Function to register a global ban in the FoxGuard database
local function RegisterGlobalBan(source, reason, detectedSoftware, screenshot)
    local playerName = GetPlayerName(source)
    local playerIdentifiers = GetPlayerIdentifiers(source)
    
    DebugLog("Registering global ban for player: " .. playerName)
    
    -- Create ban data
    local banData = {
        player = {
            name = playerName,
            identifiers = playerIdentifiers,
            source = source
        },
        reason = reason,
        detected_software = detectedSoftware,
        screenshot = screenshot,
        server_id = GetConvar("sv_hostname", "Unknown"),
        timestamp = os.time(),
        ban_type = "global_cheat_detection"
    }
    
    -- Call the global ban API endpoint
    CallFoxGuardAPI(Config.banRequestEndpoint, banData)
    
    -- Output to server console
    print("[FoxGuard] GLOBAL BAN ISSUED: Player " .. playerName .. " globally banned for using: " .. table.concat(detectedSoftware, ", "))
    print("[FoxGuard] The player can request an unban at: " .. Config.banDatabasePanel)
    
    return true
end

-- Process detection results from client
RegisterNetEvent("foxguard:detectionResults")
AddEventHandler("foxguard:detectionResults", function(results)
    local source = source
    local playerName = GetPlayerName(source)
    
    DebugLog("Received detection results from " .. playerName)
    
    if results.unauthorized then
        DebugLog("Unauthorized software detected for player: " .. playerName)
        
        -- Check if detected software is in our global ban list
        local shouldGlobalBan = false
        local bannedSoftwareDetected = {}
        
        for _, detected in ipairs(results.detected) do
            for _, banned in ipairs(Config.bannedSoftware) do
                if detected:lower() == banned:lower() or detected:find(banned) then
                    shouldGlobalBan = true
                    table.insert(bannedSoftwareDetected, detected)
                    break
                end
            end
        end
        
        -- Report to FoxGuard API
        CallFoxGuardAPI("/report/cheat_detection", {
            player = source,
            name = playerName,
            detected = results.detected,
            screenshot = results.screenshot -- Base64 encoded screenshot if available
        })
        
        -- If global banning is enabled and banned software was detected
        if Config.globalBanEnabled and shouldGlobalBan then
            local banReason = "FoxGuard Anti-Cheat: Detected banned software: " .. table.concat(bannedSoftwareDetected, ", ")
            
            -- Register global ban
            RegisterGlobalBan(source, banReason, bannedSoftwareDetected, results.screenshot)
            
            -- Drop player with message about global ban
            DropPlayer(source, "FoxGuard: You have been globally banned from all FoxGuard-protected servers for using cheat software. Visit " .. Config.banDatabasePanel .. " to request an unban.")
            
            -- If using a ban system, add permanent ban locally as well
            if exports["foxcore_framework"].BanPlayer then
                exports["foxcore_framework"]:BanPlayer(source, banReason, 0) -- 0 = permanent
            end
        else
            -- Regular local ban for unauthorized software
            DropPlayer(source, "FoxGuard: Unauthorized software detected")
            
            -- If using a ban system, add permanent ban
            if exports["foxcore_framework"].BanPlayer then
                exports["foxcore_framework"]:BanPlayer(source, "FoxGuard Anti-Cheat: Unauthorized software detected", 0) -- 0 = permanent
            end
        end
    end
end)

-- Function to verify player with FoxGuard
local function VerifyPlayer(source)
    local player = FoxCore:GetPlayer(source)
    if not player then return false end
    
    local playerIdentifiers = GetPlayerIdentifiers(source)
    local playerName = GetPlayerName(source)
    
    local data = {
        identifiers = playerIdentifiers,
        name = playerName,
        server_id = GetConvar("sv_hostname", "Unknown"),
    }
    
    DebugLog("Verifying player: " .. playerName)
    
    -- Check for global bans first
    local banCheckResponse = CallFoxGuardAPI("/ban/check", data)
    if banCheckResponse and banCheckResponse.is_banned then
        DebugLog("Player is globally banned: " .. playerName)
        return false, banCheckResponse.ban_reason
    end
    
    local response = CallFoxGuardAPI("/player/verify", data)
    return response and response.verified or false
end

-- Function to handle player connection
local function OnPlayerConnected(source)
    DebugLog("Player connected: " .. source)
    
    -- Check if player is verified with FoxGuard
    local verified, banReason = VerifyPlayer(source)
    if not verified then
        local dropMessage = "FoxGuard: You are not authorized to join this server."
        if banReason then
            dropMessage = "FoxGuard: " .. banReason .. ". Visit " .. Config.banDatabasePanel .. " to request an unban."
        end
        
        DebugLog("Player failed verification: " .. source)
        DropPlayer(source, dropMessage)
        return
    end
    
    -- Register player as initialized
    initalizedPlayers[source] = true
    DebugLog("Player verified and initialized: " .. source)
    
    -- Trigger client-side scanning
    TriggerClientEvent("foxguard:scanSystem", source)
end

-- Function to handle player disconnection
local function OnPlayerDisconnected(source)
    if initalizedPlayers[source] then
        initalizedPlayers[source] = nil
        DebugLog("Player disconnected and removed from tracking: " .. source)
    end
end

-- Function for periodic checks
local function PeriodicChecks()
    DebugLog("Running periodic checks")
    
    for source, _ in pairs(initalizedPlayers) do
        -- Check if player still exists on server
        if GetPlayerName(source) == nil then
            initalizedPlayers[source] = nil
            DebugLog("Removed non-existent player from tracking: " .. source)
        else
            -- Verify player is still authorized
            local verified, banReason = VerifyPlayer(source)
            if not verified then
                local dropMessage = "FoxGuard: Your authorization has expired."
                if banReason then
                    dropMessage = "FoxGuard: " .. banReason .. ". Visit " .. Config.banDatabasePanel .. " to request an unban."
                end
                
                DebugLog("Player failed periodic verification: " .. source)
                DropPlayer(source, dropMessage)
            else
                -- Trigger periodic client-side scanning
                TriggerClientEvent("foxguard:scanSystem", source)
            end
        end
    end
    
    -- Schedule next check
    SetTimeout(Config.checkInterval, PeriodicChecks)
end

-- Event handlers
RegisterNetEvent("playerConnecting")
AddEventHandler("playerConnecting", function(name, setCallback, deferrals)
    local source = source
    deferrals.defer()
    deferrals.update("Checking FoxGuard authorization...")
    
    -- Verify with FoxGuard
    local verified, banReason = VerifyPlayer(source)
    
    if verified then
        deferrals.done()
    else
        local denyMessage = "FoxGuard: You are not authorized to join this server."
        if banReason then
            denyMessage = "FoxGuard: " .. banReason .. ". Visit " .. Config.banDatabasePanel .. " to request an unban."
        end
        
        deferrals.done(denyMessage)
    end
end)

RegisterNetEvent("foxcore_framework:playerLoaded")
AddEventHandler("foxcore_framework:playerLoaded", function(source)
    OnPlayerConnected(source)
end)

AddEventHandler("playerDropped", function()
    local source = source
    OnPlayerDisconnected(source)
end)

-- FoxCore specific integrations
-- Add money check to prevent cheating
local originalAddMoney = FoxCore.AddMoney
FoxCore.AddMoney = function(source, amount, type)
    -- Log the transaction and verify with FoxGuard
    local data = {
        player = source,
        amount = amount,
        type = type,
        action = "add_money"
    }
    
    local response = CallFoxGuardAPI("/transaction/verify", data)
    if response and response.authorized then
        return originalAddMoney(source, amount, type)
    else
        DebugLog("Suspicious money addition blocked for player: " .. source)
        -- Optionally report to FoxGuard
        CallFoxGuardAPI("/report/violation", {
            player = source,
            type = "money_cheat",
            details = "Attempted to add " .. amount .. " to " .. type
        })
        return false
    end
end

-- Initialize script
Citizen.CreateThread(function()
    DebugLog("FoxGuard script initialized")
    
    -- Start periodic checks
    PeriodicChecks()
    
    -- Register server as active with FoxGuard
    local serverData = {
        name = GetConvar("sv_hostname", "Unknown"),
        players = GetNumPlayerIndices(),
        resources = GetNumResources()
    }
    
    CallFoxGuardAPI("/server/register", serverData)
end)

-- Export API for other resources
exports("VerifyPlayer", VerifyPlayer)
exports("IsFoxGuardEnabled", function() return Config.enabled end)
exports("SetFoxGuardEnabled", function(state) Config.enabled = state end)
exports("RegisterGlobalBan", RegisterGlobalBan) -- Export the global ban function