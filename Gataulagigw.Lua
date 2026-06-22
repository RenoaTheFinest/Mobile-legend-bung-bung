-- ================================================
-- WEBHOOK TAB (WITH SUPER LEGENDARY DETECTION)
-- ================================================
repeat task.wait() until getgenv().Window
local Window = getgenv().Window

local WebhookTab = Window:CreateTab("Webhook", nil)

-- ======================================
-- CHECK CONFIG
-- ======================================
local config = getgenv().config or {}

if not config.PRIVATE_WEBHOOK_URL or config.PRIVATE_WEBHOOK_URL == "" then
    WebhookTab:CreateSection("Webhook Not Configured")
    WebhookTab:CreateLabel("Please set your webhook in the config before executing!")
    WebhookTab:CreateLabel("Add this BEFORE the loadstring in your executor:")
    WebhookTab:CreateLabel([[getgenv().config = {
    PRIVATE_WEBHOOK_URL = "Put your webhook URL here!",
    DISCORD_USER_ID = "Put your Discord user ID here!"
}]])
    return
end

-- ======================================
-- SERVICES
-- ======================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer

-- ======================================
-- WEBHOOK (from config)
-- ======================================
local WEBHOOK_URL = config.PRIVATE_WEBHOOK_URL
local DISCORD_USER_ID = config.DISCORD_USER_ID or ""

local request = http_request or request or (syn and syn.request)
if not request then
    WebhookTab:CreateSection("Error")
    WebhookTab:CreateLabel("Your executor doesn't support webhooks!")
    return
end

-- ======================================
-- FILTER
-- ======================================
local TRACKED_RARITIES = {
    ["Secret"] = true,
    ["Celestial"] = true,
    ["Infinity"] = true,
    ["Void"] = true,
    ["Super Legendary"] = true,
}

-- ======================================
-- COLORS
-- ======================================
local COLORS = {
    Secret = {Normal=0xFF0000,Shiny=0xFFD700,Mythic=0x8B00FF,ShinyMythic=0x00FF00},
    Celestial = {Normal=0xFF0000,Shiny=0xFFD700,Mythic=0x8B00FF,ShinyMythic=0x00FF00},
    Infinity = {Normal=0xFF0000,Shiny=0xFFB84D,Mythic=0x7D3CFF,ShinyMythic=0x00E6A8},
    Void = {Normal=0x0D0D0D,Shiny=0x3AA0FF},
    ["Super Legendary"] = {Normal=0x1E90FF,Shiny=0xFFD700,Mythic=0x8B00FF,ShinyMythic=0x00FF00}
}

-- ======================================
-- DATA
-- ======================================
local Pets = require(ReplicatedStorage.Shared.Data.Pets)
local LocalData = require(ReplicatedStorage.Client.Framework.Services.LocalData)

-- ======================================
-- FORMAT
-- ======================================
local function formatNum(n)
    if not n then return "0" end
    if n>=1e9 then return string.format("%.1fB",n/1e9)
    elseif n>=1e6 then return string.format("%.1fM",n/1e6)
    elseif n>=1e3 then return string.format("%.1fK",n/1e3)
    else return tostring(n) end
end

local function formatExist(n)
    if not n then return "0" end
    local s=tostring(math.floor(n))
    return s:reverse():gsub("(%d%d%d)","%1,"):reverse():gsub("^,","")
end

-- ======================================
-- STATS
-- ======================================
local function getStats(eggName)
    local data = LocalData:Get()
    if not data then return "0","0","0" end

    return
        formatNum(data.Coins or 0),
        formatNum(data.Gems or 0),
        formatNum((data.EggsOpened and data.EggsOpened[eggName]) or 0)
end

-- ======================================
-- PET EXTRA
-- ======================================
local function getPetExtra(petInfo)
    local odds="Unknown"
    local exist="Unknown"

    if petInfo.Chance then
        local calc=math.floor(1/petInfo.Chance)
        if calc>0 then odds="1/"..formatExist(calc) end
    elseif petInfo.Odds then
        odds="1/"..formatExist(petInfo.Odds)
    end

    if petInfo.Exists then
        exist=formatExist(petInfo.Exists)
    end

    return odds,exist
