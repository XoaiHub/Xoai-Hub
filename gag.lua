-- ================================================================
-- Mochi Farm (Luarmor-ready & Emulator-stable, no UI) - FULL (FIX v2)
-- Request: 
--  * Bỏ nhặt full rương -> CHỈ mở rương loại 1 gems & 5 gems
--  * Giữ nguyên các chức năng cũ (fast hop, anti-dead, skip full, no-rejoin, asc/desc+cursor, grace windows, v.v.)
--  * Sửa "create": ở LOBBY nếu không có ai đang create thì hop qua lobby khác tìm server có người đang create,
--    và khi thấy có người đang create thì teleport/nhảy vào create đó. 
-- ================================================================

-- ===== CONFIG =====
local Config = {
    RegionFilterEnabled     = false,
    RegionList              = { "singapore", "tokyo", "us-east" },
    RetryHttpDelay          = 2,

    StrongholdChestName     = "Stronghold Diamond Chest",
    StrongholdPromptTime    = 6,
    StrongholdDiamondWait   = 10,

    FarmPlaceId             = 126509999114328, -- map farm
    LobbyCheckInterval      = 2.0,
    FarmTick                = 1.0,
    DiamondTick             = 0.35,

    HopBackoffMin           = 1.5,
    HopBackoffMax           = 3.0,

    -- Fast hop sau khi NHẶT xong
    HopAfterStronghold      = true,
    HopAfterNormalChest     = true,
    HopPostDelay            = 0.20,

    -- Anti-DEAD
    DeadHopTimeout          = 6.0,
    DeadUiKeywords          = { "dead", "you died", "respawn", "revive" },

    -- Harden
    MaxConsecutiveHopFail   = 5,
    ConsecutiveHopCooloff   = 6.0,
    MaxPagesPrimary         = 8,
    MaxPagesFallback        = 12,

    -- Giảm tỉ lệ hop vào server full (tăng yêu cầu slot tạm thời khi fail)
    MinFreeSlotsDefault     = 1,
    MinFreeSlotsCeil        = 3,

    -- Chọn kiểu server khi HopClassic (FARM)
    ClassicMode             = "Low", -- "Low" hoặc "High"

    -- Chống hop quá sớm (grace windows)
    JoinGraceSeconds        = 4.0,   -- sau khi vừa vào map farm
    FirstDiamondGrace       = 2.5,   -- sau khi nhặt viên kim cương đầu

    -- Chống spam hop (vá)
    HopCooldownMin          = 0.8,   -- tối thiểu giữa 2 lần HopClassic

    -- ===== RƯƠNG CHỈ MỞ 1 & 5 GEMS =====
    AllowedChestGemValues   = {1, 5},

    -- ===== LOBBY CREATE FINDER =====
    MinPlayersOnCreate      = 1,     -- xem là "có người create" nếu >= 1/Max
    LobbyScanTimeout        = 8.0,   -- chờ tối đa 8s để tìm create trong lobby hiện tại, không có thì hop lobby
    LobbyPreferHighPlayers  = true,  -- khi săn lobby có người create, ưu tiên server có nhiều người
}

-- ===== SERVICES =====
local g               = game
local Players         = g:GetService("Players")
local LocalPlayer     = Players.LocalPlayer
local RS              = g:GetService("ReplicatedStorage")
local RunService      = g:GetService("RunService")
local HttpService     = g:GetService("HttpService")
local TeleportService = g:GetService("TeleportService")

-- ===== UTILS =====
local function WaitForChar(timeout)
    timeout = timeout or 15
    local t = 0
    while t < timeout do
        local c = LocalPlayer.Character
        if c and c:FindFirstChild("HumanoidRootPart") and c:FindFirstChild("Humanoid") then
            return c
        end
        t = t + 0.25
        task.wait(0.25)
    end
    return LocalPlayer.Character
end

local function HRP()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function rand(a,b) return a + (b-a)*math.random() end

-- HTTP getter tương thích
local function http_get(url)
    local ok1, res1 = pcall(function() return g:HttpGet(url) end)
    if ok1 and type(res1) == "string" and #res1 > 0 then return res1 end
    local req = (syn and syn.request) or (http and http.request) or (request)
    if req then
        local ok2, res2 = pcall(function() return req({Url = url, Method = "GET"}) end)
        if ok2 and res2 and (res2.Success == nil or res2.Success == true) and type(res2.Body) == "string" then
            return res2.Body
        end
    end
    return nil
end

-- queue_on_teleport tương thích
local function queue_on_teleport_compat(code)
    local f = (syn and syn.queue_on_teleport)
          or  (_G and _G.queue_on_teleport)
          or  queue_on_teleport
          or  (fluxus and fluxus.queue_on_teleport)
          or  (KRNL_LOADED and queue_on_teleport)
    if f then pcall(f, code) end
