-- MM2 Farm (Lobby-safe): chỉ farm khi đã "ở trong map", lobby thì đứng yên.
-- Flow: Lobby (idle) -> Được map kéo vào -> Farm tới TargetCoins -> Hop server -> Lặp lại

-- ====== CONFIG ======
local Config = {
    IdleInLobby       = true,          -- đứng yên ở lobby
    IdleMethod        = "walkspeed",   -- "walkspeed" hoặc "anchor"
    IdleWalkSpeed     = 0,
    IdleJumpPower     = 0,
    RestoreWalkSpeed  = 16,
    RestoreJumpPower  = 50,

    TargetCoins       = 40,            -- đủ bao nhiêu coin thì hop
    SpeedFactor       = 35,            -- cao hơn -> nhanh hơn
    TweenMinTime      = 0.07,
    TweenMaxTime      = 2.0,
    CoinLockTime      = 2.0,           -- tối đa “dính” 1 coin
    DelayBetweenCoins = 0.12,          -- nghỉ nhỏ giữa các coin
    RoundPollDelay    = 0.25,
}

-- ====== Services ======
local g              = game
local Players        = g:GetService("Players")
local RS             = g:GetService("ReplicatedStorage")
local TweenService   = g:GetService("TweenService")
local TeleportService= g:GetService("TeleportService")
local HttpService    = g:GetService("HttpService")
local LP             = Players.LocalPlayer
local PlaceId        = g.PlaceId

-- ====== Character ======
local function getChar()
    local char = LP.Character or LP.CharacterAdded:Wait()
    local hrp  = char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart")
    local hum  = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid")
    return char, hrp, hum
end
local Char, HRP, Humanoid = getChar()
LP.CharacterAdded:Connect(function() Char, HRP, Humanoid = getChar() end)

-- ====== Idle control (lobby) ======
local function applyIdle(state)
    if not Humanoid or not HRP then return end
    if state then
        if Config.IdleMethod == "walkspeed" then
            Humanoid.WalkSpeed = Config.IdleWalkSpeed
            Humanoid.JumpPower = Config.IdleJumpPower
        else
            HRP.Anchored = true
        end
    else
        if Config.IdleMethod == "walkspeed" then
            Humanoid.WalkSpeed = Config.RestoreWalkSpeed
            Humanoid.JumpPower = Config.RestoreJumpPower
        else
            HRP.Anchored = false
        end
    end
end

-- ====== Round / Map detect ======
local function findActiveMap()
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:GetAttribute("MapID") and obj:FindFirstChild("CoinContainer") then
            return obj
        end
    end
end

local function getInRoundFlag()
    local ok, v = pcall(function()
        local gd = RS:FindFirstChild("GameData")
        local iv = gd and gd:FindFirstChild("InRound")
        return iv and iv.Value
    end)
    return ok and v or nil
end

local function isRoundLive()
    local flag = getInRoundFlag()
    if flag ~= nil then return flag end
    -- fallback nhẹ: có map đang active coi như live
    return findActiveMap() ~= nil
end

-- Kiểm tra người chơi có ĐANG Ở BÊN TRONG map không (dựa theo bounding box map)
local function isInsideMap(mapModel, margin)
    margin = margin or 10
    if not (mapModel and HRP) then return false end
    local cf, size = mapModel:GetBoundingBox()
    local rel = cf:PointToObjectSpace(HRP.Position)
    local half = size * 0.5
    return math.abs(rel.X) <= half.X + margin
       and math.abs(rel.Y) <= half.Y + margin
       and math.abs(rel.Z) <= half.Z + margin
end

-- Chờ tới khi: round đang chạy VÀ mình đã ở trong map (tránh tp xuyên từ lobby)
local function waitUntilActuallyInMap()
    if Config.IdleInLobby then applyIdle(true) end
    while true do
        local m = findActiveMap()
        if m and isRoundLive() and isInsideMap(m, 12) then
            if Config.IdleInLobby then applyIdle(false) end
            return m
        end
        task.wait(Config.RoundPollDelay)
    end
end

-- ====== Hop server ======
local function hopServer()
    local servers, cursor = {}, nil
    local base = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(PlaceId)
    while true do
        local res = game:HttpGet(base .. (cursor and "&cursor="..cursor or ""))
        local data = HttpService:JSONDecode(res)
        for _, s in ipairs(data.data) do
            if s.playing < s.maxPlayers and s.id ~= game.JobId then
                table.insert(servers, s.id)
            end
        end
        cursor = data.nextPageCursor
        if not cursor then break end
    end
    if #servers > 0 then
        TeleportService:TeleportToPlaceInstance(PlaceId, servers[math.random(1, #servers)], LP)
    else
        TeleportService:Teleport(PlaceId, LP)
    end
end

-- ====== Coin helpers ======
local function getNearest(mapModel)
    local cc = mapModel and mapModel:FindFirstChild("CoinContainer")
    if not cc then return nil end
    local nearest, dist = nil, math.huge
    for _, coin in ipairs(cc:GetChildren()) do
        if coin:IsA("BasePart") then
            local v = coin:FindFirstChild("CoinVisual")
            if v and not v:GetAttribute("Collected") then
                local d = (HRP.Position - coin.Position).Magnitude
                if d < dist then
                    nearest, dist = coin, d
                end
            end
        end
    end
    return nearest
end

local currentTween
local function cancelTween()
    if currentTween then pcall(function() currentTween:Cancel() end); currentTween = nil end
end

local function tpTo(part)
    if not (HRP and part and part.CFrame) then return end
    if Humanoid then Humanoid:ChangeState(Enum.HumanoidStateType.Physics) end
    local d = (HRP.Position - part.Position).Magnitude
    local t = math.clamp(d / Config.SpeedFactor, Config.TweenMinTime, Config.TweenMaxTime)
    cancelTween()
    currentTween = TweenService:Create(HRP, TweenInfo.new(t, Enum.EasingStyle.Linear), {CFrame = part.CFrame})
    currentTween:Play()
    currentTween.Completed:Wait()
end

-- ====== MAIN LOOP ======
while true do
    -- 1) Ở lobby: đứng im cho tới khi MÌNH THỰC SỰ ở trong map
    local map = waitUntilActuallyInMap()
    local collected = 0

    -- 2) Ở trong map + round đang chạy => farm
    while isRoundLive() and map and map.Parent and isInsideMap(map, 12) do
        if not (Char and HRP and Humanoid) then Char, HRP, Humanoid = getChar() end

        local coin = getNearest(map)
        if coin then
            tpTo(coin)
            -- chờ coin collected hoặc timeout
            local v = coin:FindFirstChild("CoinVisual")
            local t0 = os.clock()
            while v and v.Parent and not v:GetAttribute("Collected") and (os.clock()-t0 < Config.CoinLockTime) do
                task.wait(0.05)
            end
            collected += 1
            task.wait(Config.DelayBetweenCoins)
            if collected >= Config.TargetCoins then break end
        else
            task.wait(0.18)
        end
    end

    cancelTween()

    -- 3) Nếu đạt mục tiêu -> hop; nếu round end trước đó -> quay lại lobby & chờ map kế
    if collected >= Config.TargetCoins then
        hopServer()
        break
    else
        -- quay lại lobby chờ (idle sẽ bật lại trong waitUntilActuallyInMap)
        task.wait(0.5)
    end
end

