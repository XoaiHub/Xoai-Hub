-- Auto Teleport 1/2/3
local Players=game:GetService("Players")
local lp=Players.LocalPlayer

local function tpTo(cf)
    if lp.Character and lp.Character:FindFirstChild("HumanoidRootPart") then
        lp.Character:SetPrimaryPartCFrame(cf)
    end
end

local function checkTeleporter(obj)
    local g=obj:FindFirstChild("BillboardHolder")
    if g and g:FindFirstChild("BillboardGui") and g.BillboardGui:FindFirstChild("Players") then
        local t=g.BillboardGui.Players.Text
        local x,y=t:match("(%d+)/(%d+)")
        x,y=tonumber(x),tonumber(y)
        if x and y and x>=2 then
            local enter=obj:FindFirstChildWhichIsA("BasePart")
            if enter and lp.Character and lp.Character:FindFirstChild("Humanoid") then
                local hrp=lp.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local dir=(enter.Position-hrp.Position).Unit
                    lp.Character.Humanoid:MoveTo(enter.Position)
                    if(hrp.Position-enter.Position).Magnitude>10 then
                        tpTo(enter.CFrame+Vector3.new(0,3,0))
                    end
                end
            end
        end
    end
end

spawn(function()
    while task.wait(0.5) do
        for _,obj in ipairs(workspace:GetChildren()) do
            if obj:IsA("Model") and(obj.Name=="Teleporter1"or obj.Name=="Teleporter2"or obj.Name=="Teleporter3") then
                checkTeleporter(obj)
            end
        end
    end
end)

--// ===================== CONFIG =====================
local Config = {
    RegionFilterEnabled = false,
    RegionList = { "singapore", "tokyo", "us-east" },
    MaxPromptTime = 10,
    WaitDiamondTimeout = 20,
    UIScanInterval = 0.2,
    RetryHttpDelay = 2,
    HopLoopDelay = 2,
    ChestName = "Stronghold Diamond Chest",

    -- ==== ADD: Diamond Farm ====
    FarmPlaceId = 126509999114328, -- nơi farm gems/diamond
    DiamondScanInterval = 0.1,     -- chu kỳ quét diamond
    DiamondTPYOffset = 2,          -- TP đứng hơi trên viên diamond
    DiamondTPDistance = 150,       -- chỉ TP nếu xa hơn ngưỡng này
}

--// ===================== SERVICES =====================
local Players          = game:GetService("Players")
local LocalPlayer      = Players.LocalPlayer
local StarterGui       = game:GetService("StarterGui")
local TeleportService  = game:GetService("TeleportService")
local HttpService      = game:GetService("HttpService")
local Replicated       = game:GetService("ReplicatedStorage")

-- các object game cụ thể
local Remote = Replicated:WaitForChild("RemoteEvents"):WaitForChild("RequestTakeDiamonds")

local Interface = LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("Interface")
local DiamondCount = Interface:WaitForChild("DiamondCount"):WaitForChild("Count")

--// ===================== STATE =====================
local PlaceID = game.PlaceId
local AllIDs = {}
local cursor = ""
local isTeleporting = false
local shouldHop = true
local requestHopNow = false
local ui = {}

-- CỜ dùng chung để Diamond Farm né lúc đang thao tác chest
local __CHEST_BUSY = false

--// ===================== UTILS =====================
local function notify(t)
    pcall(function()
        StarterGui:SetCore("SendNotification", { Title = "Notification", Text = tostring(t), Duration = 3 })
    end)
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

--// ===================== UI =====================
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
    frame.Size = UDim2.new(0, 220, 0, 100)
    frame.Position = UDim2.new(0, 80, 0, 100)
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
    title.Text = "Kaitun 99 night"

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
        while task.wait(Config.UIScanInterval) do
            pcall(function()
                ui.diamonds.Text = "Diamonds: " .. (DiamondCount and DiamondCount.Text or "?")
            end)
        end
    end)
end

local function setStatus(t)
    if ui.status then ui.status.Text = "Status: " .. tostring(t) end
end

--// ===================== SERVER LIST & TELEPORT =====================
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
                task.delay(5, function() isTeleporting = false end)
                return true
            end
        end
    end
    return false
end

local function TeleportLoop()
    while shouldHop and task.wait(Config.HopLoopDelay) do
        if isTeleporting then continue end

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

--// ===================== CHEST / DIAMOND FLOW =====================
local function waitCharacter()
    repeat task.wait() until LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