end

-- ===== FPS BOOST =====
do
    g.Lighting.GlobalShadows = false
    g.Lighting.Brightness = 0
    g.Lighting.FogEnd = 1e10
    pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
    local function optimize(v)
        if v:IsA("BasePart") or v:IsA("MeshPart") then
            v.Material = Enum.Material.Plastic
            v.Reflectance = 0
            v.CastShadow  = false
            if v:IsA("MeshPart") then v.TextureID = "" end
            v.Transparency = 1
        elseif v:IsA("Decal") or v:IsA("Texture") then
            v.Transparency = 1
        elseif v:IsA("Explosion") then
            v.BlastPressure = 1; v.BlastRadius = 1
        elseif v:IsA("Fire") or v:IsA("SpotLight") or v:IsA("Smoke") or v:IsA("Sparkles") then
            v.Enabled = false
        elseif v:IsA("SpecialMesh") or v:IsA("SurfaceAppearance") or v:IsA("PostEffect") then
            pcall(function() v:Destroy() end)
        end
    end
    task.spawn(function()
        for _, v in ipairs(g:GetDescendants()) do optimize(v); task.wait(0.0005) end
    end)
    g.DescendantAdded:Connect(optimize)
end

-- ===== STATE =====
local strongholdTried, chestTried = {}, {}
local StrongholdCount, NormalChestCount = 0, 0

-- MinFreeSlots động
local DynamicMinFreeSlots = Config.MinFreeSlotsDefault
local MinFreeSlotsDecayAt = 0
local function getEffectiveMinFreeSlots()
    if MinFreeSlotsDecayAt > 0 and os.clock() > MinFreeSlotsDecayAt then
        DynamicMinFreeSlots = Config.MinFreeSlotsDefault
        MinFreeSlotsDecayAt = 0
    end
    return math.clamp(DynamicMinFreeSlots, Config.MinFreeSlotsDefault, Config.MinFreeSlotsCeil)
end

-- ===== VISITED / NO-REJOIN-SAME-SERVER =====
do
    getgenv().VisitedServers = getgenv().VisitedServers or { hour = -1, ids = {} }
end
local function nowHourUTC() return os.date("!*t").hour end
local function rotateVisitedIfHourChanged()
    local h = nowHourUTC()
    if getgenv().VisitedServers.hour ~= h then
        getgenv().VisitedServers.hour = h
        getgenv().VisitedServers.ids  = {}
    end
end
local function wasVisited(sid)
    rotateVisitedIfHourChanged()
    return getgenv().VisitedServers.ids[sid] == true
end
local function markVisited(sid)
    rotateVisitedIfHourChanged()
    getgenv().VisitedServers.ids[sid] = true
end

task.delay(2, function()
    pcall(function()
        if g.JobId and g.JobId ~= "" then markVisited(g.JobId) end
    end)
end)

queue_on_teleport_compat([[
    task.wait(1)
    pcall(function()
        getgenv().VisitedServers = getgenv().VisitedServers or { hour = -1, ids = {} }
        local h = os.date("!*t").hour
        if getgenv().VisitedServers.hour ~= h then
            getgenv().VisitedServers.hour = h
            getgenv().VisitedServers.ids  = {}
        end
        if game.JobId and game.JobId ~= "" then
            getgenv().VisitedServers.ids[game.JobId] = true
        end
    end)
]])

-- ===== GRACE WINDOWS & HOP GUARDS =====
local JoinedFarmAt = 0
local FirstDiamondAt = 0
local function inJoinGrace() return (JoinedFarmAt > 0) and ((os.clock() - JoinedFarmAt) < Config.JoinGraceSeconds) end
local function inFirstDiamondGrace() return (FirstDiamondAt > 0) and ((os.clock() - FirstDiamondAt) < Config.FirstDiamondGrace) end

local HopLock = false
local LastHopAt = 0
local function canHopNow()
    if HopLock then return false end
    if (os.clock() - LastHopAt) < Config.HopCooldownMin then return false end
    return true
end
local function setHopStamp()
    LastHopAt = os.clock()
end

-- ===== Teleport wrapper (Async-first; fallback) =====
local function tp_to_instance(placeId, serverId)
    local ok, err = pcall(function()
        local TeleportOptions = Instance.new("TeleportOptions")
        TeleportOptions.ServerInstanceId = serverId
        TeleportService:TeleportAsync(placeId, { LocalPlayer }, TeleportOptions)
    end)
    if ok then return true end
    local ok2, err2 = pcall(function()
        TeleportService:TeleportToPlaceInstance(placeId, serverId, LocalPlayer)
    end)
    if ok2 then return true end
    warn("[TP] Async fail:", err, " | Fallback fail:", err2)
    return false, tostring(err2 or err)
