-- ===================== Auto Open Mystery Box (Balls >= 800) =====================
-- Luôn GỬI WEBHOOK PUBLIC về server (link gắn cứng trong code)
-- Giữ nguyên cấu hình theo yêu cầu của bạn: getgenv().Config = { ... }

-- >>>>>>> THAY LINK WEBHOOK CỦA BẠN TẠI ĐÂY <<<<<<<
local WEBHOOK_URL = "https://discord.com/api/webhooks/1414772367930163270/Zhd2kiXZY2Bf0km8rH1Shr8Zf-ce9biX2aLtoWQ5pbzb8GrZHFTYFR_IFlcKCeLK60ob"

-- ========================== Không chỉnh bên dưới ===============================
local MIN_BALLS        = 800
local CHECK_INTERVAL   = 1.25
local OPEN_COOLDOWN    = 2.0

local Players          = game:GetService("Players")
local RS               = game:GetService("ReplicatedStorage")
local HttpService      = game:GetService("HttpService")

local LP               = Players.LocalPlayer
local Remotes          = RS:WaitForChild("Remotes")
local Shop             = Remotes:WaitForChild("Shop")
local OpenCrate        = Shop:WaitForChild("OpenCrate")
local UseInvoke        = (OpenCrate.ClassName == "RemoteFunction")

-- Args đúng theo bạn đưa
local OPEN_ARGS = {
    "Summer2025Box",   -- crateId
    "MysteryBox",      -- crateType
    "BeachBalls2025",  -- currency name
}

-- ======= Config mặc định (nếu bạn quên set từ ngoài) =======
getgenv().Config = getgenv().Config or {
    ["Mystery Box"]       = true,
    DISCORD_ID            = "",
    WEBHOOK_NOTE          = "AutoCrate MM2",
    SHOW_WEBHOOK_USERNAME = true,
    SHOW_WEBHOOK_JOBID    = true,
}

-- ========================= Helpers =========================
local function now() return os.clock() end

local function bool(v)
    return not not v
end

local function getJobId()
    local jid = game.JobId or ""
    if jid == "" then
        -- Private server đôi khi JobId rỗng
        pcall(function() jid = (game:GetService("TeleportService"):GetLocalPlayerTeleportData() or {})._jobid or "" end)
    end
    return jid
end

local function mentionStr()
    local id = tostring(getgenv().Config.DISCORD_ID or "")
    if id ~= "" and id ~= " " then
        return "<@" .. id .. ">"
    end
    return ""
end

local function sendWebhook(eventName, description, fieldsKV, colorInt)
    if type(WEBHOOK_URL) ~= "string" or not WEBHOOK_URL:find("https://") then
        return -- không có webhook hợp lệ thì bỏ qua
    end

    local cfg = getgenv().Config
    local username = "MM2 AutoCrate"
    if bool(cfg.SHOW_WEBHOOK_USERNAME) then
        pcall(function()
            local uname = LP and LP.Name or "Player"
            username = ("AutoCrate | %s"):format(uname)
        end)
    end

    local footerText = "Auto Open Mystery Box"
    if bool(cfg.SHOW_WEBHOOK_JOBID) then
        footerText = footerText .. " | JobId: " .. tostring(getJobId())
    end

    local fields = {}
    if type(fieldsKV) == "table" then
        for k, v in pairs(fieldsKV) do
            table.insert(fields, { name = tostring(k), value = tostring(v), inline = true })
        end
    end

    local contentPrefix = mentionStr()
    local note = tostring(cfg.WEBHOOK_NOTE or "")
    if note ~= "" and note ~= " " then
        contentPrefix = (contentPrefix ~= "" and (contentPrefix .. " | ") or "") .. note
    end

    local payload = {
        content = contentPrefix ~= "" and contentPrefix or nil,
        username = username,
        embeds = {
            {
                title = eventName or "AutoCrate",
                description = description or "",
                color = colorInt or 0x00A3FF,
                fields = fields,
                footer = { text = footerText },
                timestamp = DateTime.now():ToIsoDate()
            }
        }
    }

    local ok, _ = pcall(function()
        HttpService:RequestAsync({
            Url = WEBHOOK_URL,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode(payload)
        })
    end)
    return ok
end

-- Tìm số Balls qua nhiều đường: leaderstats / Value objects / GUI text
local function parseInt(s)
    if not s then return nil end
    s = tostring(s)
    s = s:gsub(",", ""):gsub("%.", ""):gsub("%s+", "")
    local n = tonumber(s)
    return n
end

