--[[ 
  Chest + Diamond Farm (multi-chest) + Auto Teleporter + Hop Loop + UI
  - Giữ nguyên: auto teleport vào Teleporter1/2/3 khi đủ người, UI Diamonds, hop server vòng lặp
  - Nhặt chest: tất cả model có "Chest" (trừ "Snow") có ProximityPrompt/ProximityInteraction, ưu tiên ngoài Fog
  - Nhặt Diamond: gọi RS.RemoteEvents.RequestTakeDiamonds
  - Sau khi loot xong -> yêu cầu hop tiếp ngay
  - Farm chính ở place 126509999114328 (có Diamond)
]]]

-- ===================== CONFIG =====================
local Config = {
    FarmPlaceID        = 126509999114328,
    RegionFilterEnabled= false,                      -- bật nếu muốn lọc region
    RegionList         = { "singapore", "tokyo", "us-east" },
    ChestPromptTimeout = 10,                         -- tối đa 10s bấm 1 chest
    WaitDiamondTimeout = 20,                         -- chờ Diamond spawn
    ScanInterval       = 0.2,                        -- chu kỳ quét UI và vòng chính
    HopLoopDelay       = 2,                          -- delay giữa mỗi lần thử hop
    RetryHttpDelay     = 2,                          -- retry khi gọi API server list lỗi
    UIPos              = UDim2.new(0, 80, 0, 100),
}

-- ===================== SERVICES =====================
local Players          = game:GetService("Players")
local LocalPlayer      = Players.LocalPlayer
local StarterGui       = game:GetService("StarterGui")
local TeleportService  = game:GetService("TeleportService")
local HttpService      = game:GetService("HttpService")
local Replicated       = game:GetService("ReplicatedStorage")

-- game objects cụ thể
local Remote = Replicated:WaitForChild("RemoteEvents"):WaitForChild("RequestTakeDiamonds")

-- UI lấy sẵn Diamonds count của game
local Interface = LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("Interface")
local DiamondCount = Interface:WaitForChild("DiamondCount"):WaitForChild("Count")

-- ===================== STATE =====================
local PlaceID       = game.PlaceId
local AllIDs        = {}
local cursor        = ""
local isTeleporting = false
local shouldHop     = true
local requestHopNow = false
local ui            = {}

-- ===================== HELPERS =====================
local function notify(t)
    pcall(function()
        StarterGui:SetCore("SendNotification", { Title = "Notification", Text = tostring(t), Duration = 3 })
    end)
end

local function setStatus(t)
    if ui.status then ui.status.Text = "Status: " .. tostring(t) end
end

local function rainbowStroke(stroke)
    task.spawn(function()
        while task.wait() do
            for hue = 0, 1, 0.01 do
                stroke.Color = Color3.fromHSV(hue, 1, 1)
                task.wait(0.02)
            end
        end
    end)
end

local function hasValue(t, v) for _,x in ipairs(t) do if x == v then return true end end return false end

local function waitCharacter()
    repeat task.wait() until LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
end

local function tpTo(cf)
    local ch = LocalPlayer.Character
    if ch and ch:FindFirstChild("HumanoidRootPart") then
        ch:PivotTo(cf)
    end
end

-- Fog filter (nếu có biến toàn cục FogCF, FogSize trong game)
local function inFog(pos)
    if _G.FogCF then FogCF = _G.FogCF end
    if _G.FogSize then FogSize = _G.FogSize end
    if not (typeof(pos) == "Vector3") then return false end
    if not FogCF or not FogSize then return false end
    local minv = FogCF.Position - FogSize/2
    local maxv = FogCF.Position + FogSize/2
    return (pos.X >= minv.X and pos.Y >= minv.Y and pos.Z >= minv.Z and
            pos.X <= maxv.X and pos.Y <= maxv.Y and pos.Z <= maxv.Z)
end

