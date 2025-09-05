--// Auto chọn "Phone" khi vào game

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer

local function SelectDevice()
    local args = { "Phone" }
    local remote = RS:WaitForChild("Remotes"):WaitForChild("Extras"):WaitForChild("ChangeLastDevice")
    remote:FireServer(unpack(args))
    warn("[AUTO] Đã chọn thiết bị Phone.")
end

-- Khi character spawn lần đầu hoặc respawn
LP.CharacterAdded:Connect(function()
    task.delay(1, SelectDevice) -- delay 1s cho chắc chắn GUI/remote đã sẵn sàng
end)

-- Nếu đã có character sẵn thì chạy luôn
if LP.Character then
    task.delay(1, SelectDevice)
end

