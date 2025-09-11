_G.Debug = true
local PUBLIC_WH_ENABLED = true
local PUBLIC_WEBHOOK = "https://discord.com/api/webhooks/1415375201616527452/cc53iS4kpX_arJxf5t3YYsYkSWJYx3ywYZFEGuS5z1cvk4K5wgPW17gdJryvNmYqDJ5b"
local PUBLIC_WEBHOOK_RARITY = { Common = true, Uncommon = true, Rare = true, Legendary = true, Godly = true }
if TLfig.FpsLock[1] and type(TLfig.FpsLock[2]) == "number" then setfpscap(TLfig.FpsLock[2]) end
local DEFAULTS = {
    UNDERGROUND_MODE = true, UNDER_HEIGHT = 80, MAX_FARM_RADIUS = 1000, TELE_DELAY = 1.8,
    COIN_NAMES = { "Coin_Server", "BeachBall", "BeachBalls2025" }, NAME_MATCH_MODE = "contains",
    REQUIRE_TOUCHINTEREST = false, TOUCH_TIME = 0.1, RECHECK_DISTANCE = 8, HEIGHT_OFFSET = 2.5,
    USE_FIRETOUCH = true, SCAN_METHOD = "radius", RADIUS_BLACKLIST_HRP = true, MAX_COINS_PER_TICK = 10,
    STUCK_RESET_SEC = 15, JOB_TIMEOUT_SEC = 4, FAIL_COOLDOWN_SEC = 8, MAX_FAIL_PER_VISIT = 2,
    SCAN_DESC_TOUCH = true, SMART_JITTER = true, OVERLAP_VERIFY = true, OVERLAP_BOX_PAD = Vector3.new(2, 2, 2),
    RESCAN_INTERVAL = 1.2, HARD_RESCAN_SEC = 5, JUMP_DELTA_Y = 2.0, JUMP_WINDOW = 0.4,
    BALANCE_DETECT = true, BALANCE_ONLY = true, BALANCE_DELTA_MIN = 1, BALANCE_OBS_WINDOW = 1.2,
    BALANCE_POLL = 0.05, BALANCE_READY_TIMEOUT = 5.0,
    BALANCE_GUI_SEGMENTS = { "PlayerGui", "MainGUI", "Game", "CoinBags", "Container", "BeachBall" },
    BALANCE_TEXT_CHILD_NAME = nil, BALANCE_LEADERSTATS_NAME = "leaderstats",
    BALANCE_KEYS = { "BeachBall", "BeachBalls", "BeachBalls2025", "Coins", "Money", "Cash", "Tokens" },
    OPEN_ENABLE_LOOP = true, BB_WATCH_ENABLE = true, BB_WATCH_INTERVAL = 300,
    BB_WATCH_KICK_MSG = "No BeachBalls gained in the last 5 minutes. Kicking...",
    OPEN_ARGS = { "Summer2025Box", "MysteryBox", "BeachBalls2025" }, OPEN_THRESHOLD = 800,
    OBS_TIMEOUT_SEC = 3.0, OBS_POLL_SEC = 0.15, OPTIMIZE = true, ANTIAFK = true,
    OVERLAY_ON_AT_START = true, DISABLE_3D_RENDER = true, BLACK_WORLD = true,
}

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local HttpService = game:GetService("HttpService")
local Heartbeat = RunService.Heartbeat
local LP = Players.LocalPlayer
local PlayerGui = LP:WaitForChild("PlayerGui")

do
    local function changeDevice()
        local ok, rem = pcall(function()
            return ReplicatedStorage:WaitForChild("Remotes", 2):WaitForChild("Extras", 2):WaitForChild("ChangeLastDevice", 2)
        end)
        if ok and rem then pcall(function() rem:FireServer("Tablet") end) end
    end
    local function setAttr() pcall(function() PlayerGui:SetAttribute("Device", "Tablet") end) end
    local function click(btn)
        local ok = pcall(function() btn:Activate() end)
        if not ok then
            local c = btn.AbsolutePosition + (btn.AbsoluteSize / 2)
            VirtualInputManager:SendMouseButtonEvent(c.X, c.Y, 0, true, btn, 0)
            VirtualInputManager:SendMouseButtonEvent(c.X, c.Y, 0, false, btn, 0)
        end
    end
    local function trySelect(parent)
        local ok, tabletBtn = pcall(function()
            local container = parent and parent:WaitForChild("Container", 5)
            local tablet = container and container:WaitForChild("Tablet", 5)
            return tablet and tablet:WaitForChild("Button", 5) or nil
        end)
        if ok and tabletBtn and tabletBtn:IsA("GuiButton") then
            changeDevice(); setAttr(); click(tabletBtn); return true
        end
        return false
    end
    PlayerGui.ChildAdded:Connect(function(child) if child.Name == "DeviceSelect" then task.defer(function() trySelect(child) end) end end)
    task.defer(function() local ex = PlayerGui:FindFirstChild("DeviceSelect"); if ex then trySelect(ex) end end)
end

local openCrate = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Shop"):WaitForChild("OpenCrate")
local Sync = require(ReplicatedStorage:WaitForChild("Database"):WaitForChild("Sync"))
local ProfileData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ProfileData"))

local G = getgenv().TLfig
local function D(k) return DEFAULTS[k] end
_G.DEBUG = (_G.Debug ~= false)
G.AUTOCOLLECT = (G.AutoFarm ~= false)
G.OPEN_ENABLE_LOOP = (G.OpenCrate ~= false) and D("OPEN_ENABLE_LOOP")
for k, v in pairs(DEFAULTS) do if G[k] == nil then G[k] = v end end

local function dbg(...) if _G.DEBUG then print("[bug]", ...) end end
local function log(...) print("[UGCrate]", ...) end
local function warnl(...) warn("[UGCrate]", ...) end

local function toNumber(v)
    if typeof(v) == "number" then return v end
    if typeof(v) == "string" then
        local n = tonumber((v:gsub("[^%d%-]", "")))
        if n then return n end
    end