-- ===================== UI =====================
do
    if game.CoreGui:FindFirstChild("DiamondFarmUI") then
        game.CoreGui.DiamondFarmUI:Destroy()
    end

    local a = Instance.new("ScreenGui")
    a.Name = "DiamondFarmUI"
    a.ResetOnSpawn = false
    a.Parent = game.CoreGui
    ui.root = a

    local frame = Instance.new("Frame", a)
    frame.Size = UDim2.new(0, 240, 0, 110)
    frame.Position = Config.UIPos
    frame.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Draggable = true

    local corner = Instance.new("UICorner", frame)
    corner.CornerRadius = UDim.new(0, 8)

    local stroke = Instance.new("UIStroke", frame)
    stroke.Thickness = 1.5
    rainbowStroke(stroke)

    local title = Instance.new("TextLabel", frame)
    title.Size = UDim2.new(1, 0, 0, 28)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.TextSize = 14
    title.TextColor3 = Color3.new(1,1,1)
    title.Text = "Kaitun 99 night (Chest+Diamond)"

    local status = Instance.new("TextLabel", frame)
    status.Size = UDim2.new(1, -20, 0, 30)
    status.Position = UDim2.new(0, 10, 0, 36)
    status.BackgroundColor3 = Color3.fromRGB(0,0,0)
    status.BorderSizePixel = 0
    status.Font = Enum.Font.GothamBold
    status.TextSize = 14
    status.TextColor3 = Color3.new(1,1,1)
    status.Text = "Status: init..."
    local statusCorner = Instance.new("UICorner", status)
    statusCorner.CornerRadius = UDim.new(0, 6)

    local diamonds = Instance.new("TextLabel", frame)
    diamonds.Size = UDim2.new(1, -20, 0, 24)
    diamonds.Position = UDim2.new(0, 10, 0, 70)
    diamonds.BackgroundTransparency = 1
    diamonds.Font = Enum.Font.Gotham
    diamonds.TextSize = 14
    diamonds.TextColor3 = Color3.new(1,1,1)
    diamonds.Text = "Diamonds: ..."

    ui.status = status
    ui.diamonds = diamonds

    task.spawn(function()
        while task.wait(Config.ScanInterval) do
            pcall(function()
                ui.diamonds.Text = "Diamonds: " .. (DiamondCount and DiamondCount.Text or "?")
            end)
        end
    end)
end

-- ===================== AUTO TELEPORTER 1/2/3 =====================
local function checkTeleporter(obj)
    local g=obj:FindFirstChild("BillboardHolder")
    if g and g:FindFirstChild("BillboardGui") and g.BillboardGui:FindFirstChild("Players") then
        local t=g.BillboardGui.Players.Text
        local x,y=t:match("(%d+)/(%d+)")
        x,y=tonumber(x),tonumber(y)
        if x and y and x>=2 then
            local enter=obj:FindFirstChildWhichIsA("BasePart")
            if enter and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
                local hrp=LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    LocalPlayer.Character.Humanoid:MoveTo(enter.Position)
                    if (hrp.Position - enter.Position).Magnitude>10 then
                        tpTo(enter.CFrame + Vector3.new(0,3,0))
                    end
                end
            end
        end
    end
end

task.spawn(function()
    while task.wait(0.5) do
        for _,obj in ipairs(workspace:GetChildren()) do
            if obj:IsA("Model") and (obj.Name=="Teleporter1" or obj.Name=="Teleporter2" or obj.Name=="Teleporter3") then
                pcall(checkTeleporter, obj)
            end
        end
    end
end)

-- ===================== SERVER LIST & HOP =====================
local function fetchServerPage(nextCursor)
    local url = ("https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Desc&excludeFullGames=true&limit=100%s")
        :format(PlaceID, nextCursor ~= "" and ("&cursor="..nextCursor) or "")
    local ok, data = pcall(function()
        return HttpService:JSONDecode(game:HttpGet(url))
    end)
    if not ok then
        task.wait(Config.RetryHttpDelay)
        return nil
    end
    return data
end

local function regionMatch(serverEntry)
    if not Config.RegionFilterEnabled then return true end
    local raw = tostring(serverEntry.ping or serverEntry.region or ""):lower()
    if raw == "" then return false end
    for _, key in ipairs(Config.RegionList) do
        if string.find(raw, tostring(key):lower(), 1, true) then
            return true
        end
    end
    return false
end

local function tryTeleportOnce()
    local page = fetchServerPage(cursor)
    if not page or not page.data then
        setStatus("Wait hop server, retry...")
        return false
    end
    cursor = (page.nextPageCursor and page.nextPageCursor ~= "null") and page.nextPageCursor or ""
    for _, v in ipairs(page.data) do
        local sid = tostring(v.id)
        if tonumber(v.playing) and tonumber(v.maxPlayers) and tonumber(v.playing) < tonumber(v.maxPlayers) then
            if not hasValue(AllIDs, sid) and regionMatch(v) then
                table.insert(AllIDs, sid)
                setStatus(("Teleport -> %s (%s/%s)"):format(sid, tostring(v.playing), tostring(v.maxPlayers)))
                isTeleporting = true
                pcall(function()
                    TeleportService:TeleportToPlaceInstance(PlaceID, sid, LocalPlayer)
                end)
                task.delay(5, function() isTeleporting = false end) -- nếu fail
                return true
            end
        end
    end
    return false
end

