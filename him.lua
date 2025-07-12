-- ==========================
-- ⚙️ BOOST SERVER + LOCK FPS
-- ==========================
local cfg = getgenv().Settings

-- 🔒 Lock FPS thủ công
if cfg["Lock FPS"] and cfg["Lock FPS"]["Enabled"] then
    setfpscap(cfg["Lock FPS"]["FPS"])
end

-- ⚙️ Boost Server Script
local function optimizeGame()
    if not cfg["Boost Server"] then return end

    -- 🧹 Xoá object theo tên
    if cfg["Object Removal"] and cfg["Object Removal"]["Enabled"] then
        for _, obj in ipairs(workspace:GetDescendants()) do
            for _, name in ipairs(cfg["Object Removal"]["Targets"]) do
                if string.find(obj.Name:lower(), name:lower()) then
                    pcall(function() obj:Destroy() end)
                end
            end
        end
    end

    -- 💨 Xoá hiệu ứng
    if cfg["Remove Effects"] then
        for _, v in ipairs(workspace:GetDescendants()) do
            if v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Smoke") or v:IsA("Fire") or v:IsA("Sparkles") then
                pcall(function() v:Destroy() end)
            end
        end
    end

    -- 🔇 Xoá âm thanh
    if cfg["Remove Sounds"] then
        for _, sound in ipairs(workspace:GetDescendants()) do
            if sound:IsA("Sound") and sound.Looped then
                pcall(function() sound:Stop(); sound:Destroy() end)
            end
        end
    end

    -- 🌙 Tối giản ánh sáng
    if cfg["Simplify Lighting"] then
        local lighting = game:GetService("Lighting")
        lighting.FogEnd = 1000000
        lighting.Brightness = 0
        lighting.GlobalShadows = false
    end
end

spawn(function()
    while true do
        optimizeGame()
        task.wait(5)
    end
end)

-- ==========================
-- 🚂 TELEPORT + CREATE PARTY (THEO CONFIG)
-- ==========================

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

-- Đếm số người trong Zone
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

-- Teleport đến Zone
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

-- Tạo Party
local function createParty(mode)
    local args = {{
        isPrivate = true,
        maxMembers = 1,
        trainId = "default",
        gameMode = mode
    }}
    game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Network")
        :WaitForChild("RemoteEvent"):WaitForChild("CreateParty"):FireServer(unpack(args))
end

-- Tạo danh sách zone theo config
local zoneList = {}
for zoneName, _ in pairs(getgenv().TargetPlayersPerZone or {}) do
    table.insert(zoneList, zoneName)
end
table.sort(zoneList, function(a, b) return a < b end)

