local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local CollectController = require(ReplicatedStorage.Modules.CollectController)

local pickup_enabled = true
local autoFarmEnabled = true -- Bạn có thể điều khiển bật/tắt farm bằng biến này

-- Reset trạng thái CollectController
CollectController._lastCollected = 0
CollectController._holding = true
CollectController:_updateButtonState()

-- Tìm nông trại của người chơi
local farm_model
for _, descendant in pairs(Workspace:FindFirstChild("Farm"):GetDescendants()) do
    if descendant.Name == "Owner" and descendant.Value == localPlayer.Name then
        farm_model = descendant.Parent and descendant.Parent.Parent
        break
    end
end

-- Thu hoạch cây trồng
task.spawn(function()
    while pickup_enabled and farm_model do
        local plants_folder = farm_model:FindFirstChild("Plants_Physical")
        if plants_folder then
            for _, plant_model in pairs(plants_folder:GetChildren()) do
                if plant_model:IsA("Model") then
                    CollectController._lastCollected = 0
                    CollectController:_updateButtonState()
                    CollectController:Collect(plant_model)
                    
                    for _, object in pairs(plant_model:GetDescendants()) do
                        CollectController._lastCollected = 0
                        CollectController:_updateButtonState()
                        CollectController:Collect(object)
                        task.wait(0.01)
                    end
                end
            end
        end
        task.wait(0.1)
    end
end)

-- Hàm dịch chuyển glitch
local function glitchTeleport(pos)
    if not localPlayer.Character then return end
    local root = localPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local tween = TweenService:Create(root, TweenInfo.new(0.15, Enum.EasingStyle.Linear), {
        CFrame = CFrame.new(pos + Vector3.new(0, 5, 0))
    })
    tween:Play()
end

-- Dummy function cần bạn tự định nghĩa đúng theo game của bạn
local function updateFarmData()
    -- Trả về farms, plants
    return {}, {}
end

local function isInventoryFull()
    -- Kiểm tra nếu túi đầy
    return false
end

-- Tự động farm
task.spawn(function()
    while autoFarmEnabled do
        while autoFarmEnabled and isInventoryFull() do
            task.wait(1)
        end

        if not autoFarmEnabled then break end

        local farms, plants = updateFarmData()

        for _, part in pairs(plants) do
            if not autoFarmEnabled or isInventoryFull() then break end
            if part and part.Parent then
                local prompt = part:FindFirstChildOfClass("ProximityPrompt")
                if prompt then
                    glitchTeleport(part.Position)
                    task.wait(0.2)

                    for _, farm in pairs(farms) do
                        if not autoFarmEnabled or isInventoryFull() then break end
                        for _, obj in pairs(farm:GetDescendants()) do
                            if obj:IsA("ProximityPrompt") then
                                local str = tostring(obj.Parent)
                                if not (str:find("Grow_Sign") or str:find("Core_Part")) then
                                    fireproximityprompt(obj, 1)
                                end
                            end
                        end
                    end

                    task.wait(0.2)
                end
            end
        end

        task.wait(0.1)
    end
end)