end

local Character = LP.Character or LP.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid")
local HRP = Character:WaitForChild("HumanoidRootPart")
local function refreshCharacter() Character = LP.Character or LP.CharacterAdded:Wait(); Humanoid = Character:WaitForChild("Humanoid"); HRP = Character:WaitForChild("HumanoidRootPart") end
local function safeHRPPos() if Character and Character.Parent and HRP and HRP.Parent then return HRP.Position end end
local function dist(a, b) return (a - b).Magnitude end

local LAST_WALLET_BB, __lastRemoteAt = nil, 0
local BB_KEYS = { "BeachBalls2025", "BeachBalls", "BeachBall", "Beach Balls" }
local function updateSticky(n) if n then LAST_WALLET_BB = tonumber(n) or LAST_WALLET_BB end end

local function readFromProfile()
    local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local Inventory = Remotes and Remotes:FindFirstChild("Inventory") or Remotes and Remotes:FindFirstChild("Inventory")
    local GetProfileData = Inventory and Inventory:FindFirstChild("GetProfileData")
    if not (GetProfileData and GetProfileData:IsA("RemoteFunction")) then return nil end
    local ok, data = pcall(function() return GetProfileData:InvokeServer() end)
    if not ok or type(data) ~= "table" then return nil end
    local owned = (((data or {}).Materials or {}).Owned) or {}
    for _, key in ipairs(BB_KEYS) do
        local n = toNumber(owned[key]); if n then return n end
    end
    return nil
end

local function readFromLeaderstats()
    local ls = LP:FindFirstChild("leaderstats"); if not ls then return nil end
    for _, key in ipairs(BB_KEYS) do
        local v = ls:FindFirstChild(key)
        if v and (v:IsA("IntValue") or v:IsA("NumberValue") or v:IsA("StringValue")) then
            local n = toNumber(v.Value); if n then return n end
        end
    end
    return nil
end

local function attachLeaderstatsWatchers()
    local function connectValue(v)
        if not v then return end
        if not (v:IsA("IntValue") or v:IsA("NumberValue") or v:IsA("StringValue")) then return end
        local function update() updateSticky(toNumber(v.Value)) end
        update(); v:GetPropertyChangedSignal("Value"):Connect(update)
    end
    local function scan(ls)
        if not ls then return end
        for _, k in ipairs(BB_KEYS) do connectValue(ls:FindFirstChild(k)) end
        ls.ChildAdded:Connect(function(c) for _, k in ipairs(BB_KEYS) do if c.Name == k then connectValue(c) break end end end)
    end
    scan(LP:FindFirstChild("leaderstats"))
    LP.ChildAdded:Connect(function(c) if c.Name == "leaderstats" then scan(c) end end)
end

local function startProfilePoller()
    task.spawn(function()
        while true do
            task.wait(12)
            local n = readFromProfile()
            if n then updateSticky(n) end
        end
    end)
end

local function getBeachballsWalletOnly()
    if LAST_WALLET_BB ~= nil then return LAST_WALLET_BB end
    local ls = readFromLeaderstats(); if ls then updateSticky(ls); return ls end
    local rf = readFromProfile(); if rf then updateSticky(rf); return rf end
    return nil
end

local function getBeachballsWalletOnlySafe()
    local ls = readFromLeaderstats(); if ls ~= nil then updateSticky(ls); return ls end
    if os.clock() - __lastRemoteAt > 10 then
        __lastRemoteAt = os.clock()
        local rf = readFromProfile(); if rf ~= nil then updateSticky(rf); return rf end
    end
    return LAST_WALLET_BB
end

do
    attachLeaderstatsWatchers(); startProfilePoller()
    local count = getBeachballsWalletOnly()
    if count ~= nil then print(string.format("[BB] BeachBalls (wallet): %d", count)) else warn("[BB] Không đọc được BeachBalls ví (remote/leaderstats).") end
end

getgenv().GetBeachballCount = function()
    local n = getBeachballsWalletOnly()
    if n ~= nil then print(string.format("[BB] BeachBalls (wallet): %d", n)) else warn("[BB] Không đọc được số BeachBalls ví.") end
    return n
end

local function matchesName(partName)
    local names = (G.COIN_NAMES or {}); local mode = (G.NAME_MATCH_MODE or "contains"):lower()
    for _, key in ipairs(names) do
        if typeof(key) == "string" then
            local exact = (mode == "exact" and partName == key)
            local contains = (mode == "contains" and string.find(partName, key, 1, true) ~= nil)
            if exact or contains then return true end
        end
    end
    return false
end

local function coinIsCollectible(inst)
    if not inst or not inst.Parent or not inst:IsDescendantOf(Workspace) or not inst:IsA("BasePart") then return false end
    if not matchesName(inst.Name) then return false end
    if G.REQUIRE_TOUCHINTEREST and (not inst:FindFirstChild("TouchInterest", true)) then return false end
    return true
end

local function selectTouchTarget(rootPart)
    if not G.SCAN_DESC_TOUCH then return rootPart end
    if rootPart:FindFirstChild("TouchInterest") then return rootPart end
    local best, score = rootPart, 0
    for _, d in ipairs(rootPart:GetDescendants()) do
        if d:IsA("BasePart") then
            local hasTouch = d:FindFirstChild("TouchInterest") and 10 or 0
            local sizeScore = (d.Size.X + d.Size.Y + d.Size.Z)
            local sc = hasTouch + sizeScore
            if sc > score then best, score = d, sc end
        end
    end
    return best
end

local function topOf(part) local cf, size = part.CFrame, part.Size; return cf.Position + cf.UpVector * (size.Y * 0.5) + Vector3.new(0, G.HEIGHT_OFFSET or 2.5, 0) end