end

-- ===== HOP CORE (Generic fetch) =====
local ConsecutiveHopFail, LastHopFailAt = 0, 0
local BadIDs = {}
local LastAttemptSID = nil
local isTeleporting = false
local HopRequested  = false

-- Chặn prompt "Teleport Failed"
local function hookTeleportErrorPrompt()
    local function watchNode(v)
        if v.Name=="ErrorPrompt" then
            local function hideIfTF()
                if v.Visible
                   and v:FindFirstChild("TitleFrame")
                   and v.TitleFrame:FindFirstChild("ErrorTitle")
                   and v.TitleFrame.ErrorTitle.Text=="Teleport Failed" then
                    v.Visible=false
                end
            end
            hideIfTF()
            v:GetPropertyChangedSignal("Visible"):Connect(hideIfTF)
        end
    end
    pcall(function()
        local overlay = game.CoreGui:WaitForChild("RobloxPromptGui",5)
        overlay = overlay and overlay:FindFirstChild("promptOverlay")
        if overlay then
            for _,v in pairs(overlay:GetChildren()) do watchNode(v) end
            overlay.ChildAdded:Connect(watchNode)
        end
    end)
end
hookTeleportErrorPrompt()

-- Lọc region
local function regionMatch(entry)
    if not Config.RegionFilterEnabled then return true end
    local raw = tostring(entry.region or entry.ping or ""):lower()
    for _, key in ipairs(Config.RegionList) do
        if raw:find(tostring(key):lower(), 1, true) then return true end
    end
    return false
end

-- Tải trang server (chung, cho cả FARM & LOBBY)
local function fetchServerList(placeId, cursor, sort)
    placeId = tostring(placeId)
    local sortOrder = sort or "Asc"
    local base = ("https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=%s&excludeFullGames=true&limit=100")
                 :format(placeId, sortOrder)
    local url  = (cursor and cursor ~= "") and (base .. "&cursor="..cursor) or base
    url = url .. "&_t=" .. HttpService:GenerateGUID(false)
    local body = http_get(url)
    if not body then return nil end
    local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
    if ok and data and data.data then return data end
    return nil
end

