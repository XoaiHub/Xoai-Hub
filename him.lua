-- mm2 coin farm 🤑 (Eat until 40 coins then hop)

local Players      = game:GetService("Players")
local RS           = game:GetService("ReplicatedStorage")
local TP           = game:GetService("TeleportService")
local Http         = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")

local LP = Players.LocalPlayer
local PlaceId = game.PlaceId

-- === CONFIG ===
local Config = {
    SpeedFactor    = 35,   -- tốc độ di chuyển (càng cao càng nhanh, default 25-35)
    TweenMinTime   = 0.07, -- thời gian tween tối thiểu (an toàn)
    TweenMaxTime   = 2.0,
    CoinLockTime   = 2.0,
    DelayBetween   = 0.12, -- nghỉ nhỏ giữa 2 coin
    TargetCoins    = 40,   -- đủ số coin này thì hop
}

-- === Character ===
local function getChar()
    local char = LP.Character or LP.CharacterAdded:Wait()
    local hrp  = char:WaitForChild("HumanoidRootPart")
    local hum  = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid")
    return char, hrp, hum
end
local Char, HRP, Humanoid = getChar()
LP.CharacterAdded:Connect(function() Char, HRP, Humanoid = getChar() end)

-- === Map / Round ===
local function findActiveMap()
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:GetAttribute("MapID") and obj:FindFirstChild("CoinContainer") then
            return obj
        end
    end
end
local function isRoundLive()
    local ok, v = pcall(function()
        local gd = RS:FindFirstChild("GameData")
        local iv = gd and gd:FindFirstChild("InRound")
        return iv and iv.Value
    end)
    if ok and v ~= nil then return v end
    return findActiveMap() ~= nil
end
local function waitForRoundStart()
    while true do
        local m = findActiveMap()
        if m and isRoundLive() then return m end
        task.wait(0.25)
    end
end

-- === Server hop ===
local function hopServer()
    local servers, cursor = {}, nil
    local url = "https://games.roblox.com/v1/games/"..PlaceId.."/servers/Public?sortOrder=Asc&limit=100"
    while true do
        local res = game:HttpGet(url .. (cursor and "&cursor="..cursor or ""))
        local data = Http:JSONDecode(res)
        for _,s in ipairs(data.data) do
            if s.playing < s.maxPlayers and s.id ~= game.JobId then
                table.insert(servers, s.id)
            end
        end
        cursor = data.nextPageCursor
        if not cursor then break end
    end
    if #servers > 0 then
        TP:TeleportToPlaceInstance(PlaceId, servers[math.random(1,#servers)], LP)
    else
        TP:Teleport(PlaceId, LP)
    end
end

-- === Coin detect ===
local function getNearest(mapModel)
    local cc = mapModel:FindFirstChild("CoinContainer")
    if not cc then return end
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

-- === Teleport to coin ===
local function tpTo(part)
    if not (HRP and part) then return end
    local d = (HRP.Position - part.Position).Magnitude
    local t = math.clamp(d / Config.SpeedFactor, Config.TweenMinTime, Config.TweenMaxTime)
    local tw = TweenService:Create(HRP, TweenInfo.new(t, Enum.EasingStyle.Linear), {CFrame = part.CFrame})
    tw:Play()
    tw.Completed:Wait()
end

-- === MAIN ===
while true do
    local map = waitForRoundStart()
    local collected = 0

    while isRoundLive() and collected < Config.TargetCoins do
        if not (Char and HRP and Humanoid) then
            Char, HRP, Humanoid = getChar()
        end

        local coin = getNearest(map)
        if coin then
            tpTo(coin)

            -- chờ coin collected
            local v = coin:FindFirstChild("CoinVisual")
            local t0 = os.clock()
            while v and v.Parent and not v:GetAttribute("Collected") and (os.clock()-t0 < Config.CoinLockTime) do
                task.wait(0.05)
            end
            collected = collected + 1
            task.wait(Config.DelayBetween)
        else
            task.wait(0.2)
        end
    end

    -- Nếu đủ 40 coin => hop server
    if collected >= Config.TargetCoins then
        hopServer()
        break
    end

    -- Nếu round hết nhưng chưa đủ 40 coin => reset & chờ round mới
    task.wait(0.5)
end

