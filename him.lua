-- Đứng yên tại sell point
local workspace_ref = cloneref(workspace)
local players_service = cloneref(game:GetService("Players"))
local local_player = players_service.LocalPlayer
local farm_model = nil

for _, d in workspace_ref:FindFirstChild("Farm"):GetDescendants() do
    if d.Name == "Owner" and d.Value == local_player.Name then
        farm_model = d.Parent and d.Parent.Parent
        break
    end
end

if farm_model then
    local plants = farm_model:FindFirstChild("Plants_Physical")
    if plants then
        for _, m in plants:GetChildren() do
            for _, obj in m:GetDescendants() do
                if obj:IsA("ProximityPrompt") then
                    print("Trying to fire prompt from distance:", m.Name)
                    fireproximityprompt(obj)
                end
            end
        end
    end
end