-- Chọn phòng & Teleport (FARM)
local function chooseAndTeleportFromPageFarm(siteData, mode)
    if not siteData or not siteData.data then return false end
    local needFree = getEffectiveMinFreeSlots()
    local serverList = {}

    for _, v in pairs(siteData.data) do
        local id = tostring(v.id)
        local maxp = tonumber(v.maxPlayers or v.maxPlayerCount or 0) or 0
        local playing = tonumber(v.playing or v.playerCount or 0) or 0
        local free = maxp - playing
        if maxp > 0
           and free >= needFree
           and id ~= g.JobId
           and not wasVisited(id)
           and not BadIDs[id]
           and regionMatch(v) then
            table.insert(serverList, { id=id, players=playing, free=free, ping=tonumber(v.ping or 9999) })
        end
    end

    if mode == "Low" then
        table.sort(serverList, function(a,b)
            if a.free ~= b.free then return a.free > b.free end
            return a.players < b.players
        end)
    else
        table.sort(serverList, function(a,b)
            if a.players ~= b.players then return a.players > b.players end
            return a.free > b.free
        end)
        local filtered = {}
        for _, s in ipairs(serverList) do
            if s.players >= 5 then table.insert(filtered, s) end
        end
        if #filtered > 0 then serverList = filtered end
    end

    if #serverList == 0 then return false end
    if #serverList >= 3 then
        local i = math.random(1, math.min(3, #serverList))
        serverList[1], serverList[i] = serverList[i], serverList[1]
    end

    local chosen = serverList[1]
    if not chosen then return false end

    isTeleporting  = true
    LastAttemptSID = chosen.id
    setHopStamp()

    task.wait(rand(Config.HopBackoffMin, Config.HopBackoffMax))
    local ok = tp_to_instance(Config.FarmPlaceId, chosen.id)
    if not ok then
        isTeleporting = false
        BadIDs[chosen.id] = true
        ConsecutiveHopFail = ConsecutiveHopFail + 1
        LastHopFailAt = os.clock()
        return false
    else
        ConsecutiveHopFail = 0
        return true
    end
end

-- Chọn phòng & Teleport (LOBBY) – ưu tiên server đông người để có cơ hội có người create
local function chooseAndTeleportFromPageLobby(placeId, siteData)
    if not siteData or not siteData.data then return false end
    local needFree = getEffectiveMinFreeSlots()
    local serverList = {}

    for _, v in pairs(siteData.data) do
        local id = tostring(v.id)
        local maxp = tonumber(v.maxPlayers or v.maxPlayerCount or 0) or 0
        local playing = tonumber(v.playing or v.playerCount or 0) or 0
        local free = maxp - playing
        if maxp > 0
           and free >= needFree
           and id ~= g.JobId
           and not wasVisited(id)
           and not BadIDs[id]
           and regionMatch(v) then
            table.insert(serverList, { id=id, players=playing, free=free, ping=tonumber(v.ping or 9999) })
        end
    end

    table.sort(serverList, function(a,b)
        if Config.LobbyPreferHighPlayers then
            if a.players ~= b.players then return a.players > b.players end
            return a.free > b.free
        else
            if a.free ~= b.free then return a.free > b.free end
            return a.players < b.players
        end
    end)

    if #serverList == 0 then return false end
    local chosen = serverList[1]
    if not chosen then return false end

    isTeleporting  = true
    LastAttemptSID = chosen.id
    setHopStamp()

    task.wait(rand(Config.HopBackoffMin, Config.HopBackoffMax))
    local ok = tp_to_instance(placeId, chosen.id)
    if not ok then
        isTeleporting = false
        BadIDs[chosen.id] = true
        ConsecutiveHopFail = ConsecutiveHopFail + 1
        LastHopFailAt = os.clock()
        return false
    else
        ConsecutiveHopFail = 0
        return true
    end
end

-- Hop FARM
local function HopClassic(mode, reason)
    if isTeleporting or HopLock then return end
    mode = mode or Config.ClassicMode

    -- Guard lobby: không hop FARM nếu chưa ở map farm
    if g.PlaceId ~= Config.FarmPlaceId then return end

    -- Grace windows: tránh hop quá sớm trừ lý do “an toàn”
    local bypass = false
    if reason == "after-collect" or reason == "anti-dead" or reason == "retry" or reason == "locked" then
        bypass = true
    end
    if not bypass then
        if inJoinGrace() or inFirstDiamondGrace() then
            return
        end
    end

    -- cooldown khi fail liên tiếp
    if ConsecutiveHopFail >= Config.MaxConsecutiveHopFail then
        local since = os.clock() - LastHopFailAt
        if since < Config.ConsecutiveHopCooloff then
            task.wait(Config.ConsecutiveHopCooloff - since)
        end
        ConsecutiveHopFail = 0
    end

    if not canHopNow() then return end
    HopLock = true

    -- Primary pass
    local cursor, sort = "", "Asc"
    for _=1, Config.MaxPagesPrimary do
        local site = fetchServerList(Config.FarmPlaceId, cursor, sort)
        if not site then break end
        if chooseAndTeleportFromPageFarm(site, mode) then HopLock = false return end
        cursor = site.nextPageCursor or ""
        if not cursor or cursor == "" then break end
    end

    -- Fallback: đổi chiều
    cursor, sort = "", (mode == "Low" and "Desc" or "Asc")
    for _=1, Config.MaxPagesFallback do
        local site = fetchServerList(Config.FarmPlaceId, cursor, sort)
        if not site then break end
        if chooseAndTeleportFromPageFarm(site, mode) then HopLock = false return end
        cursor = site.nextPageCursor or ""
        if not cursor or cursor == "" then break end
    end

    HopLock = false
    task.wait(1 + math.random())
end

-- Hop LOBBY để TÌM CREATE
local function HopLobbyFindCreate(reason)
    if isTeleporting or HopLock then return end
    if g.PlaceId == Config.FarmPlaceId then return end -- chỉ dùng ở lobby
    if not canHopNow() then return end
    HopLock = true

    local cursor, sort = "", "Desc" -- ưu tiên đông người trước
    for _=1, math.max(Config.MaxPagesPrimary, 4) do
        local site = fetchServerList(g.PlaceId, cursor, sort)
        if not site then break end
        if chooseAndTeleportFromPageLobby(g.PlaceId, site) then HopLock = false return end
        cursor = site.nextPageCursor or ""
        if not cursor or cursor == "" then break end
    end

    -- fallback hướng ngược lại
    cursor, sort = "", "Asc"
    for _=1, math.max(Config.MaxPagesFallback, 6) do
        local site = fetchServerList(g.PlaceId, cursor, sort)
        if not site then break end
        if chooseAndTeleportFromPageLobby(g.PlaceId, site) then HopLock = false return end
        cursor = site.nextPageCursor or ""
        if not cursor or cursor == "" then break end
    end

    HopLock = false
end

-- PUBLIC APIS
local function Hop(reason_or_mode)
    local mode = (reason_or_mode == "High") and "High" or Config.ClassicMode
    local reason = (reason_or_mode == "High" or reason_or_mode == "Low" or reason_or_mode == nil) and "manual" or tostring(reason_or_mode)
    HopClassic(mode, reason)
end

local function HopFast(reason)
    if isTeleporting or HopRequested then return end
    if _G and _G.PauseHop then
        local t0 = os.clock()
        while _G.PauseHop and os.clock()-t0 < 10 do task.wait(0.25) end
    end
    HopRequested = true
    task.spawn(function()
        task.wait(Config.HopPostDelay)
        if not isTeleporting then
            pcall(function() _G._force_hop = true end)
            local why = (reason and tostring(reason):find("locked")) and "locked" or "after-collect"
            HopClassic(Config.ClassicMode, why)
        end
        HopRequested = false
    end)
end

-- Mark visited khi teleport bắt đầu & reset cờ
LocalPlayer.OnTeleport:Connect(function(state)
    if state == Enum.TeleportState.Started then
        if LastAttemptSID then markVisited(LastAttemptSID) end
        isTeleporting = false
        HopLock = false
        setHopStamp()
    end
end)

g.Loaded:Connect(function()
    task.delay(1.0, function()
        if g.PlaceId == Config.FarmPlaceId then
            JoinedFarmAt = os.clock()
            FirstDiamondAt = 0
        end
    end)
end)

TeleportService.TeleportInitFailed:Connect(function(_, result, msg)
    local rstr = tostring(result)
    warn("[Hop] TeleportInitFailed:", rstr, msg or "")

    -- Server full → nâng yêu cầu slot tạm (60s)
    if rstr:find("GameFull") or (type(msg)=="string" and msg:lower():find("requested experience is full")) then
        DynamicMinFreeSlots = math.min((DynamicMinFreeSlots or 1) + 1, Config.MinFreeSlotsCeil)
        MinFreeSlotsDecayAt = os.clock() + 60
    end
    -- Unauthorized / RequestRejected → bỏ JobId hiện tại
    if LastAttemptSID then BadIDs[LastAttemptSID] = true end

    isTeleporting = false
    HopLock = false
    ConsecutiveHopFail = ConsecutiveHopFail + 1
    LastHopFailAt = os.clock()
    task.delay(0.25, function()
        if g.PlaceId == Config.FarmPlaceId then
            HopClassic(Config.ClassicMode, "retry")
        else
            HopLobbyFindCreate("retry")
        end
    end)
end)

-- ===== NOCLIP =====
getgenv().NoClip = true
RunService.Stepped:Connect(function()
    local c = LocalPlayer.Character
    if not c then return end
    local on = getgenv().NoClip
    for _, v in ipairs(c:GetDescendants()) do
        if v:IsA("BasePart") then v.CanCollide = not on end
    end
end)

-- ===== MOVE =====
local function tpCFrame(cf)
    local r = HRP()
    if r then r.CFrame = cf end
end

-- ===== DIAMOND HELPERS =====
local function diamondsLeft()
    local items = workspace:FindFirstChild("Items")
    if not items then return false end
    for _, v in ipairs(items:GetChildren()) do
        if v.Name == "Diamond" then return true end
    end
    return false
end

local function waitNoDiamonds(timeout)
    local t0 = os.clock()
    local limit = timeout or 1.2
    while (os.clock() - t0) < limit do
        if not diamondsLeft() then return true end
        task.wait(0.1)
    end
    return not diamondsLeft()
end

local function collectAllDiamonds()
    local n = 0
    local items = workspace:FindFirstChild("Items")
    if not items then return 0 end
    for _, v in ipairs(items:GetChildren()) do
        if v.Name == "Diamond" then
            pcall(function()
                local ev = RS:FindFirstChild("RemoteEvents")
                local re = ev and ev:FindFirstChild("RequestTakeDiamonds")
                if re and re.FireServer then
                    re:FireServer(v)
                    n = n + 1
                end
            end)
        end
    end
    if n > 0 and FirstDiamondAt == 0 then
        FirstDiamondAt = os.clock()
    end
    return n
end

-- ===== CHEST FILTER: CHỈ CHO PHÉP 1 & 5 GEMS =====
local function arrayContains(arr, val)
    for _, x in ipairs(arr) do if tonumber(x) == tonumber(val) then return true end end
    return false
end

local function parseIntFromText(s)
    if type(s) ~= "string" then return nil end
    local num = s:match("(%-?%d+)")
    if num then return tonumber(num) end
    return nil
end

local function detectChestGemValueByChildren(chest)
    -- tìm NumberValue/IntValue/GemValue
    for _, d in ipairs(chest:GetDescendants()) do
        if d.Name:lower():find("gem") and (d:IsA("NumberValue") or d:IsA("IntValue") or d:IsA("StringValue")) then
            local v = d.Value
            if type(v) == "string" then v = parseIntFromText(v) end
            if type(v) == "number" then return v end
        end
        if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text and d.Text ~= "" then
            local v = parseIntFromText(d.Text)
            if v then return v end
        end
    end
    return nil
end

local function detectChestGemValue(chest)
    -- 1) Attribute
    local v = chest:GetAttribute("GemValue")
    if v == nil and chest:FindFirstChild("Main") then
        v = chest.Main:GetAttribute("GemValue")
    end
    if type(v) == "string" then v = parseIntFromText(v) end
    if type(v) == "number" then return v end

    -- 2) Child values / labels
    v = detectChestGemValueByChildren(chest)
    if type(v) == "number" then return v end

    -- 3) Name heuristics: "Chest5", "Chest_1", "1Gem", "5 Gems"
    local name = tostring(chest.Name or ""):lower()
    local nm = name:match("chest[%-_ ]?(%d+)") or name:match("(%d+)[%s%-_]*gem")
    if nm then return tonumber(nm) end

    return nil