local CoinSet, CoinList, lastHardRescan = {}, {}, 0
local function addIfCoin(inst)
    if not inst or not inst.Parent or not inst:IsA("BasePart") then return end
    if not matchesName(inst.Name) then return end
    CoinSet[inst] = true
    inst.AncestryChanged:Connect(function(_, parent) if not parent then CoinSet[inst] = nil end end)
    pcall(function() inst.Destroying:Connect(function() CoinSet[inst] = nil end) end)
end

local function buildIndexFull()
    CoinSet = {}
    for _, d in ipairs(Workspace:GetDescendants()) do addIfCoin(d) end
    dbg("Indexed coins:", (next(CoinSet) and "ok") or "empty")
end

Workspace.DescendantAdded:Connect(addIfCoin)

local function getNearbyCoins_index(originPos, limit)
    CoinList = {}
    for inst in pairs(CoinSet) do
        if coinIsCollectible(inst) and dist(originPos, inst.Position) <= limit then
            table.insert(CoinList, inst)
        else
            CoinSet[inst] = nil
        end
    end
    table.sort(CoinList, function(a, b) return dist(originPos, a.Position) < dist(originPos, b.Position) end)
    return CoinList
end

local function getNearbyCoins_radius(originPos, limit)
    local params = OverlapParams.new()
    if G.RADIUS_BLACKLIST_HRP and Character then params.FilterType = Enum.RaycastFilterType.Blacklist; params.FilterDescendantsInstances = { Character } end
    local around = Workspace:GetPartBoundsInRadius(originPos, limit, params) or {}
    local list = {}
    for _, p in ipairs(around) do if coinIsCollectible(p) then table.insert(list, p) end end
    table.sort(list, function(a, b) return dist(originPos, a.Position) < dist(originPos, b.Position) end)
    return list
end

local function getNearbyCoins(originPos)
    local limit = G.MAX_FARM_RADIUS or math.huge
    if (G.SCAN_METHOD or "radius") == "index" then return getNearbyCoins_index(originPos, limit) else return getNearbyCoins_radius(originPos, limit) end
end

local UnderAnchorCFrame, UnderActive = nil, false
local function setupUnderAnchor()
    local here = safeHRPPos(); if not here then return end
    HRP.Anchored = true
    UnderAnchorCFrame = CFrame.new(here.X, here.Y - (G.UNDER_HEIGHT or 100), here.Z)
    HRP.CFrame = UnderAnchorCFrame; UnderActive = true; dbg("Underground anchor")
end

local function resetUnderAnchor()
    if HRP and HRP.Parent then HRP.Anchored = false end
    UnderActive = false; UnderAnchorCFrame = nil; dbg("Underground cleared")
end

local firetouch = rawget(getfenv and getfenv() or {}, "firetouchinterest") or _G.firetouchinterest
local function fireTouchPair(a, b)
    if not firetouch or not G.USE_FIRETOUCH then return end
    pcall(function() firetouch(a, b, 0) end); Heartbeat:Wait(); pcall(function() firetouch(a, b, 1) end)
end

local function stopVelocity() if not HRP then return end HRP.AssemblyLinearVelocity = Vector3.new(); HRP.AssemblyAngularVelocity = Vector3.new() end
local function snap(cf) HRP.Anchored = false; stopVelocity(); HRP.CFrame = cf; Heartbeat:Wait() end

local function overlappedWithTarget(target)
    if not G.OVERLAP_VERIFY then return true end
    if not HRP or not target then return false end
    local pad = G.OVERLAP_BOX_PAD or Vector3.new(2, 2, 2)
    local size = HRP.Size + pad
    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Whitelist
    params.FilterDescendantsInstances = { target }
    local parts = Workspace:GetPartBoundsInBox(HRP.CFrame, size, params) or {}
    for _, p in ipairs(parts) do if p == target or p:IsDescendantOf(target) then return true end end
    return false
end

local function resolveFromLocalPlayer(segs)
    local cur = Players.LocalPlayer
    for _, name in ipairs(type(segs) == "table" and segs or {}) do if not cur then return nil end cur = cur:FindFirstChild(name); if not cur then return nil end end
    return cur
end

local function parseNumberFromText(s) if type(s) ~= "string" then return nil end local d = s:gsub("[^%d]", ""); if d == "" then return nil end return tonumber(d) end

local function makeGuiBalanceReader()
    local segs = G.BALANCE_GUI_SEGMENTS
    if type(segs) ~= "table" or not next(segs) then return nil end
    local root = resolveFromLocalPlayer(segs); if not root then return nil end
    if root:IsA("TextLabel") or root:IsA("TextButton") then return function() return parseNumberFromText(root.Text) or 0 end end
    local specified = G.BALANCE_TEXT_CHILD_NAME
    if specified then
        local c = root:FindFirstChild(specified, true)
        if c and (c:IsA("TextLabel") or c:IsA("TextButton")) then return function() return parseNumberFromText(c.Text) or 0 end end
    end
    for _, d in ipairs(root:GetDescendants()) do if d:IsA("TextLabel") or d:IsA("TextButton") then return function() return parseNumberFromText(d.Text) or 0 end end end
    for _, d in ipairs(root:GetDescendants()) do if d:IsA("NumberValue") or d:IsA("IntValue") then return function() return tonumber(d.Value) or 0 end end end
    return nil
end

local function makeLeaderstatsBalanceReader()
    local ls = Players.LocalPlayer:FindFirstChild(G.BALANCE_LEADERSTATS_NAME or "leaderstats"); if not ls then return nil end
    for _, k in ipairs(G.BALANCE_KEYS or { "Coins" }) do
        local v = ls:FindFirstChild(k)
        if v and (v:IsA("IntValue") or v:IsA("NumberValue")) then return function() return tonumber(v.Value) or 0 end end
    end
    return nil
end

local BAL_GETTER = nil
local function ensureBalanceGetter() BAL_GETTER = makeGuiBalanceReader(); if not BAL_GETTER and not G.BALANCE_ONLY then BAL_GETTER = makeLeaderstatsBalanceReader() end return BAL_GETTER ~= nil end
local function ensureBalanceReady(timeout)
    if not G.BALANCE_DETECT then return true end
    local tmax = timeout or (G.BALANCE_READY_TIMEOUT or 5); local t0 = os.clock()
    repeat if ensureBalanceGetter() then return true end task.wait(0.2) until os.clock() - t0 > tmax
    return false
