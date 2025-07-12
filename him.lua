if not getgenv().EnableTeleport then return end
repeat task.wait() until game:IsLoaded()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local ZonesFolder = workspace:WaitForChild("PartyZones", 10)
local currentZone = nil
local partyCreated = false

-- Lấy HRP
local function getHRP()
    local char = player.Character or player.CharacterAdded:Wait()
    return char:WaitForChild("HumanoidRootPart", 5)
end

-- Đếm người trong zone
local function getPlayerCountInZone(zoneName)
    local zone = ZonesFolder:FindFirstChild(zoneName)
    if not zone then return math.huge end
    local hitbox = zone:FindFirstChild("Hitbox")
    if not hitbox then return math.huge end

    local count = 0
    for _, p in pairs(Players:GetPlayers()) do
        local char = p.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp and (hrp.Position - hitbox.Position).Magnitude <= 15 then
            count += 1
        end
    end
    return count
end

-- Teleport
local function teleportTo(zoneName)
    local zone = ZonesFolder:FindFirstChild(zoneName)
    if not zone then return end
    local hitbox = zone:FindFirstChild("Hitbox")
    if not hitbox then return end

    local hrp = getHRP()
    if hrp then
        hrp.CFrame = CFrame.new(hitbox.Position + Vector3.new(0, getgenv().YOffset or 5, 0))
        currentZone = zoneName
        partyCreated = false
        print("[✅ Teleport đến]:", zoneName)
    end
end

-- Create Party
local function createParty(mode)
    local args = { {
        isPrivate = true,
        maxMembers = 1,
        trainId = "default",
        gameMode = mode
    } }
    ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network")
        :WaitForChild("RemoteEvent"):WaitForChild("CreateParty"):FireServer(unpack(args))
    print("[🎉 Đã tạo Party]:", mode)
end

-- BẮT SỰ KIỆN LEAVE PARTY
local leaveEvent = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network")
    :WaitForChild("RemoteEvent"):WaitForChild("LeaveParty")

leaveEvent.OnClientEvent:Connect(function()
    print("[🚪 Đã rời khỏi party] → Cho phép teleport lại.")
    partyCreated = false
end)

-- MAIN LOOP
task.spawn(function()
    local zoneList = {}
    for name, _ in pairs(getgenv().TargetPlayersPerZone) do
        table.insert(zoneList, name)
    end
    table.sort(zoneList)

    while getgenv().EnableTeleport do
        if not partyCreated then
            for _, zoneName in ipairs(zoneList) do
                local target = getgenv().TargetPlayersPerZone[zoneName]
                local current = getPlayerCountInZone(zoneName)

                print(string.format("🔍 [%s]: %d/%d", zoneName, current, target))

                if current < target then
                    if currentZone ~= zoneName then
                        teleportTo(zoneName)
                    end

                    task.wait(1)

                    if currentZone == zoneName and not partyCreated then
                        if getgenv().EnableParty then
                            if getgenv().EnableParty["Normal"] then createParty("Normal") end
                            if getgenv().EnableParty["ScorchedEarth"] then createParty("Scorched Earth") end
                            if getgenv().EnableParty["Nightmare"] then createParty("Nightmare") end
                        end
                        partyCreated = true
                    end
                    break
                end
            end
        end

        task.wait(getgenv().TeleportInterval or 5)
    end
end)