end

local function isAllowedChest(chest)
    local v = detectChestGemValue(chest)
    if v and arrayContains(Config.AllowedChestGemValues, v) then
        return true
    end
    -- nếu không dò được giá trị, coi như KHÔNG mở để tránh mở nhầm
    return false
end

-- ===== FINDERS / PROMPTS =====
local function findStrongholdChest()
    local items = workspace:FindFirstChild("Items")
    if not items then return nil end
    return items:FindFirstChild(Config.StrongholdChestName)
end

local function findProximityPromptInChest(chest)
    local main = chest and chest:FindFirstChild("Main")
    if not main then return nil end
    local attach = main:FindFirstChild("ProximityAttachment")
    if not attach then return nil end
    return attach:FindFirstChild("ProximityInteraction")
end

local function findUsableChestAllowed()
    local r = HRP(); if not r then return nil end
    local closest, dist
    local items = workspace:FindFirstChild("Items"); if not items then return nil end
    for _, v in ipairs(items:GetChildren()) do
        if v:IsA("Model") and v.Name:find("Chest") and not v.Name:find("Snow") then
            local id = v:GetDebugId()
            if not chestTried[id] then
                local prox = v:FindFirstChildWhichIsA("ProximityPrompt", true)
                if prox and prox.Enabled and isAllowedChest(v) then
                    local pv = v:GetPivot()
                    local d = (r.Position - pv.Position).Magnitude
                    if not dist or d < dist then closest, dist = v, d end
                end
            end
        end
    end
    return closest
