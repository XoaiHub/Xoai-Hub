-- MM2 Farm (Safe-Walk, anti 267): lobby idle → vào map → nhặt tới 40 coin → hop server

-- ===== CONFIG =====
local Config = {
    IdleInLobby       = true,
    IdleMethod        = "walkspeed", -- hoặc "anchor"
    IdleWalkSpeed     = 0,  IdleJumpPower=0,
    RestoreWalkSpeed  = 16, RestoreJumpPower=50,

    TargetCoins       = 40,
    -- Di chuyển an toàn (đi bộ theo path)
    WalkSpeed         = 18,     -- tốc độ Humanoid (16–20 an toàn)
    MaxStudsPerStep   = 6.0,    -- bước tối đa mỗi lần tiến (studs)
    StepInterval      = 0.10,   -- thời gian giữa các bước (s)
    RepathInterval    = 1.25,   -- bao lâu thì tính lại path (s)
    RepathOnStuck     = 0.8,    -- nếu không tiến thêm ≥0.8s → repath
    GroundOffset      = 2.5,    -- bám sàn
    CoinLockTime      = 2.0,
    DelayBetweenCoins = 0.10,
    RoundPollDelay    = 0.25,
}

-- ===== Services =====
local g=game
local Players=g:GetService("Players")
local RS=g:GetService("ReplicatedStorage")
local PathfindingService=g:GetService("PathfindingService")
local TweenService=g:GetService("TweenService")
local TeleportService=g:GetService("TeleportService")
local HttpService=g:GetService("HttpService")
local RunService=g:GetService("RunService")
local LP=Players.LocalPlayer
local PlaceId=g.PlaceId

-- ===== Character =====
local function getChar()
    local char=LP.Character or LP.CharacterAdded:Wait()
    local hrp=char:WaitForChild("HumanoidRootPart")
    local hum=char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid")
    return char,hrp,hum
end
local Char,HRP,Humanoid=getChar()
LP.CharacterAdded:Connect(function() Char,HRP,Humanoid=getChar() end)

-- ===== Idle (lobby) =====
local function applyIdle(state)
    if not Humanoid or not HRP then return end
    if state then
        if Config.IdleMethod=="walkspeed" then
            Humanoid.WalkSpeed=Config.IdleWalkSpeed
            Humanoid.JumpPower=Config.IdleJumpPower
        else HRP.Anchored=true end
    else
        if Config.IdleMethod=="walkspeed" then
            Humanoid.WalkSpeed=Config.RestoreWalkSpeed
            Humanoid.JumpPower=Config.RestoreJumpPower
        else HRP.Anchored=false end
    end
end

-- ===== Round / Map detect =====
local function findActiveMap()
    for _,obj in ipairs(workspace:GetChildren()) do
        if obj:GetAttribute("MapID") and obj:FindFirstChild("CoinContainer") then
            return obj
        end
    end
end

local function getInRoundFlag()
    local ok,v=pcall(function()
        local gd=RS:FindFirstChild("GameData")
        local iv=gd and gd:FindFirstChild("InRound")
        return iv and iv.Value
    end)
    return ok and v or nil
end

local function isRoundLive()
    local f=getInRoundFlag()
    if f~=nil then return f end
    return findActiveMap()~=nil
end

local function isInsideMap(mapModel,margin)
    margin=margin or 12
    if not (mapModel and HRP) then return false end
    local cf,size=mapModel:GetBoundingBox()
    local rel=cf:PointToObjectSpace(HRP.Position)
    local half=size*0.5
    return math.abs(rel.X)<=half.X+margin
        and math.abs(rel.Y)<=half.Y+margin
        and math.abs(rel.Z)<=half.Z+margin
end

local function waitUntilActuallyInMap()
    if Config.IdleInLobby then applyIdle(true) end
    while true do
        local m=findActiveMap()
        if m and isRoundLive() and isInsideMap(m,12) then
            if Config.IdleInLobby then applyIdle(false) end
            Humanoid.WalkSpeed=Config.WalkSpeed
            return m
        end
        task.wait(Config.RoundPollDelay)
    end
end

