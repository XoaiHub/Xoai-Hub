local players_service = cloneref(game:GetService("Players"))
local local_player = players_service.LocalPlayer
local workspace_ref = cloneref(workspace)
local farm_model = nil

-- Config
local pickup_enabled = true
local pickup_radius = 150

-- Find your own farm model
for _, descendant in next, workspace_ref:FindFirstChild("Farm"):GetDescendants() do
    if descendant.Name == "Owner" and descendant.Value == local_player.Name then
        farm_model = descendant.Parent and descendant.Parent.Parent
        break
    end
end

-- Anchor the player to "stand still"
local function anchorPlayer()
    local character = local_player.Character
    if character and character:FindFirstChild("HumanoidRootPart") then
        character.HumanoidRootPart.Anchored = true
    end
end

-- Unanchor if needed
local function unanchorPlayer()
    local character = local_player.Character
    if character and character:FindFirstChild("HumanoidRootPart") then
        character.HumanoidRootPart.Anchored = false
    end
end

-- Fire proximity prompts near the player
task.spawn(function()
    anchorPlayer()

    while pickup_enabled and farm_model do
        local character = local_player.Character
        if not character or not character:FindFirstChild("HumanoidRootPart") then
            task.wait(1)
            continue
        end

        local plants_folder = farm_model:FindFirstChild("Plants_Physical")
        if plants_folder then
            for _, plant_model in next, plants_folder:GetChildren() do
                if plant_model:IsA("Model") then
                    for _, object in next, plant_model:GetDescendants() do
                        if object:IsA("ProximityPrompt") then
                            local distance = (plant_model:GetPivot().Position - character:GetPivot().Position).Magnitude
                            if distance < pickup_radius then
                                fireproximityprompt(object)
                                task.wait(0.01)
                            end
                        end
                    end
                end
            end
        end

        task.wait(0.1)
    end

    unanchorPlayer()
end)