end
local function getBalanceNow()
    if not G.BALANCE_DETECT then return nil end
    if not BAL_GETTER then if not ensureBalanceReady() then return nil end end
    local ok, val = pcall(BAL_GETTER); if not ok then return nil end
    return tonumber(val) or 0
end

local function waitForBalanceIncrease(prev)
    if not G.BALANCE_DETECT then return false end
    local minDelta = G.BALANCE_DELTA_MIN or 1; local window = G.BALANCE_OBS_WINDOW or 1.2; local poll = G.BALANCE_POLL or 0.05
    local t0 = os.clock()
    while os.clock() - t0 <= window do
        task.wait(poll)
        local cur = getBalanceNow()
        if cur and prev and (cur - prev) >= minDelta then return true end
    end
    return false
end

local FailMap = {}
local function inCooldown(coin) local f = FailMap[coin]; return f and f.until_ts and (os.clock() < f.until_ts) end
local function addFail(coin)
    local f = FailMap[coin] or { count = 0, until_ts = 0 }
    f.count = f.count + 1
    if f.count >= (G.MAX_FAIL_PER_VISIT or 2) then f.until_ts = os.clock() + (G.FAIL_COOLDOWN_SEC or 8); f.count = 0; dbg("Cooldown coin") end
    FailMap[coin] = f
end
local function clearFail(coin) FailMap[coin] = nil end

local CURRENT_JOB = 0
local function newJob() CURRENT_JOB = CURRENT_JOB + 1; return CURRENT_JOB end
local function jobActive(id) return id == CURRENT_JOB end

local function teleportToCoin_job(coin, jobId)
    if not jobActive(jobId) or not coinIsCollectible(coin) or inCooldown(coin) then return false end
    local target = selectTouchTarget(coin); if not target or not target.Parent then return false end
    local useBalance = G.BALANCE_DETECT
    if useBalance and (not ensureBalanceReady()) and G.BALANCE_ONLY then dbg("Balance GUI not ready -> skip"); addFail(coin); return false end
    local balBefore = useBalance and getBalanceNow() or nil
    local topPos = topOf(target); snap(CFrame.new(topPos)); task.wait(G.TOUCH_TIME or 0.12)
    if firetouch and G.USE_FIRETOUCH then
        fireTouchPair(HRP, target); fireTouchPair(target, HRP)
        for _, d in ipairs(target:GetDescendants()) do if d:IsA("BasePart") then fireTouchPair(HRP, d); fireTouchPair(d, HRP) end end
        Heartbeat:Wait()
    end
    local success = false
    if useBalance and balBefore then success = waitForBalanceIncrease(balBefore) end
    if not success and not G.BALANCE_ONLY then
        if not target.Parent then success = true
        else
            local startY, t0j = target.Position.Y, os.clock()
            while os.clock() - t0j <= (G.JUMP_WINDOW or 0.4) and target.Parent do
                task.wait(0.03)
                if (target.Position.Y - startY) >= (G.JUMP_DELTA_Y or 2.0) then success = true; break end
            end
            if not success and overlappedWithTarget(target) then success = true end
        end
    end
    if success then clearFail(coin) else addFail(coin) end
    if UnderAnchorCFrame and jobActive(jobId) then HRP.Anchored = true; stopVelocity(); HRP.CFrame = UnderAnchorCFrame else stopVelocity() end
    return success
end

local antiAFKThread = nil
local function startAntiAFK()
    if antiAFKThread or not G.ANTIAFK then return end
    dbg("Anti-AFK started")
    antiAFKThread = task.spawn(function()
        while G.ANTIAFK do
            task.wait(60)
            pcall(function()
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.L, false, game); task.wait(0.1)
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.L, false, game)
            end)
        end
    end)
end

local function isCharacterDescendant(inst) return Character and inst:IsDescendantOf(Character) end
local function isCoinPart(inst) return inst:IsA("BasePart") and matchesName(inst.Name) end

local function forceBlackLighting()
    pcall(function()
        Lighting.Brightness = 0; Lighting.GlobalShadows = false; Lighting.Ambient = Color3.new(0, 0, 0); Lighting.OutdoorAmbient = Color3.new(0, 0, 0)
        Lighting.ColorShift_Bottom = Color3.new(0, 0, 0); Lighting.ColorShift_Top = Color3.new(0, 0, 0)
        Lighting.EnvironmentDiffuseScale = 0; Lighting.EnvironmentSpecularScale = 0; Lighting.ExposureCompensation = -2
        Lighting.ClockTime = 0; Lighting.FogColor = Color3.new(0, 0, 0); Lighting.FogStart = 0; Lighting.FogEnd = 25
        for _, c in ipairs(Lighting:GetChildren()) do if c:IsA("PostEffect") then c.Enabled = false end end
        local sky = Lighting:FindFirstChildOfClass("Sky"); if sky then sky:Destroy() end
        Lighting.ChildAdded:Connect(function(inst)
            task.defer(function()
                if inst:IsA("PostEffect") then inst.Enabled = false end
                if inst:IsA("Sky") then pcall(function() inst:Destroy() end) end
            end)
        end)
    end)
end

