if not getgenv().EnableTeleport then return end
repeat task.wait() until game:IsLoaded()

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local createdParty = false
local currentZone = nil

-- Lấy HRP
local function getHRP()
    local char = player.Character or player.CharacterAdded:Wait()
    return char:WaitForChild("HumanoidRootPart")
end

-- Đếm người trong Zone
local function getPlayerCountInZone(zoneName)
    local zone = workspace:WaitForChild("PartyZones", 10):FindFirstChild(zoneName)
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

-- Teleport tới Zone
local function teleportToZone(zoneName)
    local zone = workspace:WaitForChild("PartyZones", 10):FindFirstChild(zoneName)
    if not zone then return end
    local hitbox = zone:FindFirstChild("Hitbox")
    if not hitbox then return end

    local hrp = getHRP()
    if hrp then
        hrp.CFrame = CFrame.new(hitbox.Position + Vector3.new(0, getgenv().YOffset or 5, 0))
        print("[Teleported to]:", zoneName)
    end
end

-- Tạo party với mode cụ thể
local function createParty(mode)
    local args = {{
        isPrivate = true,
        maxMembers = 1,
        trainId = "default",
        gameMode = mode
    }}
    local success, err = pcall(function()
        game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Network")
            :WaitForChild("RemoteEvent"):WaitForChild("CreateParty"):FireServer(unpack(args))
    end)
    if success then
        print("[Party Created]:", mode)
    else
        warn("[Failed to Create Party]:", err)
    end
end

-- Danh sách zone
local zoneList = {}
for zoneName, _ in pairs(getgenv().TargetPlayersPerZone or {}) do
    table.insert(zoneList, zoneName)
end
table.sort(zoneList, function(a, b) return a < b end)

-- Vòng lặp chính
task.spawn(function()
    while getgenv().EnableTeleport do
        local foundSlot = false

        -- Nếu đang ở trong zone
        if currentZone then
            local count = getPlayerCountInZone(currentZone)
            local target = getgenv().TargetPlayersPerZone[currentZone]

            if count < target then
                print(string.format("[Ở %s] %d / %d", currentZone, count, target))
                -- Tạo party nếu chưa tạo
                if not createdParty and getgenv().EnableParty then
                    if getgenv().EnableParty["Normal"] then createParty("Normal") end
                    if getgenv().EnableParty["ScorchedEarth"] then createParty("Scorched Earth") end
                    if getgenv().EnableParty["Nightmare"] then createParty("Nightmare") end
                    createdParty = true
                end
                foundSlot = true
            else
                -- Slot đã full, reset lại
                currentZone = nil
                createdParty = false
            end
        end

        -- Nếu chưa ở zone hoặc slot đã full, tìm zone mới
        if not foundSlot then
            for _, zoneName in ipairs(zoneList) do
                local count = getPlayerCountInZone(zoneName)
                local target = getgenv().TargetPlayersPerZone[zoneName]
                if count < target then
                    teleportToZone(zoneName)
                    currentZone = zoneName
                    createdParty = false
                    foundSlot = true
                    break
                end
            end
        end

        if not foundSlot then
            print("[Tất cả zone đã đầy] → Đứng yên")
        end

        task.wait(getgenv().TeleportInterval or 5)
    end
end)