end

local function findChest()
    local items = workspace:FindFirstChild("Items")
    if not items then return nil end
    return items:FindFirstChild(Config.ChestName)
end

local function pressPromptWithTimeout(prompt, timeout)
    local t0 = tick()
    while prompt and prompt.Parent and (tick() - t0) < timeout do
        pcall(function() fireproximityprompt(prompt) end)
        task.wait(0.2)
    end
    return prompt and prompt.Parent == nil
end

local function findProximityPromptInChest(chest)
    local main = chest and chest:FindFirstChild("Main")
    if not main then return nil end
    local attach = main:FindFirstChild("ProximityAttachment")
    if not attach then return nil end
    return attach:FindFirstChild("ProximityInteraction")
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

local function collectAllDiamonds()
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

--// ===================== MAIN LOOP =====================
task.spawn(function()
    while true do
        setStatus("Join xong, dò chest...")
        waitCharacter()

        local chest = findChest()
        if not chest then
            setStatus("Không thấy chest -> hop")
            notify("Chest không có, đang hop server...")
            task.wait(0.5)
            task.wait(3)
            continue
        end

        -- Di chuyển đến chest
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if hrp then
            local piv = chest:GetPivot()
            __CHEST_BUSY = true
            LocalPlayer.Character:PivotTo(CFrame.new(piv.Position + Vector3.new(0, 3, 0)))
        end

        -- Tìm prompt & bấm
        setStatus("Tìm prompt & bấm...")
        local prompt = findProximityPromptInChest(chest)
        if prompt then
            pressPromptWithTimeout(prompt, Config.MaxPromptTime)
        end

        -- Nếu prompt vẫn còn -> stronghold đang chạy, hop tiếp
        prompt = findProximityPromptInChest(chest)
        if prompt and prompt.Parent then
            __CHEST_BUSY = false
            setStatus("Stronghold đang chạy -> hop")
            notify("Stronghold đang chạy, hop server khác...")
            task.wait(0.5)
            continue
        end

        -- Chờ diamonds spawn
        setStatus("Chờ Diamond spawn...")
        if not waitDiamonds(Config.WaitDiamondTimeout) then
            __CHEST_BUSY = false
            setStatus("Không có Diamond -> hop")
            notify("Không thấy Diamond, hop server...")
            task.wait(0.5)
            continue
        end

        -- Nhặt tất cả diamonds
        setStatus("Nhặt Diamond...")
        local got = collectAllDiamonds()
        notify(("Đã nhặt %d Diamond (gọi Remote)."):format(got))

        task.wait(0.5)
        got = got + collectAllDiamonds()

        -- xong lượt này -> hop tiếp
        __CHEST_BUSY = false
        setStatus("Hoàn tất. Hop tiếp server mới...")
        notify("Đã nhặt xong. Đang hop tiếp server khác...")

        requestHopNow = true
        for i = 1, 50 do
            if isTeleporting then break end
            task.wait(0.1)
        end

        task.wait(1)
    end
end)

--// ===================== (ADDED) DIAMOND FARM BACKGROUND =====================
-- Giữ nguyên tính năng khác; chỉ thêm luồng farm Diamond quét nhanh + TP tới từng viên như yêu cầu.
task.spawn(function()
    repeat task.wait() until game:IsLoaded() and Players.LocalPlayer
    while task.wait(Config.DiamondScanInterval) do
        if game.PlaceId ~= Config.FarmPlaceId then
            continue
        end
        -- Né lúc đang bấm chest/đợi chest để không kéo nhân vật đi
        if __CHEST_BUSY or isTeleporting then
            continue
        end

        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")

        for _, d in ipairs(workspace:GetDescendants()) do
            if d:IsA("Model") and d.Name == "Diamond" then
                -- TP gần nếu xa; sau đó FireServer
                local ok, piv = pcall(function() return d:GetPivot() end)
                if ok and piv and char and hrp then
                    local dist = (hrp.Position - piv.Position).Magnitude
                    if dist > Config.DiamondTPDistance then
                        pcall(function()
                            char:PivotTo(CFrame.new(piv.Position + Vector3.new(0, Config.DiamondTPYOffset, 0)))
                        end)
                    end
                end
                pcall(function()
                    Remote:FireServer(d)
                end)
                warn("collect kc")
                task.wait(0.05) -- nhỏ giọt để tránh spam quá nhanh
            end
        end
    end
end)