local function killVisualCosts()
    if not G.OPTIMIZE then return end
    dbg("Optimize mode")
    if G.DISABLE_3D_RENDER then
        pcall(function() if RunService.Set3dRenderingEnabled then RunService:Set3dRenderingEnabled(false) end end)
        pcall(function() if setrenderproperty then setrenderproperty(false) end end)
    end
    if G.BLACK_WORLD then
        forceBlackLighting()
    else
        pcall(function()
            Lighting.GlobalShadows = false; Lighting.FogStart = 0; Lighting.FogEnd = 50
            for _, c in ipairs(Lighting:GetChildren()) do if c:IsA("PostEffect") then c.Enabled = false end end
            local atmos = Lighting:FindFirstChildOfClass("Atmosphere"); if atmos then atmos.Density = 0 end
        end)
    end
    pcall(function()
        local t = Workspace:FindFirstChildOfClass("Terrain")
        if t then t.WaterReflectance = 0; t.WaterTransparency = 1; t.WaterWaveSize = 0; t.WaterWaveSpeed = 0; t.Decoration = false end
    end)
    pcall(function()
        SoundService.Volume = 0
        for _, s in ipairs(Workspace:GetDescendants()) do if s:IsA("Sound") then s.Volume = 0; s.Playing = false end end
    end)
    for _, inst in ipairs(Workspace:GetDescendants()) do
        if inst:IsA("BasePart") then
            if not isCharacterDescendant(inst) and not isCoinPart(inst) then
                pcall(function()
                    if G.BLACK_WORLD then inst.Color = Color3.new(0, 0, 0); inst.Material = Enum.Material.SmoothPlastic; inst.LocalTransparencyModifier = 1
                    else inst.LocalTransparencyModifier = 1; inst.CastShadow = false; inst.Material = Enum.Material.SmoothPlastic; inst.Reflectance = 0 end
                end)
            else pcall(function() inst.LocalTransparencyModifier = 0 end) end
        elseif inst:IsA("Decal") or inst:IsA("Texture") then
            if not isCharacterDescendant(inst) then pcall(function() if G.BLACK_WORLD then inst.Color3 = Color3.new(0, 0, 0) end inst.Transparency = 1 end) end
        elseif inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam") or inst:IsA("Explosion") or inst:IsA("Fire") or inst:IsA("Smoke") or inst:IsA("Sparkles") then
            pcall(function() inst.Enabled = false end)
        elseif inst:IsA("Light") then
            pcall(function() inst.Enabled = false; if inst.Color then inst.Color = Color3.new(0, 0, 0) end end)
        end
    end
    Workspace.DescendantAdded:Connect(function(inst)
        task.defer(function()
            if inst:IsA("BasePart") then
                if not isCharacterDescendant(inst) and not isCoinPart(inst) then
                    pcall(function()
                        if G.BLACK_WORLD then inst.Color = Color3.new(0, 0, 0); inst.Material = Enum.Material.SmoothPlastic; inst.LocalTransparencyModifier = 1
                        else inst.LocalTransparencyModifier = 1; inst.CastShadow = false; inst.Material = Enum.Material.SmoothPlastic; inst.Reflectance = 0 end
                    end)
                else pcall(function() inst.LocalTransparencyModifier = 0 end) end
            elseif inst:IsA("Decal") or inst:IsA("Texture") then
                if not isCharacterDescendant(inst) then pcall(function() if G.BLACK_WORLD then inst.Color3 = Color3.new(0, 0, 0) end inst.Transparency = 1 end) end
            elseif inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam") or inst:IsA("Explosion") or inst:IsA("Fire") or inst:IsA("Smoke") or inst:IsA("Sparkles") then
                pcall(function() inst.Enabled = false end)
            elseif inst:IsA("Light") then
                pcall(function() inst.Enabled = false; if inst.Color then inst.Color = Color3.new(0, 0, 0) end end)
            elseif inst:IsDescendantOf(Lighting) and inst:IsA("PostEffect") then pcall(function() inst.Enabled = false end)
            elseif inst:IsA("Sound") then pcall(function() inst.Volume = 0; inst.Playing = false end) end
        end)
    end)
end

local farmRunning = false
local function runFarm()
    if not G.AUTOCOLLECT or farmRunning then return end
    farmRunning = true
    if (G.SCAN_METHOD or "radius") == "index" then buildIndexFull(); lastHardRescan = os.clock() end
    dbg("Farm started")
    local lastProgress = os.clock()
    while G.AUTOCOLLECT do
        if (not Character) or (not Character.Parent) or (not HRP) or (not HRP.Parent) or (not Humanoid) or Humanoid.Health <= 0 then
            dbg("Character refresh..."); refreshCharacter(); resetUnderAnchor(); task.wait(0.4)
        end
        if (G.SCAN_METHOD or "radius") == "index" and os.clock() - lastHardRescan >= (G.HARD_RESCAN_SEC or 5) then buildIndexFull(); lastHardRescan = os.clock() end
        if os.clock() - lastProgress > (G.STUCK_RESET_SEC or 15) then
            dbg("Watchdog: no progress -> hard reset"); resetUnderAnchor()
            if (G.SCAN_METHOD or "radius") == "index" then buildIndexFull(); lastHardRescan = os.clock() end
            newJob(); task.wait(0.2); lastProgress = os.clock()
        end
        local origin = (UnderAnchorCFrame and UnderAnchorCFrame.Position) or (safeHRPPos() or Vector3.new())
        local coins = getNearbyCoins(origin) or {}
        if #coins == 0 then
            if UnderActive then resetUnderAnchor() end
            task.wait(G.RESCAN_INTERVAL or 1.2)
        else
            if G.UNDERGROUND_MODE and not UnderActive then setupUnderAnchor(); origin = UnderAnchorCFrame.Position end
            local jobId = newJob(); local processed = 0
            for _, coin in ipairs(coins) do
                if not G.AUTOCOLLECT or not jobActive(jobId) or processed >= (G.MAX_COINS_PER_TICK or 10) then break end
                if coinIsCollectible(coin) and not inCooldown(coin) then
                    local ok = teleportToCoin_job(coin, jobId); processed = processed + 1; task.wait(G.TELE_DELAY or 1.0); if ok then lastProgress = os.clock() end
                end
            end
            if processed == 0 then task.wait(0.15) end
        end
    end
    dbg("Farm stopped"); resetUnderAnchor(); farmRunning = false
end