end

local function getVariant(ex)
    if ex.Shiny and ex.Mythic then return "ShinyMythic"
    elseif ex.Shiny then return "Shiny"
    elseif ex.Mythic then return "Mythic"
    else return "Normal" end
end

local function getVariantText(v)
    if v=="ShinyMythic" then return "Shiny Mythic"
    elseif v=="Shiny" then return "Shiny"
    elseif v=="Mythic" then return "Mythic"
    else return "Normal" end
end

-- ======================================
-- IMAGE (BG.SI CDN)
-- ======================================
local function getImage(petName, ex)
    local n = petName:lower():gsub("%s+", "-"):gsub("[^%w%-]", "")
    
    local prefix = ""
    if ex.Shiny and ex.Mythic then
        prefix = "shiny-mythic-"
    elseif ex.Shiny then
        prefix = "shiny-"
    elseif ex.Mythic then
        prefix = "mythic-"
    end
    
    return "https://cdn.bgsi.gg/items/" .. prefix .. n .. ".png"
end

-- ======================================
-- WEBHOOK SYSTEM
-- ======================================
local queue={}
local processing=false

local function process()
    if processing then return end
    processing=true

    task.spawn(function()
        while #queue>0 do
            local p=table.remove(queue,1)
            pcall(function()
                request({
                    Url=WEBHOOK_URL,
                    Method="POST",
                    Headers={["Content-Type"]="application/json"},
                    Body=HttpService:JSONEncode(p)
                })
            end)
            task.wait(1)
        end
        processing=false
    end)
end

-- ======================================
-- SEND
-- ======================================
local function send(petName, eggName, ex)
    local info = Pets[petName]
    if not info then return end

    local rarity = info.Rarity
    local isSuper = (ex.Super == true) or (ex.Enchant ~= nil)
    
    -- If Legendary with Super flag, treat as Super Legendary
    if rarity == "Legendary" and isSuper then
        rarity = "Super Legendary"
    end
    
    local tracked = false
    for r in pairs(TRACKED_RARITIES) do
        if rarity:find(r) then
            tracked = true
            rarity = r
            break
        end
    end
    if not tracked then return end

    local variant = getVariant(ex)
    local variantText = getVariantText(variant)
    local color = (COLORS[rarity] and COLORS[rarity][variant]) or 16777215

    local coins, gems, opened = getStats(eggName)
    local odds, exist = getPetExtra(info)
    local img = getImage(petName, ex)

    local embed = {
        title = "Congrats You Hatched A "..variantText.." "..rarity.." "..petName.."!",
        color = color,
        fields = {
            {
                name = "* User Info",
                value =
                    "Name : "..player.Name.."\n"..
                    "Coin : "..coins.."\n"..
                    "Gems : "..gems.."\n"..
                    "Egg Hatched : "..opened,
                inline = false
            },
            {
                name = "Pet Info",
                value =
                    "Odds : "..odds.."\n"..
                    "Exist : "..exist,
                inline = false
            }
        },
        footer = {
            text = "Renoa The Finest has Blessed You! * "..os.date("%Y-%m-%d %H:%M:%S")
        }
    }

    -- Show enchant for Super Legendary
    if rarity == "Super Legendary" and ex.Enchant then
        table.insert(embed.fields, {
            name = "Ultra Legendary Enchant",
            value = tostring(ex.Enchant),
            inline = false
        })
    end

    if img then
        embed.thumbnail = {url = img}
    end

    table.insert(queue, {
        content = (rarity == "Secret") and "<@"..DISCORD_USER_ID..">" or nil,
        embeds = {embed}
    })

    process()
end

-- ======================================
-- ONLINE PING (EVERY 30 MINUTES - WITH HATCH RATE)
-- ======================================
local startTime = os.time()
local lastHatches = 0
local lastPingTime = os.time()

