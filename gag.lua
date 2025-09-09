-- ================================================================
-- Mochi MM2 Auto Device + Safe Lobby Wait + In-Map Coin Farm
-- - Auto "Phone" chọn bằng click nút con trong frame Phone (fallback remote)
-- - Ở lobby đứng yên, không tele vào map người khác đang chơi
-- - Chỉ farm khi bạn THỰC SỰ đã ở trong map + round đang diễn ra
-- - Tween cẩn thận tránh kick
-- ================================================================

-- // === Services / Refs ===
local g               = game
local Players         = g:GetService("Players")
local RS              = g:GetService("ReplicatedStorage")
local TweenService    = g:GetService("TweenService")
local UIS             = g:GetService("UserInputService")
local VIM             = g:GetService("VirtualInputManager")
local LP              = Players.LocalPlayer

-- // === Auto chọn "Phone" bằng click nút con trong frame Phone ===
local function chainVisible(gui)
    local cur = gui
    while cur and cur ~= LP do
        if cur:IsA("GuiObject") and cur.Visible == false then return false end
        if cur:IsA("ScreenGui") and cur.Enabled == false then return false end
        cur = cur.Parent
    end
    return true
end

local function getPhoneFrame()
    local pg = LP:WaitForChild("PlayerGui", 10)
    if not pg then return nil end
    local DS = pg:WaitForChild("DeviceSelect", 10)
    if not DS then return nil end
    local Container = DS:WaitForChild("Container", 10)
    if not Container then return nil end
    local Phone = Container:WaitForChild("Phone", 10)
    return Phone, DS
end

local function listClickableDescendants(root)
    local cands = {}
    for _, d in ipairs(root:GetDescendants()) do
        local cn = d.ClassName
        local n = d.Name:lower()
        local isBtnClass = (cn == "ImageButton" or cn == "TextButton")
        local looksLikeBtn = (n:find("btn") or n:find("button") or n:find("click") or n:find("hitbox") or n:find("select"))
        if isBtnClass or (d:IsA("GuiObject") and looksLikeBtn) then
            table.insert(cands, d)
        end
    end
    if #cands == 0 then
        for _, d in ipairs(root:GetDescendants()) do
            if d:IsA("GuiObject") then
                table.insert(cands, d)
            end
        end
    end
    return cands
end

local function clickAtGuiObject(gui)
    if not (gui and gui.AbsolutePosition and gui.AbsoluteSize) then return false, "no-abs" end
    local pos, size = gui.AbsolutePosition, gui.AbsoluteSize
    local x = pos.X + size.X/2
    local y = pos.Y + size.Y/2

    -- 1) firesignal
    if typeof(firesignal) == "function" then
        local ok = false
        pcall(function() if gui.MouseButton1Click then firesignal(gui.MouseButton1Click); ok = true end end)
        if ok then return true, "firesignal(MouseButton1Click)" end
        pcall(function() if gui.Activated then firesignal(gui.Activated); ok = true end end)
        if ok then return true, "firesignal(Activated)" end
        pcall(function()
            if gui.MouseButton1Down and gui.MouseButton1Up then
                firesignal(gui.MouseButton1Down); task.wait(0.02); firesignal(gui.MouseButton1Up); ok = true
            end
        end)
        if ok then return true, "firesignal(Down/Up)" end
    end

    -- 2) :Activate()
    local ok2 = pcall(function() if gui.Activated then gui:Activate() end end)
    if ok2 then return true, ":Activate()" end

    -- 3) VIM target = gui
    pcall(function()
        VIM:SendMouseMoveEvent(x, y, gui)
        VIM:SendMouseButtonEvent(x, y, 0, true, gui, 0)
        VIM:SendMouseButtonEvent(x, y, 0, false, gui, 0)
    end)
    task.wait(0.04)

    -- 4) VIM target = nil
    pcall(function()
        VIM:SendMouseMoveEvent(x, y, nil)
        VIM:SendMouseButtonEvent(x, y, 0, true, nil, 0)
        VIM:SendMouseButtonEvent(x, y, 0, false, nil, 0)
    end)
    task.wait(0.04)

    -- 5) Touch tap
    if UIS.TouchEnabled then
        pcall(function()
            VIM:SendTouchEvent(x, y, 0, true)
            VIM:SendTouchEvent(x, y, 0, false)
        end)
        task.wait(0.03)
    end

    return false, "vim/touch"
end

local function fallbackRemote()
    local ok = pcall(function()
        RS:WaitForChild("Remotes"):WaitForChild("Extras"):WaitForChild("ChangeLastDevice"):FireServer("Phone")
    end)
    warn("[AUTO-DEVICE] Fallback ChangeLastDevice('Phone') ->", ok)
    return ok
end