local function readFromLeaderstats()
    local ok, val = pcall(function()
        local ls = LP:FindFirstChild("leaderstats")
        if not ls then return nil end
        for _, ch in ipairs(ls:GetChildren()) do
            local n
            -- Ưu tiên các tên liên quan Balls
            local nm = string.lower(ch.Name)
            if nm:find("ball") or nm:find("beach") then
                if ch:IsA("NumberValue") or ch:IsA("IntValue") then
                    n = ch.Value
                elseif ch:IsA("StringValue") then
                    n = parseInt(ch.Value)
                end
                if n then return n end
            end
        end
        -- fallback: tìm bất kỳ NumberValue có vẻ là balls
        for _, ch in ipairs(ls:GetChildren()) do
            if ch:IsA("NumberValue") or ch:IsA("IntValue") then
                if string.lower(ch.Name):find("2025") then
                    return ch.Value
                end
            end
        end
        return nil
    end)
    return ok and val or nil
end

local function readFromValues()
    -- đôi khi game để currency ở Player / PlayerData / DataModel Children
    local candidates = { LP }
    local function scan(obj)
        for _, ch in ipairs(obj:GetChildren()) do
            local nm = string.lower(ch.Name)
            if (ch:IsA("NumberValue") or ch:IsA("IntValue") or ch:IsA("StringValue")) and (nm:find("ball") or nm:find("beach") or nm:find("2025")) then
                if ch:IsA("StringValue") then
                    local v = parseInt(ch.Value)
                    if v then return v end
                else
                    return ch.Value
                end
            end
            local v = scan(ch)
            if v then return v end
        end
        return nil
    end
    for _, o in ipairs(candidates) do
        local v = scan(o)
        if v then return v end
    end
    return nil
end

local function readFromGUI()
    local ok, val = pcall(function()
        local pg = LP:FindFirstChild("PlayerGui")
        if not pg then return nil end
        local function scanGui(obj)
            for _, ch in ipairs(obj:GetChildren()) do
                if ch:IsA("TextLabel") or ch:IsA("TextButton") or ch:IsA("TextBox") then
                    local t = string.lower(ch.Text or "")
                    if t:find("ball") then
                        -- tìm số trong dòng text
                        local num = ch.Text:gsub(",", "")
                        num = num:match("(%d+)")
                        if num then
                            local n = tonumber(num)
                            if n then return n end
                        end
                    end
                end
                local v = scanGui(ch)
                if v then return v end
            end
            return nil
        end
        return scanGui(pg)
    end)
    return ok and val or nil
end

local function getBalls()
    return readFromLeaderstats() or readFromValues() or readFromGUI() or 0
end

-- ========================= Open logic =========================
local isOpening = false
local lastOpen  = 0

local function canOpen()
    if not bool(getgenv().Config["Mystery Box"]) then return false, "Config tắt" end
    if isOpening then return false, "Đang mở..." end
    if (now() - lastOpen) < OPEN_COOLDOWN then return false, "Cooldown" end

    local balls = tonumber(getBalls()) or 0
    if balls < MIN_BALLS then
        return false, ("Balls %d/%d"):format(balls, MIN_BALLS)
    end
    return true
end

local function tryOpenOnce()
    local ok, reason = canOpen()
    if not ok then return false, reason end

    isOpening = true
    lastOpen  = now()

    sendWebhook(
        "Bắt đầu mở Mystery Box",
        "Đang gửi OpenCrate...",
        { ["Crate"] = OPEN_ARGS[1] .. " / " .. OPEN_ARGS[2], ["Currency"] = OPEN_ARGS[3], ["Balls"] = tostring(getBalls()) },
        0x2ECC71
    )

    local success, result = pcall(function()
        if UseInvoke then
            return OpenCrate:InvokeServer(unpack(OPEN_ARGS))
        else
            OpenCrate:FireServer(unpack(OPEN_ARGS))
            return true
        end
    end)

    isOpening = false

    if success then
        sendWebhook(
            "Mở Mystery Box: THÀNH CÔNG",
            "InvokeServer/FireServer thành công.",
            { ["Crate"] = OPEN_ARGS[1], ["Type"] = OPEN_ARGS[2], ["Currency"] = OPEN_ARGS[3], ["Balls(Sau)"] = tostring(getBalls()) },
            0x00A3FF
        )
        return true
    else
        sendWebhook(
            "Mở Mystery Box: LỖI",
            tostring(result),
            { ["Crate"] = OPEN_ARGS[1], ["Type"] = OPEN_ARGS[2] },
            0xE74C3C
        )
        return false, tostring(result)
    end
end

-- ========================= Main loop =========================
task.spawn(function()
    -- Ping webhook một lần để biết script đã chạy
    sendWebhook(
        "AutoCrate đã khởi động",
        "Sẽ tự mở khi Balls >= 800 và config bật.",
        { ["MinBalls"] = tostring(MIN_BALLS), ["CheckInterval"] = tostring(CHECK_INTERVAL) },
        0x7289DA
    )

    while true do
        local ok, reason = tryOpenOnce()
        -- Nếu không đủ điều kiện, chỉ log nhẹ; vòng lặp sẽ thử lại
        if not ok and reason then
            -- print("[AutoCrate] Skip:", reason)
        end
        task.wait(CHECK_INTERVAL)
    end
end)