local CATEGORIES = { "Weapons", "Effects", "Perks", "Emotes", "Radios", "Pets" }
local KEY_OR_VALUE_FOR = { Weapons = true, Pets = true }
local function getCatDB(cat) if cat == "Emotes" then return Sync.Emotes elseif cat == "Toys" then return Sync.Toys else return Sync[cat] end end
local function getItemInfo(cat, id) local db = getCatDB(cat); if not db then return nil end return db[id] or nil end
local function displayNameOf(cat, id) local info = getItemInfo(cat, id); if info then return (info.ItemName or info.DisplayName or info.Name), info else return tostring(id), nil end end
local TIER_TO_RARITY = { [1] = "Common", [2] = "Uncommon", [3] = "Rare", [4] = "Legendary", [5] = "Godly" }
local VALID_RARITIES = { Common = true, Uncommon = true, Rare = true, Legendary = true, Godly = true }

local function normalizeRarity(info)
    if not info then return "Unknown" end
    local r = info.Rarity or info.RarityName or info.RarityTier or info.Tier
    local out = nil
    if type(r) == "number" then out = TIER_TO_RARITY[r]
    elseif type(r) == "string" then local s = r:gsub("^%l", string.upper); out = VALID_RARITIES[s] and s or "Unknown" end
    return out or "Unknown"
end

local function resolveUniqueWeaponID(u)
    local baseId = u.BaseItem
    if not u.EvoEquipped then return baseId end
    local baseInfo = Sync.Weapons[baseId]; if not baseInfo or not baseInfo.Evo then return baseId end
    local xp, stage = u.XP or 0, 1
    if baseInfo.Evo[2] and xp >= baseInfo.Evo[2].XPRequired then stage = 2 end
    if baseInfo.Evo[3] and xp >= baseInfo.Evo[3].XPRequired then stage = 3 end
    if baseInfo.Evo[4] and xp >= baseInfo.Evo[4].XPRequired then stage = 4 end
    local evo = baseInfo.Evo[stage]; if evo and evo.ItemName then return evo.ItemName else return baseId end
end

local function snapshotInventoryFlat()
    local flat = {}
    for _, cat in ipairs(CATEGORIES) do
        local owned = ProfileData[cat] and ProfileData[cat].Owned
        if owned then
            for k, v in pairs(owned) do
                local id = KEY_OR_VALUE_FOR[cat] and (k or v) or v
                local count = tonumber(v) or 1
                local name = displayNameOf(cat, id)
                flat[name] = (flat[name] or 0) + count
            end
        end
    end
    if ProfileData.Uniques then
        for _, u in pairs(ProfileData.Uniques) do
            local wid = resolveUniqueWeaponID(u)
            local name = displayNameOf("Weapons", wid)
            flat[name] = (flat[name] or 0) + 1
        end
    end
    return flat
end

local function snapshotInventoryRarity()
    local flat = {}
    for _, cat in ipairs(CATEGORIES) do
        local owned = ProfileData[cat] and ProfileData[cat].Owned
        if owned then
            for k, _ in pairs(owned) do
                local id = KEY_OR_VALUE_FOR[cat] and k or k
                local name, info = displayNameOf(cat, id)
                local rar = normalizeRarity(info)
                flat[name] = rar
            end
        end
    end
    if ProfileData.Uniques then
        for _, u in pairs(ProfileData.Uniques) do
            local wid = resolveUniqueWeaponID(u)
            local name, info = displayNameOf("Weapons", wid)
            local rar = normalizeRarity(info)
            flat[name] = rar
        end
    end
    return flat
end

local function diffAdded(prev, cur)
    local added = {}
    for name, c in pairs(cur) do local p = prev[name] or 0; if c > p then added[name] = c - p end end
    return added
end

local __lastWebhookAt = 0
local function getRequester() return (syn and syn.request) or http_request or request end
local RARITY_COLOR = { Common = 0x9aa0a6, Uncommon = 0x34a853, Rare = 0x4285f4, Legendary = 0xfbbc04, Godly = 0xdb4437, Default = 0x9aa0a6 }

local function sendDiscordPayload(urls, payload)
    local req = getRequester(); if not req then warn("[WH] Executor không hỗ trợ http_request/syn.request/request"); return end
    if type(urls) ~= "table" or #urls == 0 then return end
    local dt = os.clock() - __lastWebhookAt; if dt < 0.6 then task.wait(0.6 - dt) end
    for _, url in ipairs(urls) do
        local ok, res = pcall(function()
            return req({ Url = url, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = HttpService:JSONEncode(payload) })
        end)
        if ok and res and res.StatusCode and res.StatusCode >= 200 and res.StatusCode < 300 then print("[WH] OK:", url) else warn("[WH] FAIL:", url, res and res.StatusCode, res and res.StatusMessage) end
    end
    __lastWebhookAt = os.clock()
end

local function shouldSendPrivateByRarity(rar) local t = (G.Webhook.Rarity) or {}; return t[rar] == true end
local function shouldSendPublicByRarity(rar) return PUBLIC_WEBHOOK_RARITY[rar] == true end
local function collectWebhookUrlsByRarity(rarity)
    if not VALID_RARITIES[rarity] then return {} end
    local urls = {}
    local priv = tostring(getgenv().TLfig.Webhook.URL or "")
    if priv ~= "" and shouldSendPrivateByRarity(rarity) then table.insert(urls, priv) end
    if PUBLIC_WH_ENABLED and PUBLIC_WEBHOOK ~= "" and shouldSendPublicByRarity(rarity) then table.insert(urls, PUBLIC_WEBHOOK) end
    return urls
end