-- Vòng lặp chính
task.spawn(function()
    while getgenv().EnableTeleport do
        local foundSlot = false

        -- Nếu đã ở zone và chưa full slot → giữ nguyên
        if currentZone then
            local count = getPlayerCountInZone(currentZone)
            local target = getgenv().TargetPlayersPerZone[currentZone]

            if count < target then
                print(string.format("[Đang ở %s] %d / %d", currentZone, count, target))
                -- Tạo party nếu chưa tạo
                if not createdParty and getgenv().EnableParty then
                    task.delay(1, function()
                        if getgenv().EnableParty["Normal"] then createParty("Normal") end
                        if getgenv().EnableParty["ScorchedEarth"] then createParty("Scorched Earth") end
                        if getgenv().EnableParty["Nightmare"] then createParty("Nightmare") end
                        createdParty = true
                        print("[Party Created]")
                    end)
                end

                foundSlot = true
            else
                currentZone = nil
                createdParty = false
            end
        end

        -- Nếu chưa ở zone hoặc zone đã full, tìm zone mới
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
-- ==========================
-- 🧩 UI Mochi Hub
-- có thể tự xóa ui
-- ==========================
if game.CoreGui:FindFirstChild("MochiUI") then
    game.CoreGui.NexonUI:Destroy()
end

local gui = Instance.new("ScreenGui", game.CoreGui)
gui.Name = "MochiUi"
gui.ResetOnSpawn = false

local mainFrame = Instance.new("Frame", gui)
mainFrame.Size = UDim2.new(0, 400, 0, 300)
mainFrame.Position = UDim2.new(0.5, 0, 0.4, 0)
mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
mainFrame.BackgroundTransparency = 1

local bondFrame = Instance.new("Frame", mainFrame)
bondFrame.Name = "BondUI"
bondFrame.Size = UDim2.new(0, 180, 0, 30)
bondFrame.Position = UDim2.new(0.5, 0, 0, 227)
bondFrame.AnchorPoint = Vector2.new(0.5, 0)
bondFrame.BackgroundTransparency = 1
bondFrame.BorderSizePixel = 0
bondFrame.Draggable = false
bondFrame.Active = true

local logo = Instance.new("ImageLabel", bondFrame)
logo.Size = UDim2.new(0, 24, 0, 24)
logo.Position = UDim2.new(0, 0, 0.5, 0)
logo.AnchorPoint = Vector2.new(0, 0.5)
logo.BackgroundTransparency = 1
logo.Image = "rbxassetid://..."
logo.ScaleType = Enum.ScaleType.Fit

local bondLabel = Instance.new("TextLabel", bondFrame)
bondLabel.Size = UDim2.new(0, 300, 0, 50)  -- Width: 300px, Height: 50px (có thể tùy chỉnh)
bondLabel.Position = UDim2.new(0.5, 0, 0.5, 0)  -- Giữa bondFrame
bondLabel.AnchorPoint = Vector2.new(0.5, 0.5)  -- Căn giữa theo toạ độ gốc
bondLabel.BackgroundTransparency = 1
bondLabel.Text = "Bond (+0)"
bondLabel.TextSize = 40
bondLabel.Font = Enum.Font.Gotham
bondLabel.TextColor3 = Color3.new(1, 1, 1)
bondLabel.TextXAlignment = Enum.TextXAlignment.Center
bondLabel.TextYAlignment = Enum.TextYAlignment.Center

-- ==========================
-- 🔁 Bond, Auto Farm, MaximGun, Train
-- ==========================
if not game:IsLoaded() then game.Loaded:Wait() end
repeat task.wait() until player.Character and player.PlayerGui:FindFirstChild("LoadingScreenPrefab") == nil

game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("EndDecision"):FireServer(false)

_G.Bond = 0
workspace.RuntimeItems.ChildAdded:Connect(function(v)
    if v.Name:find("Bond") and v:FindFirstChild("Part") then
        v.Destroying:Connect(function()
            _G.Bond += 1
        end)
    end
end)

spawn(function()
    while bondLabel do
        bondLabel.Text = "Bond (+" .. tostring(_G.Bond) .. ")"
        task.wait(2)
    end
end)

player.CameraMode = "Classic"
player.CameraMaxZoomDistance = math.huge
player.CameraMinZoomDistance = 30
player.Character.HumanoidRootPart.Anchored = true
wait(0.3)

repeat task.wait()
    player.Character.HumanoidRootPart.Anchored = true
    player.Character.HumanoidRootPart.CFrame = CFrame.new(80, 3, -9000)
until workspace.RuntimeItems:FindFirstChild("MaximGun")

task.wait(0.3)
for _, v in pairs(workspace.RuntimeItems:GetChildren()) do
    if v.Name == "MaximGun" and v:FindFirstChild("VehicleSeat") then
        v.VehicleSeat.Disabled = false
        v.VehicleSeat:SetAttribute("Disabled", false)
        v.VehicleSeat:Sit(player.Character:FindFirstChild("Humanoid"))
    end
end

task.wait(0.5)
for _, v in pairs(workspace.RuntimeItems:GetChildren()) do
    if v.Name == "MaximGun" and v:FindFirstChild("VehicleSeat") and (player.Character.HumanoidRootPart.Position - v.VehicleSeat.Position).Magnitude < 250 then
        player.Character.HumanoidRootPart.CFrame = v.VehicleSeat.CFrame
    end
end

wait(1)
player.Character.HumanoidRootPart.Anchored = false
repeat wait() until player.Character.Humanoid.Sit == true
wait(0.5)
player.Character.Humanoid.Sit = false
wait(0.5)

repeat task.wait()
    for _, v in pairs(workspace.RuntimeItems:GetChildren()) do
        if v.Name == "MaximGun" and v:FindFirstChild("VehicleSeat") and (player.Character.HumanoidRootPart.Position - v.VehicleSeat.Position).Magnitude < 250 then
            player.Character.HumanoidRootPart.CFrame = v.VehicleSeat.CFrame
        end
    end
until player.Character.Humanoid.Sit == true

wait(0.9)
for _, v in pairs(workspace:GetChildren()) do
    if v:IsA("Model") and v:FindFirstChild("RequiredComponents") and v.RequiredComponents:FindFirstChild("Controls") and v.RequiredComponents.Controls:FindFirstChild("ConductorSeat") then
        local seat = v.RequiredComponents.Controls.ConductorSeat:FindFirstChild("VehicleSeat")
        if seat then
            local TpTrain = game:GetService("TweenService"):Create(player.Character.HumanoidRootPart, TweenInfo.new(35, Enum.EasingStyle.Quad), {CFrame = seat.CFrame * CFrame.new(0, 20, 0)})
            TpTrain:Play()
            local bv = Instance.new("BodyVelocity")
            bv.Name = "VelocityHandler"
            bv.Parent = player.Character.HumanoidRootPart
            bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
            bv.Velocity = Vector3.new(0, 0, 0)
            TpTrain.Completed:Wait()
        end
    end
end

wait(1)
while true do
    if player.Character.Humanoid.Sit then
        local TpEnd = game:GetService("TweenService"):Create(player.Character.HumanoidRootPart, TweenInfo.new(30, Enum.EasingStyle.Quad), {CFrame = CFrame.new(0.5, -78, -49429)})
        TpEnd:Play()
        local bv = Instance.new("BodyVelocity")
        bv.Name = "VelocityHandler"
        bv.Parent = player.Character.HumanoidRootPart
        bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
        bv.Velocity = Vector3.new(0, 0, 0)
        repeat wait() until workspace.RuntimeItems:FindFirstChild("Bond")
        TpEnd:Cancel()
        for _, v in pairs(workspace.RuntimeItems:GetChildren()) do
            if v.Name:find("Bond") and v:FindFirstChild("Part") then
                repeat task.wait()
                    if v:FindFirstChild("Part") then
                        player.Character.HumanoidRootPart.CFrame = v.Part.CFrame
                        game:GetService("ReplicatedStorage").Shared.Network.RemotePromise.Remotes.C_ActivateObject:FireServer(v)
                    end
                until not v:FindFirstChild("Part")
            end
        end
    end
    task.wait()
end