end

local function firePromptSafe(prompt)
    if typeof(fireproximityprompt) == "function" then
        pcall(function() fireproximityprompt(prompt, 1) end)
    else
        pcall(function()
            local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            if hum and prompt and prompt.HoldDuration == 0 then
                hum:MoveTo(prompt.Parent and prompt.Parent.Position or (HRP() and HRP().Position))
            end
        end)
    end
end

local function pressPromptWithTimeout(prompt, timeout)
    local t0 = os.clock()
    local limit = timeout or 6
    while prompt and prompt.Parent and prompt.Enabled and (os.clock()-t0) < limit do
        firePromptSafe(prompt)
        task.wait(0.3)
    end
    return not (prompt and prompt.Parent and prompt.Enabled)
end

local function waitDiamonds(timeout)
    local t0 = os.clock()
    local limit = timeout or 2.0
    while (os.clock()-t0) < limit do
        local items = workspace:FindFirstChild("Items")
        if items and items:FindFirstChild("Diamond") then return true end
        task.wait(0.2)
    end
    return false
end

-- ============ AUTO JOIN / CREATE (Lobby-only) — FIXED ============
-- Tìm các Teleporter trong lobby: đọc text "x/y" và nhảy vào teleporter có người đang create
local TeleporterNames = { "Teleporter1", "Teleporter2", "Teleporter3" }

local function parseXY(txt)
    if type(txt) ~= "string" then return nil, nil end
    -- hỗ trợ "3/4" hoặc "Players: 3/4"
    local a,b = txt:match("(%d+)%s*/%s*(%d+)")
    if a and b then return tonumber(a), tonumber(b) end
    a,b = txt:match("[Pp]layers%s*:%s*(%d+)%s*/%s*(%d+)")
    if a and b then return tonumber(a), tonumber(b) end
    return nil, nil
end

local function getTeleporterPlayerCount(tpModel)
    local holder = tpModel:FindFirstChild("BillboardHolder")
    local board  = holder and holder:FindFirstChild("BillboardGui")
    -- một số map đổi tên "Players" -> "PlayerCount" hoặc gộp vào TextLabel
    local label  = board and (board:FindFirstChild("Players") or board:FindFirstChild("PlayerCount") or board:FindFirstChildWhichIsA("TextLabel"))
    if label and label:IsA("TextLabel") and label.Text and #label.Text>0 then
        local x,y = parseXY(label.Text)
        if x and y then return x,y end
    end
    return 0, 0