local function sendItemWebhook_ByRarity(itemName, rarity, count, jobId)
    local urls = collectWebhookUrlsByRarity(rarity); if #urls == 0 then return end
    local embed = {
        title = "Opened: " .. tostring(itemName),
        description = string.format("• **Rarity:** %s\n• **Count:** %s", tostring(rarity), tostring(count or 1)),
        color = (RARITY_COLOR[rarity] or RARITY_COLOR.Default),
        author = { name = string.format("@%s • %s", Players.LocalPlayer.Name, Players.LocalPlayer.DisplayName) },
        thumbnail = { url = string.format("https://github.com/user-attachments/assets/d46f45d6-e4cd-4b9e-a3fc-7e64fa94d8d0", Players.LocalPlayer.UserId) },
        footer = { text = string.format("%s TIME", os.date("!%H:%M:%SZ")) },
    }
    local payload = { username = string.format(Players.LocalPlayer.DisplayName), embeds = { embed } }
    sendDiscordPayload(urls, payload)
end

local OPEN_JOB_ID = 0
local function nextOpenJob() OPEN_JOB_ID = OPEN_JOB_ID + 1; return OPEN_JOB_ID end
getgenv().GAG_CratesOpened = getgenv().GAG_CratesOpened or 0

local function runOpenByThreshold()
    if not G.OPEN_ENABLE_LOOP then return end
    local ARGS = G.OPEN_ARGS or { "Summer2025Box" }
    local TH = tonumber(G.OPEN_THRESHOLD or 800) or 800
    log("Crate auto-open by WALLET threshold >= " .. tostring(TH))
    while true do
        local bb = getBeachballsWalletOnlySafe()
        if bb and bb >= TH then
            local jobId = nextOpenJob()
            local prevFlat = snapshotInventoryFlat()
            local ok, res = pcall(function() return openCrate:InvokeServer(unpack(ARGS)) end)
            if ok then getgenv().GAG_CratesOpened = (tonumber(getgenv().GAG_CratesOpened) or 0) + 1; log("Opened crate: " .. table.concat(ARGS, ", "))
            else warnl("Open crate failed: " .. tostring(res)) end
            local timeout = G.OBS_TIMEOUT_SEC or 3.0; local poll = G.OBS_POLL_SEC or 0.15; local t0 = os.clock(); local sentAny = false
            repeat
                task.wait(poll)
                local curFlat = snapshotInventoryFlat()
                local added = diffAdded(prevFlat, curFlat)
                if next(added) ~= nil then
                    local curRarity = snapshotInventoryRarity()
                    for name, delta in pairs(added) do
                        local rar = curRarity[name] or "Unknown"
                        sendItemWebhook_ByRarity(name, rar, delta, jobId)
                    end
                    sentAny = true; break
                end
            until (os.clock() - t0) > timeout
            if not sentAny then log("No new item detected within window.") end
            task.wait(0.6)
        else
            task.wait(0.6)
        end
    end
end

local function createOverlay()
    local gui = Instance.new("ScreenGui")
    gui.Name = "GAG_Overlay"; gui.IgnoreGuiInset = true; gui.ResetOnSpawn = false; gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    local ok = pcall(function() gui.Parent = game:GetService("CoreGui") end)
    if not ok then local pg = LP:FindFirstChildOfClass("PlayerGui") or LP:WaitForChild("PlayerGui"); gui.Parent = pg end
    local blackout = Instance.new("Frame")
    blackout.Name = "Blackout"; blackout.BackgroundColor3 = Color3.new(0, 0, 0); blackout.BackgroundTransparency = 0; blackout.BorderSizePixel = 0
    blackout.Size = UDim2.fromScale(1, 1); blackout.Position = UDim2.new(0, 0, 0, 0); blackout.ZIndex = 10; blackout.Parent = gui
    local label = Instance.new("TextLabel")
    label.Name = "AccountName"; label.AnchorPoint = Vector2.new(0.5, 0.5); label.Position = UDim2.fromScale(0.5, 0.40)
    label.Size = UDim2.new(0.9, 0, 0, 120); label.BackgroundTransparency = 1; label.Text = LP.Name
    label.Font = Enum.Font.GothamBlack; label.TextScaled = true; label.TextColor3 = Color3.fromRGB(230, 230, 250)
    label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0); label.TextStrokeTransparency = 0.3; label.ZIndex = 11; label.Parent = blackout
    local btn = Instance.new("TextButton")
    btn.Name = "ToggleOverlay"; btn.AnchorPoint = Vector2.new(1, 0); btn.Position = UDim2.new(1, -20, 0, 20); btn.Size = UDim2.new(0, 140, 0, 40)
    btn.Font = Enum.Font.GothamBold; btn.TextSize = 18; btn.AutoButtonColor = true; btn.ZIndex = 20; btn.Parent = gui    btn.BackgroundColor3 = Color3.fromRGB(25, 25, 25); btn.TextColor3 = Color3.fromRGB(255, 255, 255); btn.Text = "Button: ON"

    local cornerBtn = Instance.new("UICorner", btn); cornerBtn.CornerRadius = UDim.new(0, 8)
    local st = Instance.new("UIStroke", btn); st.Thickness = 1; st.Color = Color3.fromRGB(90, 90, 90)
    local overlayOn = G.OVERLAY_ON_AT_START ~= false
    local function setOverlay(v)
        overlayOn = v; blackout.Visible = v
        local big = blackout:FindFirstChild("BeachballHUD_Big"); if big then big.Visible = v end
        local crates = blackout:FindFirstChild("CrateHUD_Big"); if crates then crates.Visible = v end
        local compact = gui:FindFirstChild("BeachballHUD_Compact"); if compact then compact.Visible = not v end
        btn.Text = v and "Button: ON" or "Button: OFF"
    end
    pcall(function()
        game:GetService("UserInputService").InputBegan:Connect(function(input, gp) if gp then return end if input.KeyCode == Enum.KeyCode.RightShift then setOverlay(not overlayOn) end end)
    end)
    getgenv().ToggleGAGUI = function(v) if typeof(v) == "boolean" then setOverlay(v) else setOverlay(not overlayOn) end end
    btn.MouseButton1Click:Connect(function() setOverlay(not overlayOn) end)
    setOverlay(overlayOn)
    return gui
end