local busyPick = false
local function autoPickPhone()
    if busyPick then return end
    busyPick = true

    local phoneFrame = nil
    for _=1,40 do
        phoneFrame = select(1, getPhoneFrame())
        if phoneFrame and chainVisible(phoneFrame) then break end
        task.wait(0.2)
    end
    if not phoneFrame then
        warn("[AUTO-DEVICE] Không thấy Phone frame → fallback remote.")
        fallbackRemote(); busyPick = false; return
    end

    warn(("[AUTO-DEVICE] PhoneFrame=%s class=%s vis=%s")
        :format(phoneFrame:GetFullName(), phoneFrame.ClassName, tostring(chainVisible(phoneFrame))))

    local cands = listClickableDescendants(phoneFrame)
    if #cands == 0 then
        warn("[AUTO-DEVICE] Không tìm thấy nút con trong Phone → fallback remote.")
        fallbackRemote(); busyPick = false; return
    end

    for idx, gui in ipairs(cands) do
        if not gui:IsA("GuiObject") then continue end
        warn(("[AUTO-DEVICE] Thử candidate #%d: %s (%s)")
            :format(idx, gui:GetFullName(), gui.ClassName))
        for i=1,3 do
            if chainVisible(gui) then
                local ok, how = clickAtGuiObject(gui)
                warn(("[AUTO-DEVICE]  -> lần %d: click=%s via %s")
                    :format(i, tostring(ok), how))
                task.wait(0.25)
                local pf = select(1, getPhoneFrame())
                if not pf then
                    warn("[AUTO-DEVICE] DeviceSelect biến mất → ĐÃ CHỌN.")
                    busyPick = false
                    return
                end
            else
                warn("[AUTO-DEVICE]  -> candidate chưa visible, chờ…")
                task.wait(0.2)
            end
        end
    end

    fallbackRemote()
    busyPick = false
end

LP.CharacterAdded:Connect(function()
    task.delay(1.0, autoPickPhone)
end)
if LP.Character then task.delay(1.0, autoPickPhone) end

task.spawn(function()
    local pg = LP:WaitForChild("PlayerGui", 15)
    if pg then
        pg.DescendantAdded:Connect(function(inst)
            local path = inst:GetFullName():lower()
            if path:find("playergui.deviceselect") then
                task.delay(0.1, autoPickPhone)
            end
        end)
    end
end)

-- // === Character safe refs ===
local function getChar()
    local char = LP.Character or LP.CharacterAdded:Wait()
    local hrp  = char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart")
    local hum  = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid")
    return char, hrp, hum
end
local Char, HRP, Humanoid = getChar()
LP.CharacterAdded:Connect(function()
    Char, HRP, Humanoid = getChar()
    -- chọn lại Phone nếu GUI hiện lại
    task.delay(0.5, autoPickPhone)
end)

-- // === Round / Map detect ===
local function findActiveMap()
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:GetAttribute("MapID") and obj:FindFirstChild("CoinContainer") then
            return obj
        end
    end
    return nil
end

local function isRoundLive()
    local ok, inRound = pcall(function()
        local gd = RS:FindFirstChild("GameData")
        local iv = gd and gd:FindFirstChild("InRound")
        return iv and iv.Value
    end)
    if ok and inRound ~= nil then return inRound end

    local m = findActiveMap()
    if not m then return false end
    local cc = m:FindFirstChild("CoinContainer")
    if not cc then return false end
    if #cc:GetChildren() > 0 then return true end
    local t0 = os.clock()
    while os.clock() - t0 < 2 do
        if #cc:GetChildren() > 0 then return true end
        task.wait(0.1)
    end
    return false
end

-- Bạn có thực sự "ở trong" map?
local function isPlayerInMap(mapModel)
    if not (mapModel and Char and HRP) then return false end
    if Char:IsDescendantOf(mapModel) then return true end

    local ok, cf, size = pcall(function()
        return mapModel:GetModelCFrame(), mapModel:GetExtentsSize()
    end)
    if ok and cf and size then
        local half = size * 0.5
        local rel  = cf:PointToObjectSpace(HRP.Position)
        return math.abs(rel.X) <= half.X + 6 and math.abs(rel.Y) <= half.Y + 6 and math.abs(rel.Z) <= half.Z + 6
    end

    if mapModel.PrimaryPart then
        local d = (HRP.Position - mapModel.PrimaryPart.Position).Magnitude
        return d <= 150
    end

    return false
end

-- Chờ đến khi bạn được đặt vào map (không tự tele vào trận người khác)
local function waitUntilYouAreInMap()
    while true do
        local m = findActiveMap()
        if m and isRoundLive() and isPlayerInMap(m) then
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

-- Tween an toàn tránh kick
local function tweenTo(part)
    if not (HRP and part and part.CFrame) then return end
    if Humanoid then Humanoid:ChangeState(Enum.HumanoidStateType.Physics) end
    local d  = (HRP.Position - part.Position).Magnitude
    local t  = math.clamp(d / 25, 0.10, 2.0) -- hơi chậm để safe
    local tw = TweenService:Create(HRP, TweenInfo.new(t, Enum.EasingStyle.Linear), {CFrame = part.CFrame})
    tw:Play()
    tw.Completed:Wait()
end

-- // === Main farm loop ===
task.spawn(function()
    -- delay nhẹ để DeviceSelect xử lý trước
    task.wait(0.5)

    while true do
        -- 1) Ở lobby: chờ cho đến khi CHÍNH BẠN vào map
        local currentMap = waitUntilYouAreInMap()

        -- 2) Farm khi round còn diễn ra & bạn vẫn ở trong map
        while isRoundLive() and currentMap and currentMap.Parent and isPlayerInMap(currentMap) do
            if not (Char and Char.Parent and HRP and HRP.Parent and Humanoid and Humanoid.Parent) then
                Char, HRP, Humanoid = getChar()
            end

            local target = getNearest(currentMap)
            if target then
                tweenTo(target)
                local v = target:FindFirstChild("CoinVisual")
                local t0 = os.clock()
                while isRoundLive() and isPlayerInMap(currentMap) and v and v.Parent and not v:GetAttribute("Collected") do
                    local n = getNearest(currentMap)
                    if n and n ~= target then break end
                    if os.clock() - t0 > 2.5 then break end
                    task.wait(0.05)
                end
            else
                task.wait(0.15)
            end
        end

        -- 3) Round xong hoặc bị kéo khỏi map -> quay lại chờ ở lobby
        task.wait(0.5)
    end
end)