end

local function scanLobbyTeleporterAndJoin()
    local joined = false
    local foundCreate = false

    for _, name in ipairs(TeleporterNames) do
        local obj = workspace:FindFirstChild(name)
        if obj and obj:IsA("Model") then
            local x,y = getTeleporterPlayerCount(obj)
            if x and y and x >= Config.MinPlayersOnCreate and x < y then
                foundCreate = true
            end
        end
    end

    if foundCreate then
        -- ưu tiên teleporter có nhiều người nhất
        local bestTP, bestX, bestY = nil, -1, -1
        for _, name in ipairs(TeleporterNames) do
            local obj = workspace:FindFirstChild(name)
            if obj and obj:IsA("Model") then
                local x,y = getTeleporterPlayerCount(obj)
                if x and y and x >= Config.MinPlayersOnCreate and x < y then
                    if x > bestX then bestTP, bestX, bestY = obj, x, y end
                end
            end
        end
        if bestTP then
            local enter = bestTP:FindFirstChildWhichIsA("BasePart")
            if enter and HRP() then
                _G.PauseHop = true -- tạm khóa hop để khỏi nhảy lobby khi đang join
                tpCFrame(enter.CFrame + Vector3.new(0, 3, 0))
                joined = true
                -- mở khóa lại sau 6 giây nếu chưa teleport (an toàn)
                task.delay(6, function() _G.PauseHop = false end)
            end
        end
    else
        -- không thấy ai create → đứng vào bất kỳ teleporter (tự create) nhưng không bắt buộc
        local any = nil
        for _, name in ipairs(TeleporterNames) do
            local obj = workspace:FindFirstChild(name)
            if obj and obj:IsA("Model") then any = obj break end
        end
        if any then
            local enter = any:FindFirstChildWhichIsA("BasePart")
            if enter and HRP() then
                tpCFrame(enter.CFrame + Vector3.new(0, 3, 0))
            end
        end
    end

    return joined, foundCreate
end

-- Vòng lặp lobby: nếu KHÔNG có ai create trong ~LobbyScanTimeout giây -> hop lobby khác để tìm
task.spawn(function()
    local lastScanStart = 0
    local waitingOnThisLobby = false
    while task.wait(Config.LobbyCheckInterval) do
        if g.PlaceId ~= Config.FarmPlaceId then
            if not waitingOnThisLobby then
                lastScanStart = os.clock()
                waitingOnThisLobby = true
            end

            local ok, joined, found = pcall(scanLobbyTeleporterAndJoin)
            if not ok then
                joined, found = false, false
            end

            -- nếu đã join vào create, nhường thời gian cho teleport diễn ra, không hop
            if joined then
                -- reset đồng hồ để không bị hop sớm
                lastScanStart = os.clock()
            end

            -- quá thời gian chờ mà vẫn không có ai create → hop lobby khác để săn
            if os.clock() - lastScanStart >= Config.LobbyScanTimeout then
                if not found then
                    HopLobbyFindCreate("find-create")
                end
                lastScanStart = os.clock()
            end
        else
            waitingOnThisLobby = false
        end
    end
end)
-- ================== END LOBBY FIX ==================

-- ===== ANTI-DEAD =====
local IsDead, DeadSince = false, 0

local function hasDeadUi()
    local pg = LocalPlayer:FindFirstChild("PlayerGui"); if not pg then return false end
    local lower = string.lower
    for _, gui in ipairs(pg:GetDescendants()) do
        if gui:IsA("TextLabel") or gui:IsA("TextButton") then
            local t = tostring(gui.Text or ""):gsub("%s+", " ")
            for _, k in ipairs(Config.DeadUiKeywords) do
                if lower(t):find(lower(k), 1, true) then return true end
            end
        end
    end
    return false
end

local function bindDeathWatcher(char)
    local hum = char:FindFirstChild("Humanoid")
    if not hum then return end
    hum.Died:Connect(function()
        IsDead = true
        DeadSince = os.clock()
    end)
end

if LocalPlayer.Character then bindDeathWatcher(LocalPlayer.Character) end
LocalPlayer.CharacterAdded:Connect(function(c)
    IsDead = false
    DeadSince = 0
    task.wait(0.5)
    bindDeathWatcher(c)
    if g.PlaceId == Config.FarmPlaceId then
        JoinedFarmAt = os.clock()
        FirstDiamondAt = 0
    end
end)

task.spawn(function()
    while task.wait(0.5) do
        if g.PlaceId == Config.FarmPlaceId then
            if (IsDead or hasDeadUi()) then
                if DeadSince == 0 then DeadSince = os.clock() end
                if (os.clock() - DeadSince) >= Config.DeadHopTimeout then
                    HopFast("anti-dead")
                end
            end
        end
    end
end)