local leaderstats = player:FindFirstChild("leaderstats")
if leaderstats then
    for _, stat in ipairs(leaderstats:GetChildren()) do
        if stat.Name:find("Hatches") then
            lastHatches = tonumber(stat.Value) or 0
        end
    end
end

task.spawn(function()
    while true do
        task.wait(1800)
        
        local elapsed = os.time() - startTime
        local hours = math.floor(elapsed / 3600)
        local minutes = math.floor((elapsed % 3600) / 60)
        
        local data = LocalData:Get()
        local coins = data and formatNum(data.Coins or 0) or "0"
        local gems = data and formatNum(data.Gems or 0) or "0"
        
        local leaderstats = player:FindFirstChild("leaderstats")
        local bubbles = "0"
        local currentHatches = 0
        if leaderstats then
            for _, stat in ipairs(leaderstats:GetChildren()) do
                if stat.Name:find("Bubble") then
                    bubbles = formatNum(stat.Value)
                end
                if stat.Name:find("Hatches") then
                    currentHatches = tonumber(stat.Value) or 0
                end
            end
        end
        
        local timeSinceLastPing = (os.time() - lastPingTime) / 60
        local hatchesSinceLastPing = currentHatches - lastHatches
        local perMin = timeSinceLastPing > 0 and math.floor(hatchesSinceLastPing / timeSinceLastPing) or 0
        local perHour = perMin * 60
        
        lastHatches = currentHatches
        lastPingTime = os.time()
        
        table.insert(queue, {
            embeds = {{
                title = "Still Online!",
                description =
                    "**" .. player.Name .. "** is still online!\n\n" ..
                    "Online: " .. hours .. "h " .. minutes .. "m\n" ..
                    "Coins: " .. coins .. "\n" ..
                    "Gems: " .. gems .. "\n" ..
                    "Bubbles: " .. bubbles .. "\n\n" ..
                    "**Hatch Rate**\n" ..
                    "Per Minute: " .. perMin .. "\n" ..
                    "Per Hour: " .. perHour,
                color = 3447003,
                footer = {text = "Renoa Hub * " .. os.date("%Y-%m-%d %H:%M:%S")}
            }}
        })
        process()
    end
end)

-- ======================================
-- HOOK (WORKS WITH ANIMATION TOGGLE)
-- ======================================
local success, mod = pcall(function()
    return require(ReplicatedStorage.Client.Effects.HatchEgg)
end)

if success and mod then
    local originalPlay = mod.Play

    local hookedFunction = newcclosure(function(self, data)
        if type(data) == "table" and data.Pets then
            for _, p in ipairs(data.Pets) do
                local pet = p.Pet or p
                if pet and pet.Name then
                    local ex = {Shiny = pet.Shiny, Mythic = pet.Mythic, XL = pet.XL}
                    if pet.Super then ex.Super = pet.Super end
                    if pet.Enchant then ex.Enchant = pet.Enchant end
                    send(pet.Name, data.Name or "Egg", ex)
                end
            end
        end
        if getgenv().animationHidden then
            return
        end
        return originalPlay(self, data)
    end)

    mod.Play = hookedFunction
    print("[Webhook] Hook installed!")
else
    warn("[Webhook] Failed to hook HatchEgg module!")
end

-- ======================================
-- UI
-- ======================================
WebhookTab:CreateSection("Status")
WebhookTab:CreateLabel("Webhook is Running!")
WebhookTab:CreateLabel("Tracking: Secret, Celestial, Infinity, Void, Super Legendary")
WebhookTab:CreateLabel("Online ping: Every 30 minutes (with hatch rate)")
WebhookTab:CreateLabel("Ping: "..(DISCORD_USER_ID ~= "" and "ON <@"..DISCORD_USER_ID..">" or "OFF"))

print("Webhook Is Online, Good Luck Hatching Guys! Me (Renoa The Finest) Wishing for our luck")
