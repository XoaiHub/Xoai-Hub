-- ================================================================
-- Mochi Farm (Luarmor-ready & Emulator-stable, no UI)
-- + Fast Hop After Collect
-- + Anti-DEAD (đa lớp) + Skip Server Full + Failover
-- + No-Repeat Server Hop (persistent recent history via TeleportData)
-- ================================================================

-- ===== CONFIG =====
local Config = {
    RegionFilterEnabled   = false,
    RegionList            = { "singapore", "tokyo", "us-east" },
    RetryHttpDelay        = 2,

    StrongholdChestName   = "Stronghold Diamond Chest",
    StrongholdPromptTime  = 6,
    StrongholdDiamondWait = 10,

    FarmPlaceId           = 126509999114328, -- map farm
    LobbyCheckInterval    = 2.0,
    FarmTick              = 1.0,
    DiamondTick           = 0.35,
    HopBackoffMin         = 1.5,
    HopBackoffMax         = 3.0,

    HopAfterStronghold    = true,
    HopAfterNormalChest   = true,
    HopPostDelay          = 0.20,

    -- Anti-DEAD
    DeadHopTimeout        = 6.0,   -- đứng DEAD quá thời gian này -> hop
    DeadUiKeywords        = { "dead", "you died", "respawn", "revive" },

    -- No-Repeat Hop
    VisitedTTLSeconds     = 20*60, -- 20 phút
    VisitedMaxCount       = 60,    -- lưu tối đa 60 server gần nhất
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
        t += 0.25
        task.wait(0.25)
    end
    return LocalPlayer.Character
end

local function HRP()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function rand(a,b) return a + (b-a)*math.random() end

-- ===== queue_on_teleport (nạp lại loader nếu cần) =====
local function queue_on_teleport_compat(code)
    local f = (syn and syn.queue_on_teleport)
          or  queue_on_teleport
          or  (fluxus and fluxus.queue_on_teleport)
          or  (KRNL_LOADED and queue_on_teleport)
    if f then pcall(f, code) end
end
-- ví dụ: queue_on_teleport_compat([[loadstring(game:HttpGet("https://yourdomain.com/Init.lua"))()]])

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
        elseif v:IsA("Fire") or v:IsA("SpotLight") or v:IsA("Smoke") or v:IsA("Sparkles") then
            v.Enabled = false
        elseif v:IsA("SpecialMesh") or v:IsA("SurfaceAppearance") then
            pcall(function() v:Destroy() end)
        end
    end
    task.spawn(function()
        for _, v in ipairs(g:GetDescendants()) do optimize(v); task.wait(0.0005) end
    end)
    g.DescendantAdded:Connect(optimize)
end

-- ===== STATE =====
local PlaceID = Config.FarmPlaceId

local AllIDs, cursor, isTeleporting = {}, "", false
local strongholdTried, chestTried = {}, {}
local StrongholdCount, NormalChestCount = 0, 0

local BadIDs = {}
local LastAttemptSID = nil

local function resetState()
    AllIDs, cursor, isTeleporting = {}, "", false
    strongholdTried, chestTried = {}, {}
    LastAttemptSID = nil
end

-- ====== RECENT SERVER HISTORY (PERSISTENT) ======
-- Bảng lưu jobId -> timestamp
local RecentSIDs = getgenv().Mochi_RecentSIDs
if type(RecentSIDs) ~= "table" then RecentSIDs = {} end

-- Hợp nhất TeleportData.recent (nếu có) để mang lịch sử qua hop
pcall(function()
    local jd = Players.LocalPlayer:GetJoinData()
    if jd and jd.TeleportData and type(jd.TeleportData.recent) == "table" then
        for sid, ts in pairs(jd.TeleportData.recent) do
            if type(sid) == "string" and type(ts) == "number" then
                RecentSIDs[sid] = ts
            end
        end
    end
end)

-- Lưu ngược về getgenv() để chia sẻ giữa script
getgenv().Mochi_RecentSIDs = RecentSIDs

local function pruneRecent()
    local now = os.time()
    -- loại theo TTL
    for sid, ts in pairs(RecentSIDs) do
        if now - ts > Config.VisitedTTLSeconds then
            RecentSIDs[sid] = nil
        end
    end
    -- giới hạn số lượng
    local cnt = 0
    for _ in pairs(RecentSIDs) do cnt += 1 end
    if cnt > Config.VisitedMaxCount then
        -- cắt bỏ các entry cũ nhất
        local arr = {}
        for sid, ts in pairs(RecentSIDs) do table.insert(arr, {sid, ts}) end
        table.sort(arr, function(a,b) return a[2] < b[2] end)
        for i = 1, (cnt - Config.VisitedMaxCount) do
            local sid = arr[i][1]
            RecentSIDs[sid] = nil
        end
    end
end

local function markRecent(sid)
    RecentSIDs[sid] = os.time()
    pruneRecent()
end

local function isRecent(sid)
    local ts = RecentSIDs[sid]
    if not ts then return false end
    if os.time() - ts > Config.VisitedTTLSeconds then
        RecentSIDs[sid] = nil
        return false
    end
    return true
end

-- ===== DIAMOND HELPERS =====
local function diamondsLeft()
    for _, v in ipairs(workspace:GetDescendants()) do
        if v.ClassName == "Model" and v.Name == "Diamond" then return true end
    end
    return false
end
local function waitNoDiamonds(timeout)
    local t0 = tick()
    while tick() - t0 < (timeout or 1.2) do
        if not diamondsLeft() then return true end
        task.wait(0.1)
    end
    return not diamondsLeft()
end
local function collectAllDiamonds()
    local n = 0
    for _, v in ipairs(workspace:GetDescendants()) do
        if v.ClassName == "Model" and v.Name == "Diamond" then
            pcall(function() RS.RemoteEvents.RequestTakeDiamonds:FireServer(v) end)
            n += 1
        end
    end
    return n
end

-- ===== FAST HOP =====
local HopRequested = false
local lastSortAsc  = false -- luân phiên Asc/Desc để đa dạng hoá danh sách

local function HopFallback()
    -- Fallback: chọn random server của PlaceID (có thể trùng; chỉ dùng khi bất khả kháng)
    pcall(function()
        TeleportService:Teleport(PlaceID, LocalPlayer)
    end)
end

local function Hop()
    if isTeleporting or HopRequested then return end
    HopRequested = true
    task.spawn(function()
        WaitForChar()

        local function fetchServerPage(nextCursor, sortOrder)
            local order = sortOrder or "Desc"
            local url = ("https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=%s&excludeFullGames=true&limit=100%s")
                :format(PlaceID, order, nextCursor ~= "" and ("&cursor="..nextCursor) or "")
            local ok, data = pcall(function() return HttpService:JSONDecode(game:HttpGet(url)) end)
            if not ok then task.wait(Config.RetryHttpDelay) return nil end
            return data
        end

        local function regionMatch(entry)
            if not Config.RegionFilterEnabled then return true end
            local raw = tostring(entry.region or ""):lower()
            for _, key in ipairs(Config.RegionList) do
                if raw:find(tostring(key):lower(), 1, true) then return true end
            end
            return false
        end

        pruneRecent()

        local triedPages = 0
        cursor = ""
        local order = lastSortAsc and "Asc" or "Desc"
        lastSortAsc = not lastSortAsc

        while triedPages < 8 and not isTeleporting do
            local page = fetchServerPage(cursor, order)
            if not page or not page.data then break end
            cursor = page.nextPageCursor or ""

            -- Duyệt danh sách và chọn server hợp lệ
            for _, v in ipairs(page.data) do
                local sid = tostring(v.id)
                local playing, maxp = tonumber(v.playing), tonumber(v.maxPlayers)

                -- Loại ngay server hiện tại, server đầy, server đã bad, server mới ghé gần đây, sai region
                local skip =
                    (sid == g.JobId) or
                    (BadIDs[sid] == true) or
                    (isRecent(sid) == true) or
                    (not regionMatch(v)) or
                    (not (playing and maxp and playing < maxp))

                if not skip then
                    -- Đánh dấu recent **trước** khi gọi teleport để hạn chế race khi fail
                    markRecent(sid)

                    local opts = Instance.new("TeleportOptions")
                    -- Mang lịch sử qua lần hop sau
                    local payload = { recent = RecentSIDs }
                    pcall(function() opts:SetTeleportData(payload) end)

                    isTeleporting = true
                    LastAttemptSID = sid

                    task.wait(rand(Config.HopBackoffMin, Config.HopBackoffMax))
                    local ok, err = pcall(function()
                        TeleportService:TeleportToPlaceInstance(PlaceID, sid, LocalPlayer, opts)
                    end)
                    if not ok then
                        -- Teleport lỗi: bỏ flag, đánh dấu bad để lần tới khỏi chọn lại
                        isTeleporting = false
                        BadIDs[sid] = true
                    else
                        HopRequested = false
                        return
                    end
                else
                    -- đánh dấu "bad" cho các server không hợp lệ vì đầy
                    if playing and maxp and playing >= maxp then
                        BadIDs[sid] = true
                    end
                end
            end

            triedPages += 1
            task.wait(rand(0.8, 1.6))
            if cursor == "" then break end
        end

        -- Nếu tới đây vẫn chưa hop được -> fallback random (có thể trùng)
        isTeleporting = true
        HopFallback()
        HopRequested = false
    end)
end

TeleportService.TeleportInitFailed:Connect(function(_, teleportResult, msg)
    warn("[Hop] TeleportInitFailed:", teleportResult, msg)
    if LastAttemptSID then BadIDs[LastAttemptSID] = true end
    isTeleporting = false
    HopRequested = false
    task.delay(0.5, function()
        HopFallback()
    end)
end)

Players.LocalPlayer.OnTeleport:Connect(function(state)
    if state == Enum.TeleportState.Started then resetState() end
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
local function tpCFrame(cf) local r = HRP(); if r then r.CFrame = cf end end

-- ===== FINDERS =====
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

local function findUsableChest()
    local r = HRP(); if not r then return nil end
    local closest, dist
    local items = workspace:FindFirstChild("Items"); if not items then return nil end
    for _, v in pairs(items:GetDescendants()) do
        if v:IsA("Model") and v.Name:find("Chest") and not v.Name:find("Snow") then
            local id = v:GetDebugId()
            if not chestTried[id] then
                local prox = v:FindFirstChildWhichIsA("ProximityPrompt", true)
                if prox and prox.Enabled then
                    local d = (r.Position - v:GetPivot().Position).Magnitude
                    if not dist or d < dist then closest, dist = v, d end
                end
            end
        end
    end
    return closest
end

-- ===== PROMPT HELPERS =====
local function pressPromptWithTimeout(prompt, timeout)
    local t0 = tick()
    while prompt and prompt.Parent and prompt.Enabled and (tick()-t0) < timeout do
        pcall(function() fireproximityprompt(prompt) end)
        task.wait(0.3)
    end
    return not (prompt and prompt.Parent and prompt.Enabled)
end

local function waitDiamonds(timeout)
    local t0 = tick()
    while (tick()-t0) < (timeout or 2.0) do
        if workspace:FindFirstChild("Diamond", true) then return true end
        task.wait(0.2)
    end
    return false
end

-- ===== AUTO JOIN / CREATE (Lobby) =====
local function autoJoinOrCreate()
    local joined = false
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("Model") and (obj.Name=="Teleporter1" or obj.Name=="Teleporter2" or obj.Name=="Teleporter3") then
            local gui  = obj:FindFirstChild("BillboardHolder")
            local board= gui and gui:FindFirstChild("BillboardGui")
            local lab  = board and board:FindFirstChild("Players")
            if lab and typeof(lab.Text) == "string" then
                local x, y = lab.Text:match("(%d+)/(%d+)")
                x, y = tonumber(x), tonumber(y)
                if x and y and x >= 2 and x < y then
                    local enter = obj:FindFirstChildWhichIsA("BasePart")
                    if enter and HRP() then
                        tpCFrame(enter.CFrame + Vector3.new(0, 3, 0))
                        joined = true
                        break
                    end
                end
            end
        end
    end
    if not joined then
        for _, obj in ipairs(workspace:GetChildren()) do
            if obj:IsA("Model") and (obj.Name=="Teleporter1" or obj.Name=="Teleporter2" or obj.Name=="Teleporter3") then
                local enter = obj:FindFirstChildWhichIsA("BasePart")
                if enter and HRP() then tpCFrame(enter.CFrame + Vector3.new(0, 3, 0)); break end
            end
        end
    end
end

task.spawn(function()
    while task.wait(Config.LobbyCheckInterval) do
        if g.PlaceId ~= Config.FarmPlaceId then pcall(autoJoinOrCreate) end
    end
end)

-- ===== ANTI-DEAD (đa lớp) =====
local IsDead = false
local DeadSince = 0

local function hasDeadUi()
    local pg = LocalPlayer:FindFirstChild("PlayerGui"); if not pg then return false end
    local lower = string.lower
    for _, gui in ipairs(pg:GetDescendants()) do
        if gui:IsA("TextLabel") or gui:IsA("TextButton") then
            local t = tostring(gui.Text or ""):gsub("%s+", " ")
            for _, k in ipairs(Config.DeadUiKeywords) do
                if lower(t):find(lower(k), 1, true) then return true end
            end
        elseif gui:IsA("Frame") or gui:IsA("ImageLabel") then
            local n = tostring(gui.Name or "")
            for _, k in ipairs(Config.DeadUiKeywords) do
                if lower(n):find(lower(k), 1, true) and gui.Visible ~= false then
                    return true
                end
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
        DeadSince = tick()
    end)
end

if LocalPlayer.Character then bindDeathWatcher(LocalPlayer.Character) end
LocalPlayer.CharacterAdded:Connect(function(c)
    IsDead = false
    DeadSince = 0
    task.wait(0.5)
    bindDeathWatcher(c)
end)

task.spawn(function()
    while task.wait(0.3) do
        local c = LocalPlayer.Character
        local hum = c and c:FindFirstChild("Humanoid")
        local uiDead = hasDeadUi()
        local hpDead = hum and (hum.Health <= 0)

        if (IsDead or uiDead or hpDead) then
            if DeadSince == 0 then DeadSince = tick() end
            if (tick() - DeadSince) >= Config.DeadHopTimeout then
                Hop()
            end
        else
            DeadSince = 0
        end
    end
end)

-- ===== MAIN FARM =====
task.spawn(function()
    while task.wait(Config.FarmTick) do
        if g.PlaceId ~= Config.FarmPlaceId then continue end
        WaitForChar()

        -- 1) Stronghold
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
                    else
                        if waitDiamonds(Config.StrongholdDiamondWait) then
                            collectAllDiamonds()
                            waitNoDiamonds(1.1)
                            StrongholdCount += 1
                            if Config.HopAfterStronghold then Hop() end
                        else
                            strongholdTried[sid] = true
                        end
                    end
                else
                    strongholdTried[sid] = true
                end
            end
        end

        -- 2) Chest thường
        local chest = findUsableChest()
        if not chest then
            Hop()
        else
            local id   = chest:GetDebugId()
            local prox = chest:FindFirstChildWhichIsA("ProximityPrompt", true)
            local t0   = os.clock()
            local okOpen = false
            while prox and prox.Parent and prox.Enabled and (os.clock() - t0) < 10 do
                tpCFrame(CFrame.new(chest:GetPivot().Position))
                pcall(function() fireproximityprompt(prox) end)
                task.wait(0.45)
                prox = chest:FindFirstChildWhichIsA("ProximityPrompt", true)
            end
            if not (prox and prox.Parent and prox.Enabled) then okOpen = true end
            if okOpen then
                NormalChestCount += 1
                collectAllDiamonds()
                waitNoDiamonds(1.0)
                if Config.HopAfterNormalChest then Hop() end
            else
                chestTried[id] = true
            end
        end
    end
end)

-- 3) Diamonds song song
task.spawn(function()
    while task.wait(Config.DiamondTick) do
        if g.PlaceId == Config.FarmPlaceId then collectAllDiamonds() end
    end
end)