-- ===== MAIN FARM =====
task.spawn(function()
    while task.wait(Config.FarmTick) do
        if g.PlaceId == Config.FarmPlaceId then
            WaitForChar()

            -- 1) Stronghold (KHÔNG mở được -> Hop ngay)
            local sh = findStrongholdChest()
            if sh then
                local sid = sh:GetDebugId()
                if not strongholdTried[sid] then
                    local prox = findProximityPromptInChest(sh)
                    if prox and prox.Enabled then
                        tpCFrame(CFrame.new(sh:GetPivot().Position + Vector3.new(0,3,0)))

                        local opened = pressPromptWithTimeout(prox, Config.StrongholdPromptTime)
                        prox = findProximityPromptInChest(sh)

                        if not opened and (prox and prox.Parent and prox.Enabled) then
                            strongholdTried[sid] = true
                            HopFast("stronghold-locked")
                        else
                            if waitDiamonds(Config.StrongholdDiamondWait) then
                                collectAllDiamonds()
                                waitNoDiamonds(1.1)
                                StrongholdCount = StrongholdCount + 1
                                if Config.HopAfterStronghold then
                                    HopFast("after-stronghold-collect")
                                end
                            else
                                strongholdTried[sid] = true
                                HopFast("stronghold-no-diamonds")
                            end
                        end
                    else
                        strongholdTried[sid] = true
                    end
                end
            end

            -- 2) Chest thường (CHỈ 1 & 5 gems; KHÔNG mở full)
            local chest = findUsableChestAllowed()
            if not chest then
                -- Chỉ hop nếu không bị khoá, không đang teleport và đã qua grace
                if not isTeleporting and not HopLock and not inJoinGrace() and not inFirstDiamondGrace() then
                    Hop("manual")
                end
            else
                local id   = chest:GetDebugId()
                local prox = chest:FindFirstChildWhichIsA("ProximityPrompt", true)
                local t0   = os.clock()
                local okOpen = false

                while prox and prox.Parent and prox.Enabled and (os.clock() - t0) < 10 do
                    tpCFrame(CFrame.new(chest:GetPivot().Position))
                    firePromptSafe(prox)
                    task.wait(0.45)
                    prox = chest:FindFirstChildWhichIsA("ProximityPrompt", true)
                end

                if not (prox and prox.Parent and prox.Enabled) then
                    okOpen = true
                end

                if okOpen then
                    NormalChestCount = NormalChestCount + 1
                    collectAllDiamonds()
                    waitNoDiamonds(1.0)
                    if Config.HopAfterNormalChest then
                        HopFast("after-normalchest-collect")
                    end
                else
                    chestTried[id] = true
                    HopFast("chest-locked")
                end
            end
        end
    end
end)

-- 3) Diamonds song song (nhẹ, không spam)
task.spawn(function()
    while task.wait(Config.DiamondTick) do
        if g.PlaceId == Config.FarmPlaceId then
            collectAllDiamonds()
        end
    end
end)

-- ===== OPTIONAL OVERLAY (đếm diamond GUI) =====
task.spawn(function()
    local a = Instance.new("ScreenGui")
    a.Name = "gg"
    a.ResetOnSpawn = false
    a.IgnoreGuiInset = true
    a.Parent = game:GetService("CoreGui")

    local b = Instance.new("Frame", a)
    b.Size = UDim2.new(1, 0, 1, 0)
    b.BackgroundTransparency = 1
    b.BorderSizePixel = 0

    local d = Instance.new("UIStroke", b); d.Thickness = 2
    local function rainbowStroke(stroke)
        task.spawn(function()
            while task.wait() do
                for i = 0, 1, 0.02 do
                    stroke.Color = Color3.fromHSV(i, 1, 1)
                    task.wait(0.03)
                end
            end
        end)
    end
    rainbowStroke(d)

    local e = Instance.new("TextLabel", b)
    e.Size = UDim2.new(1, 0, 1, 0)
    e.BackgroundTransparency = 1
    e.Text = "0"
    e.TextColor3 = Color3.fromRGB(255, 255, 255)
    e.Font = Enum.Font.GothamBold
    e.TextScaled = true
    e.TextStrokeTransparency = 0.6

    while task.wait(0.2) do
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        if pg and pg:FindFirstChild("Interface")
               and pg.Interface:FindFirstChild("DiamondCount")
               and pg.Interface.DiamondCount:FindFirstChild("Count") then
            local lab = pg.Interface.DiamondCount.Count
            if lab and lab:IsA("TextLabel") then
                e.Text = lab.Text
            end
        end
    end
end)
