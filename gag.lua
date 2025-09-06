-- mm2 coin farm 🤑🤑🤑  (auto-run ONLY when in-map)
-- Yêu cầu: chỉ nhặt coin khi đã vào map game (round start)

-- // === Services / Refs ===
local TweenService = game:GetService("TweenService")
local Players      = game:GetService("Players")
local RS           = game:GetService("ReplicatedStorage")
local LP           = Players.LocalPlayer

-- Bảo đảm Character/HRP luôn hợp lệ (respawn an toàn)
local function getChar()
    local char = LP.Character or LP.CharacterAdded:Wait()
    local hrp  = char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart")
    local hum  = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid")
    return char, hrp, hum
end
local Char, HRP, Humanoid = getChar()
LP.CharacterAdded:Connect(function()
    Char, HRP, Humanoid = getChar()
end)

-- // === Round / Map detect ===
-- Trả về model map đang active (có thuộc tính MapID + CoinContainer tồn tại)
local function findActiveMap()
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:GetAttribute("MapID") and obj:FindFirstChild("CoinContainer") then
            return obj
        end
    end
    return nil
end

-- Bool: có round đang diễn ra không?
-- Ưu tiên tín hiệu "InRound" nếu game có, nếu không thì dựa vào map + coin
local function isRoundLive()
    -- 1) Nhiều bản MM2 có RS.GameData.InRound (BoolValue)
    local ok, inRound = pcall(function()
        local gd = RS:FindFirstChild("GameData")
        local iv = gd and gd:FindFirstChild("InRound")
        return iv and iv.Value
    end)
    if ok and inRound ~= nil then
        return inRound
    end

    -- 2) Fallback: có map & có khả năng spawn coin thì coi như đang trong round
    local m = findActiveMap()
    if not m then return false end
    local cc = m:FindFirstChild("CoinContainer")
    if not cc then return false end
    -- nếu đã có coin con hoặc map vừa spawn (đợi coin xuất hiện)
    if #cc:GetChildren() > 0 then return true end

    -- Kiểm tra thêm một nhịp ngắn xem coin có xuất hiện
    local t0 = os.clock()
    while os.clock() - t0 < 2 do
        if #cc:GetChildren() > 0 then return true end
        task.wait(0.1)
    end
    return false
end

-- Chờ đến khi round thật sự bắt đầu
local function waitForRoundStart()
    while true do
        -- đợi có map
        local m = findActiveMap()
        if m and isRoundLive() then
            return m
        end
        task.wait(0.25)
    end
end

-- // === Coin logic ===
local function getNearest(mapModel)
    local cc = mapModel and mapModel:FindFirstChild("CoinContainer")
    if not cc then return nil end
    local closest, dist = nil, math.huge
    for _, coin in ipairs(cc:GetChildren()) do
        if coin and coin:IsA("BasePart") then
            local v = coin:FindFirstChild("CoinVisual")
            if v and not v:GetAttribute("Collected") then
                local d = (HRP.Position - coin.Position).Magnitude
                if d < dist then
                    closest = coin
                    dist = d
                end
            end
        end
    end
    return closest
end

local function tp(targetPart)
    if not (HRP and targetPart and targetPart.CFrame) then return end
    if Humanoid then Humanoid:ChangeState(Enum.HumanoidStateType.Physics) end
    local d = (HRP.Position - targetPart.Position).Magnitude
    local tw = TweenService:Create(HRP, TweenInfo.new(math.clamp(d / 25, 0.08, 2.5), Enum.EasingStyle.Linear), {CFrame = targetPart.CFrame})
    tw:Play()
    tw.Completed:Wait()
end

-- // === Main loop ===
while true do
    -- Chỉ bắt đầu khi vào map/round
    local currentMap = waitForRoundStart()

    -- Farm cho tới khi round kết thúc hoặc map biến mất
    while isRoundLive() and currentMap and currentMap.Parent do
        -- nếu chết/respawn thì cập nhật ref
        if not (Char and Char.Parent and HRP and HRP.Parent and Humanoid and Humanoid.Parent) then
            Char, HRP, Humanoid = getChar()
        end

        local target = getNearest(currentMap)
        if target then
            tp(target)
            -- giữ sát coin đó đến khi collected hoặc coin biến mất/round đổi
            local v = target:FindFirstChild("CoinVisual")
            local t0 = os.clock()
            while isRoundLive() and v and v.Parent and not v:GetAttribute("Collected") do
                -- nếu có coin gần hơn thì thoát để chuyển mục tiêu
                local n = getNearest(currentMap)
                if n and n ~= target then break end
                -- tránh kẹt quá lâu 1 coin
                if os.clock() - t0 > 2.5 then break end
                task.wait(0.05)
            end
        else
            -- không thấy coin -> chờ chút rồi check lại
            task.wait(0.15)
        end
    end

    -- Round đã xong => quay lại vòng lặp & chờ round kế tiếp
    task.wait(0.5)
end

