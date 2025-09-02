--// ===== CONFIG =====
local Config = {
    RegionFilterEnabled = false,
    RegionList = { "singapore", "tokyo", "us-east" },
    RetryHttpDelay = 2,
}

--// ===== SERVICES =====
local g = game
local Players = g:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local RS = g:GetService("ReplicatedStorage")
local RunService = g:GetService("RunService")
local HttpService = g:GetService("HttpService")
local TeleportService = g:GetService("TeleportService")

--// ===== SERVER HOP =====
local PlaceID = g.PlaceId
local AllIDs, cursor, isTeleporting = {}, "", false

local function hasValue(tab, val)
    for _, v in ipairs(tab) do
        if v == val then return true end
    end
    return false
end

local function fetchServerPage(nextCursor)
    local url = ("https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Desc&excludeFullGames=true&limit=100%s")
        :format(PlaceID, nextCursor ~= "" and ("&cursor="..nextCursor) or "")
    local ok, data = pcall(function()
        return HttpService:JSONDecode(game:HttpGet(url))
    end)
    if not ok then
        task.wait(Config.RetryHttpDelay)
        return nil
    end
    return data
end

local function isReady()
    return game:IsLoaded()
       and LocalPlayer
       and LocalPlayer.Character
       and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
end

local function regionMatch(serverEntry)
    if not Config.RegionFilterEnabled then return true end
    local raw = tostring(serverEntry.ping or serverEntry.region or ""):lower()
    if raw == "" then return false end
    for _, key in ipairs(Config.RegionList) do
        if string.find(raw, tostring(key):lower(), 1, true) then
            return true
        end
    end
    return false
end

local function tryTeleportOnce()
    if not isReady() then return false end
    local page = fetchServerPage(cursor)
    if not page or not page.data then return false end
    cursor = (page.nextPageCursor and page.nextPageCursor ~= "null") and page.nextPageCursor or ""
    for _, v in ipairs(page.data) do
        local sid = tostring(v.id)
        if tonumber(v.playing) and tonumber(v.maxPlayers) and tonumber(v.playing) < tonumber(v.maxPlayers) then
            if not hasValue(AllIDs, sid) and regionMatch(v) then
                table.insert(AllIDs, sid)
                warn(("[Hop] Teleport -> %s (%s/%s)"):format(sid, tostring(v.playing), tostring(v.maxPlayers)))
                isTeleporting = true
                pcall(function()
                    TeleportService:TeleportToPlaceInstance(PlaceID, sid, LocalPlayer)
                end)
                task.delay(5, function() isTeleporting = false end)
                return true
            end
        end
    end
    return false
end

local function Hop()
    if not isReady() then
        repeat task.wait(1) until isReady()
    end
    for i = 1, 5 do
        if tryTeleportOnce() then return end
        task.wait(2)
    end
    warn("[Hop] Không tìm thấy server phù hợp.")
end

--// ===== FARM =====
local function L_V1(cf)
    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
        LocalPlayer.Character:SetPrimaryPartCFrame(cf)
    end
end

local chestSeen = {}
local function findChest()
    local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local closest, dist
    for _, v in pairs(workspace.Items:GetDescendants()) do
        if v:IsA("Model") and v.Name:find("Chest") and not v.Name:find("Snow") then
            local prox = v:FindFirstChildWhichIsA("ProximityPrompt", true)
            if prox then
                local id = v:GetDebugId()
                if not chestSeen[id] then chestSeen[id] = tick() end
                local d = (hrp.Position - v:GetPivot().Position).Magnitude
                if not dist or d < dist then
                    closest, dist = v, d
                end
            end
        end
    end
    return closest
end

local function farmDiamonds()
    for _, d in pairs(workspace:GetDescendants()) do
        if d:IsA("Model") and d.Name=="Diamond" and g.PlaceId==126509999114328 then
            L_V1(CFrame.new(d:GetPivot().Position))
            RS.RemoteEvents.RequestTakeDiamonds:FireServer(d)
            warn("collect kc")
        end
    end
end

--// ===== MAIN LOOP =====
spawn(function()
    while task.wait(0.5) do
        if g.PlaceId == 126509999114328 then
            -- Farm chest liên tục
            while true do
                local chest = findChest()
                if not chest then
                    warn("[ChestFarm] Hết rương -> hop sang server mới")
                    Hop()
                    break
                end
                local prox = chest:FindFirstChildWhichIsA("ProximityPrompt", true)
                local start = os.time()
                while prox and prox.Parent and os.time()-start < 10 do
                    L_V1(CFrame.new(chest:GetPivot().Position))
                    fireproximityprompt(prox)
                    task.wait(0.5)
                    prox = chest:FindFirstChildWhichIsA("ProximityPrompt", true)
                end
                task.wait(0.5)
            end
        end
    end
end)

-- diamonds song song
while task.wait(0.1) do
    if g.PlaceId == 126509999114328 then
        farmDiamonds()
    end
end