local function TeleportLoop()
    while shouldHop and task.wait(Config.HopLoopDelay) do
        if isTeleporting then continue end

        -- ưu tiên: hop ngay khi đã set cờ sau khi loot xong
        if requestHopNow then
            setStatus("Hop tiếp (sau khi loot xong)...")
            cursor = ""
            if tryTeleportOnce() then
                requestHopNow = false
                continue
            else
                setStatus("Chưa tìm được server trống, thử lại...")
            end
        end

        setStatus("Tìm server...")
        tryTeleportOnce()
    end
end
task.spawn(TeleportLoop)

-- ===================== CHEST / DIAMOND =====================
-- Tìm tất cả chest hợp lệ (không Snow, có prompt, ngoài Fog nếu có Fog)
local function getAllChests()
    local items = workspace:FindFirstChild("Items")
    if not items then return {} end
    local list = {}
    for _, v in ipairs(items:GetDescendants()) do
        if v:IsA("Model") and v.Name:find("Chest") and not v.Name:find("Snow") then
            local prox = v:FindFirstChild("ProximityInteraction", true) or v:FindFirstChildWhichIsA("ProximityPrompt", true)
            if prox then
                local pos = v:GetPivot().Position
                if not inFog(pos) then
                    table.insert(list, v)
                end
            end
        end
    end
    return list
end

local function getClosestChest()
    local ch = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not ch then return nil end
    local hrp = ch
    local best, dist
    for _, v in ipairs(getAllChests()) do
        local p = v:GetPivot().Position
        local d = (hrp.Position - p).Magnitude
        if not dist or d < dist then
            best, dist = v, d
        end
    end
    return best
end

local function findPromptInChest(chest)
    return chest and (chest:FindFirstChild("ProximityInteraction", true) or chest:FindFirstChildWhichIsA("ProximityPrompt", true))
end

local function pressPromptWithTimeout(prompt, timeout)
    local t0 = tick()
    while prompt and prompt.Parent and (tick() - t0) < timeout do
        pcall(function() fireproximityprompt(prompt) end)
        task.wait(0.2)
    end
    return prompt and prompt.Parent == nil
end

local function waitDiamonds(timeout)
    local t0 = tick()
    while (tick() - t0) < timeout do
        local found = workspace:FindFirstChild("Diamond", true)
        if found then return true end
        task.wait(0.2)
    end
    return false
end

local function collectAllDiamondsOnce()
    local count = 0
    for _, v in ipairs(workspace:GetDescendants()) do
        if v.ClassName == "Model" and v.Name == "Diamond" then
            pcall(function()
                Remote:FireServer(v)
                count += 1
            end)
        end
    end
    return count
end

-- ===================== MAIN LOOP =====================
task.spawn(function()
    while true do
        setStatus("Join xong, dò chest...")
        waitCharacter()

        -- Nếu không ở map farm vẫn chạy cơ chế hop/inactivity của loop
        if game.PlaceId ~= Config.FarmPlaceID then
            setStatus("Không ở FarmPlace -> đợi hop...")
            task.wait(2)
            continue
        end

        -- QUÉT & NHẶT TOÀN BỘ CHEST (không chỉ Stronghold)
        while true do
            local chest = getClosestChest()
            if not chest then
                break -- hết chest
            end

            -- tới gần chest
            local piv = chest:GetPivot()
            tpTo(CFrame.new(piv.Position + Vector3.new(0, 3, 0)))
            setStatus("Bấm chest: " .. tostring(chest.Name))

            -- bấm prompt trong tối đa N giây
            local prompt = findPromptInChest(chest)
            if prompt then
                pressPromptWithTimeout(prompt, Config.ChestPromptTimeout)
            end

            -- nếu vẫn còn prompt sau timeout -> bỏ qua chest này
            prompt = findPromptInChest(chest)
            if prompt and prompt.Parent then
                setStatus("Chest timeout, skip -> " .. tostring(chest.Name))
            end

            task.wait(0.3)
        end

        -- CHỜ diamond spawn
        setStatus("Chờ Diamond spawn...")
        if waitDiamonds(Config.WaitDiamondTimeout) then
            setStatus("Nhặt Diamond...")
            local got = collectAllDiamondsOnce()
            task.wait(0.4)
            got = got + collectAllDiamondsOnce()
            notify(("Đã nhặt %d Diamond."):format(got))
        else
            setStatus("Không có Diamond sau chest")
        end

        -- YÊU CẦU HOP TIẾP TỤC
        setStatus("Hoàn tất. Hop tiếp server mới...")
        notify("Đã loot xong. Đang hop server khác...")
        requestHopNow = true

        -- chờ TeleportLoop xử lý teleport
        for _ = 1, 50 do
            if isTeleporting then break end
            task.wait(0.1)
        end

        task.wait(1)
    end
end)
