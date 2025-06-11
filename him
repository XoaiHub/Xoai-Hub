local players_service = cloneref(game:GetService("Players"))
local local_player = players_service.LocalPlayer
local workspace_ref = cloneref(workspace)
local farm_model = nil

-- Config
local pickup_enabled = true
local pickup_radius = 150

for _, descendant in next, workspace_ref:FindFirstChild("Farm"):GetDescendants() do
    if descendant.Name == "Owner" and descendant.Value == local_player.Name then
        farm_model = descendant.Parent and descendant.Parent.Parent
        break
    end
end

task.spawn(function()
    while pickup_enabled and farm_model do
        local plants_folder = farm_model:FindFirstChild("Plants_Physical")
        if plants_folder then
            for _, plant_model in next, plants_folder:GetChildren() do
                if plant_model:IsA("Model") then
                    for _, object in next, plant_model:GetDescendants() do
                        if object:IsA("ProximityPrompt") and (plant_model:GetPivot().Position - local_player.Character:GetPivot().Position).Magnitude < pickup_radius then
                            fireproximityprompt(object)
task.wait(.01)
                        end
                    end
                end
            end
        end
        task.wait()
    end
end)