-- ===== Hop server =====
local function hopServer()
    local servers, cursor = {}, nil
    local base=("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(PlaceId)
    while true do
        local res=game:HttpGet(base..(cursor and "&cursor="..cursor or ""))
        local data=HttpService:JSONDecode(res)
        for _,s in ipairs(data.data) do
            if s.playing < s.maxPlayers and s.id~=game.JobId then
                table.insert(servers,s.id)
            end
        end
        cursor=data.nextPageCursor
        if not cursor then break end
    end
    if #servers>0 then
        TeleportService:TeleportToPlaceInstance(PlaceId, servers[math.random(1,#servers)], LP)
    else
        TeleportService:Teleport(PlaceId, LP)
    end
end

-- ===== Coin helpers =====
local function getNearest(mapModel)
    local cc=mapModel and mapModel:FindFirstChild("CoinContainer")
    if not cc then return nil end
    local nearest,dist=nil,math.huge
    for _,coin in ipairs(cc:GetChildren()) do
        if coin:IsA("BasePart") then
            local v=coin:FindFirstChild("CoinVisual")
            if v and not v:GetAttribute("Collected") then
                local d=(HRP.Position-coin.Position).Magnitude
                if d<dist then nearest,dist=coin,d end
            end
        end
    end
    return nearest
end

-- ===== Safe-walk mover (anti 267) =====
local lastStep=0
local function groundSnap(pos)
    -- raycast xuống để bám mặt đất
    local ray=Ray.new(pos+Vector3.new(0,5,0), Vector3.new(0,-20,0))
    local hit,hitPos=workspace:FindPartOnRayWithIgnoreList(ray, {Char})
    if hit then
        return Vector3.new(hitPos.X, hitPos.Y + Config.GroundOffset, hitPos.Z)
    end
    return pos
end

local function followPathTo(targetPos)
    local startTime=os.clock()
    local lastPos=HRP.Position
    local deadline=startTime+Config.CoinLockTime+1.5

    while os.clock()<deadline do
        if not isRoundLive() then return false end
        if (HRP.Position-targetPos).Magnitude<3.5 then return true end

        -- Tính path định kỳ hoặc khi bị kẹt
        local stuck = (os.clock()-lastStep)>Config.RepathOnStuck and (HRP.Position - lastPos).Magnitude < 1.0
        if (os.clock()-lastStep)>Config.RepathInterval or stuck then
            lastStep=os.clock(); lastPos=HRP.Position
            local path=PathfindingService:CreatePath({
                AgentRadius=2, AgentHeight=5, AgentCanJump=true,
                Costs={Water=100}
            })
            path:ComputeAsync(HRP.Position, targetPos)
            if path.Status ~= Enum.PathStatus.Success then
                return false
            end

            local waypoints=path:GetWaypoints()
            for i=1,#waypoints do
                local wp=waypoints[i]
                local goal=groundSnap(wp.Position)
                local dir=(goal - HRP.Position)
                local dist=dir.Magnitude
                if dist>0 then
                    local step=math.min(Config.MaxStudsPerStep, dist)
                    local moveTo=HRP.Position + dir.Unit*step
                    moveTo=groundSnap(moveTo)
                    Humanoid:MoveTo(moveTo + Vector3.new(
                        (math.random()-0.5)*0.4, 0, (math.random()-0.5)*0.4)) -- jitter nhỏ
                    local t0=os.clock()
                    while (HRP.Position - moveTo).Magnitude>1.2 do
                        if os.clock()-t0>Config.StepInterval*2 then break end
                        RunService.Heartbeat:Wait()
                    end
                    task.wait(Config.StepInterval)
                end
                if (HRP.Position-targetPos).Magnitude<3.5 then return true end
                if not isRoundLive() then return false end
            end
        else
            RunService.Heartbeat:Wait()
        end
    end
    return false
end

-- ===== MAIN =====
while true do
    -- Lobby: đứng chờ tới khi MÌNH ở trong map
    local map=waitUntilActuallyInMap()
    local collected=0

    while isRoundLive() and map and map.Parent and isInsideMap(map,12) do
        if not (Char and HRP and Humanoid) then Char,HRP,Humanoid=getChar() end

        local coin=getNearest(map)
        if coin then
            local goal=coin.Position
            followPathTo(goal)

            local v=coin:FindFirstChild("CoinVisual")
            local t0=os.clock()
            while v and v.Parent and not v:GetAttribute("Collected") and (os.clock()-t0<Config.CoinLockTime) do
                task.wait(0.05)
            end
            collected += 1
            task.wait(Config.DelayBetweenCoins)
            if collected>=Config.TargetCoins then break end
        else
            task.wait(0.18)
        end
    end

    if collected>=Config.TargetCoins then
        hopServer()
        break
    else
        -- Round kết thúc → quay về lobby (idle sẽ auto bật ở hàm chờ)
        task.wait(0.5)
    end
end