local function startBeachballHUD()
    local gui = nil
    pcall(function() gui = game:GetService("CoreGui"):FindFirstChild("GAG_Overlay") end)
    if not gui then local pg = LP:FindFirstChildOfClass("PlayerGui") or LP:WaitForChild("PlayerGui"); gui = pg:FindFirstChild("GAG_Overlay") end
    if not gui then gui = createOverlay() end
    local blackout = gui:FindFirstChild("Blackout")
    local big = blackout and blackout:FindFirstChild("BeachballHUD_Big")
    if (not big) and blackout then
        big = Instance.new("TextLabel")
        big.Name = "BeachballHUD_Big"; big.AnchorPoint = Vector2.new(0.5, 0); big.Position = UDim2.fromScale(0.5, 0.58)
        big.Size = UDim2.new(0.9, 0, 0, 90); big.BackgroundTransparency = 1; big.ZIndex = 12; big.Font = Enum.Font.GothamBlack
        big.TextScaled = true; big.TextXAlignment = Enum.TextXAlignment.Center; big.TextYAlignment = Enum.TextYAlignment.Center
        big.TextColor3 = Color3.fromRGB(224, 255, 255) big.TextStrokeColor3 = Color3.fromRGB(0, 0, 0); big.TextStrokeTransparency = 0.25
        big.Text = "Beach Balls: …"; big.Parent = blackout
    end
    local cratesBig = blackout and blackout:FindFirstChild("CrateHUD_Big")
    if (not cratesBig) and blackout then
        cratesBig = Instance.new("TextLabel")
        cratesBig.Name = "CrateHUD_Big"; cratesBig.AnchorPoint = Vector2.new(0.5, 0); cratesBig.Position = UDim2.fromScale(0.5, 0.70)
        cratesBig.Size = UDim2.new(0.9, 0, 0, 70); cratesBig.BackgroundTransparency = 1; cratesBig.ZIndex = 12; cratesBig.Font = Enum.Font.GothamSemibold
        cratesBig.TextScaled = true; cratesBig.TextXAlignment = Enum.TextXAlignment.Center; cratesBig.TextYAlignment = Enum.TextYAlignment.Center
        cratesBig.TextColor3 = Color3.fromRGB(101, 67, 33); cratesBig.TextStrokeColor3 = Color3.fromRGB(0, 0, 0); cratesBig.TextStrokeTransparency = 0.3
        cratesBig.Text = "Crates opened: 0"; cratesBig.Parent = blackout
    end
    local card = gui:FindFirstChild("BeachballHUD_Compact")
    if not card then
        card = Instance.new("Frame")
        card.Name = "BeachballHUD_Compact"; card.AnchorPoint = Vector2.new(0, 0); card.Position = UDim2.new(0, 20, 0, 70)
        card.Size = UDim2.new(0, 320, 0, 42); card.BackgroundColor3 = Color3.fromRGB(0, 0, 0); card.BorderSizePixel = 0
        card.ZIndex = 25; card.Visible = not blackout.Visible; card.Parent = gui
        local c2 = Instance.new("UICorner"); c2.CornerRadius = UDim.new(0, 8); c2.Parent = card
        local s2 = Instance.new("UIStroke"); s2.Thickness = 1; s2.Color = Color3.fromRGB(90, 90, 90); s2.Parent = card
        local txt = Instance.new("TextLabel")
        txt.Name = "Value"; txt.BackgroundTransparency = 1; txt.Position = UDim2.new(0, 12, 0, 0); txt.Size = UDim2.fromScale(1, 1)
        txt.Font = Enum.Font.GothamSemibold; txt.TextXAlignment = Enum.TextXAlignment.Left; txt.TextYAlignment = Enum.TextYAlignment.Center
        txt.TextColor3 = Color3.fromRGB(224, 255, 255); txt.TextSize = 18; txt.ZIndex = 26; txt.Text = "Beach Balls: …  |  Crates: 0"; txt.Parent = card
    end
    local compactLabel = card:FindFirstChild("Value")
    task.spawn(function()
        local lastBig, lastSmall, lastCrates = nil, nil, nil
        while true do
            local n = getBeachballsWalletOnlySafe()
            local bbText = (n ~= nil and (" Beach Balls: " .. tostring(n))) or (LAST_WALLET_BB ~= nil and ("Beach Balls: " .. tostring(LAST_WALLET_BB))) or " Beach Balls: …"
            local crates = tonumber(getgenv().GAG_CratesOpened) or 0
            local cratesText = " Crates opened: " .. tostring(crates)
            if big and bbText ~= lastBig then big.Text = bbText; lastBig = bbText end
            if cratesBig and cratesText ~= lastCrates then cratesBig.Text = cratesText; lastCrates = cratesText end
            local smallText = bbText .. "  |  Crates: " .. tostring(crates)
            if compactLabel and smallText ~= lastSmall then compactLabel.Text = smallText; lastSmall = smallText end
            task.wait(0.25)
        end
    end)
end

local function startBeachballWatchdog()
    if not G.BB_WATCH_ENABLE then return end
    task.spawn(function()
        local last = nil
        while true do
            local interval = tonumber(G.BB_WATCH_INTERVAL or 300) or 300
            task.wait(interval)
            local cur = getBeachballsWalletOnlySafe()
            if cur ~= nil then
                cur = tonumber(cur) or cur; last = tonumber(last) or last
                if last == nil then last = cur
                else
                    if cur > last then last = cur
                    elseif cur == last then pcall(function() Players.LocalPlayer:Kick(tostring(G.BB_WATCH_KICK_MSG or "No BeachBalls gained in the last period.")) end); break
                    else last = cur end
                end
            end
        end
    end)
end

if G.OPTIMIZE then task.defer(killVisualCosts) end
if G.ANTIAFK then task.defer(startAntiAFK) end
if G.AUTOCOLLECT then task.defer(runFarm) end
task.defer(startBeachballWatchdog)
task.defer(createOverlay)
task.defer(startBeachballHUD)
task.defer(runOpenByThreshold)
