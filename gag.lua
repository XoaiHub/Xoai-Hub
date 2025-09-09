--========== AutoCrate (HARD-CODED Discord Webhook, realtime config, weapon-only notify) ==========
-- SỬA DÒNG NÀY: Dán link webhook kênh public của server Discord bạn
local WEBHOOK_URL = "https://discord.com/api/webhooks/XXXX/XXXX"

-- Ngưỡng & nhịp
local MinBalls, CheckInterval, AfterOpenWait = 800, 1.0, 1.0
local RecheckStep = 0.10

-- Services
local RS        = game:GetService("ReplicatedStorage")
local Players   = game:GetService("Players")
local HttpSvc   = game:GetService("HttpService")
local LP        = Players.LocalPlayer

-- ====== BOX MAP (đặt tên hiển thị -> tham số server) ======
local BOX_DEFS = {
    ["Mystery Box"]      = { crateId = "Summer2025Box", crateType = "MysteryBox" },
    ["Summer 2025 Box"]  = { crateId = "Summer2025Box", crateType = "MysteryBox" },
}

-- ====== REMOTES ======
local Remotes   = RS:WaitForChild("Remotes")
local Shop      = Remotes:WaitForChild("Shop")
local OpenCrate = Shop:WaitForChild("OpenCrate")
local UseInvoke = (OpenCrate.ClassName == "RemoteFunction")

-- ====== LOG ======
local function log(...)  print("[Crate]", ...) end
local function wlog(...) warn("[Crate]", ...) end

-- ====== UTILS ======
local function trim(s) s = tostring(s or ""); return (s:gsub("^%s+",""):gsub("%s+$","")) end

local function resolve_path(root, dotpath)
    local cur = root
    for part in string.gmatch(dotpath, "[^%.]+") do
        if part == "%UserId%" then part = tostring(LP.UserId) end
        if part == "%Name%"   then part = LP.Name end
        cur = cur and cur:FindFirstChild(part)
        if not cur then return nil end
    end
    return cur
end

local function find_number_value(root, nameHints)
    for _, inst in ipairs(root:GetDescendants()) do
        if inst:IsA("IntValue") or inst:IsA("NumberValue") then
            local n = inst.Name:lower()
            for _, kw in ipairs(nameHints) do
                if n:find(kw) then return inst, "Value" end
            end
        end
        for _, kw in ipairs(nameHints) do
            local att = inst:GetAttribute(kw)
            if type(att) == "number" then
                return inst, ("Attribute:" .. kw)
            end
        end
    end
end

local function find_textlabel_ball()
    local pg = LP:FindFirstChild("PlayerGui")
    if not pg then return nil end
    for _, ui in ipairs(pg:GetDescendants()) do
        if ui:IsA("TextLabel") or ui:IsA("TextButton") then
            local t = (ui.Text or ""):lower()
            if t:find("ball") or t:find("beach") then
                return ui
            end
        end
    end
end

-- ====== CURRENCY DETECTOR ======
local currencyGetter, currencySourceDesc
local function install_currency_getter()
    local path = rawget(getgenv(), "CurrencyPath")
    if type(path) == "string" and #trim(path) > 0 then
        local root = game
        local first = path:match("^[^%.]+")
        if first == "ReplicatedStorage" then root = RS end
        if first == "Players" then root = Players end
        if first == "LocalPlayer" or first == "Player" then root = LP; path = path:gsub("^[^%.]+%.","") end
        local inst = resolve_path(root, path)
        if inst then
            if inst:IsA("IntValue") or inst:IsA("NumberValue") then
                currencyGetter = function() return inst.Value end
                currencySourceDesc = inst:GetFullName()
                log("Currency via Value:", currencySourceDesc); return true
            else
                wlog("CurrencyPath không phải Int/NumberValue:", inst.ClassName)
            end
        else
            wlog("Không resolve được CurrencyPath:", path)
        end
    end

    local hints = {"beachballs2025","beachballs","beachball","balls","ball","beach"}
    local holder, how = find_number_value(LP, hints)
    if not holder then holder, how = find_number_value(RS, hints) end
    if holder then
        if how == "Value" then
            currencyGetter = function() return holder.Value end
            currencySourceDesc = holder:GetFullName()
            log("Currency via Value:", currencySourceDesc); return true
        else
            local att = how:match("Attribute:(.+)")
            currencyGetter = function() return tonumber(holder:GetAttribute(att)) end
            currencySourceDesc = holder:GetFullName() .. "@" .. how
            log("Currency via Attribute:", currencySourceDesc); return true
        end
    end

    local tl = find_textlabel_ball()
    if tl then
        currencyGetter = function()
            local t = tl.Text or ""
            local num = tonumber((t:gsub("[^%d]", "")))
            return num or 0
        end
        currencySourceDesc = tl:GetFullName() .. " (UI parse)"
        log("Currency via UI:", currencySourceDesc); return true
    end
    return false
end

assert(install_currency_getter(), "Không tìm thấy nơi đọc ball. Hãy set getgenv().CurrencyPath đúng nếu cần.")

local function Balls()
    local ok, val = pcall(currencyGetter)
    if not ok then return 0 end
    return tonumber(val or 0) or 0
end

-- ====== GLOBAL ENABLE (tùy chọn) ======
if getgenv().AutoCrateEnabled == nil then
    getgenv().AutoCrateEnabled = true
end

-- ====== CONFIG ACCESS ======
-- YÊU CẦU: bạn cấu hình ngoài như sau (ví dụ):
-- getgenv().Config = {
--   ["Mystery Box"]      = true,
--   DISCORD_ID           = "1039...",  -- rỗng = không ping
--   WEBHOOK_NOTE         = "Main Account",
--   SHOW_WEBHOOK_USERNAME= true,
--   SHOW_WEBHOOK_JOBID   = true,
-- }
local function CFG() return rawget(getgenv(), "Config") end

local function boxEnabled(name)
    local cfg = CFG()
    return (getgenv().AutoCrateEnabled == true)
        and (type(cfg) == "table")
        and (cfg[name] == true)
end

-- ====== HTTP REQUEST COMPAT ======
local function http_request_compat(tbl)
    local f = (syn and syn.request) or (http and http.request) or http_request or request
    if f then return f(tbl) end
    return nil
end

-- ====== WEBHOOK CORE (hardcoded URL) ======
local lastSendAt = 0
local function canSend(minInterval)
    return (tick() - lastSendAt) >= (minInterval or 1.3)
end

local function fmtNumber(n)
    n = tonumber(n) or 0
    local s = tostring(math.floor(n))
    return s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

local function readWebhookConfig()
    local cfg = CFG() or {}
    return {
        DISCORD_ID            = trim(cfg.DISCORD_ID or ""),
        WEBHOOK_NOTE          = trim(cfg.WEBHOOK_NOTE or ""),
        SHOW_WEBHOOK_USERNAME = (cfg.SHOW_WEBHOOK_USERNAME ~= false),
        SHOW_WEBHOOK_JOBID    = (cfg.SHOW_WEBHOOK_JOBID == true),
    }
end

local function buildEmbed(title, desc)
    local e = {
        title = title,
        description = desc,
        fields = {
            { name = "Player", value = ("`%s` (ID %s)"):format(LP.Name, tostring(LP.UserId)), inline = true },
        },
        timestamp = DateTime.now():ToIsoDate(),
    }
    local cfg = readWebhookConfig()
    if cfg.SHOW_WEBHOOK_JOBID then
        table.insert(e.fields, 2, { name = "JobId", value = ("`%s`"):format(game.JobId or "N/A"), inline = true })
    end
    if cfg.WEBHOOK_NOTE ~= "" then
        table.insert(e.fields, { name = "Note", value = cfg.WEBHOOK_NOTE, inline = false })
    end
    return { e }
end

local function sendDiscord(content, embeds)
    local url = trim(WEBHOOK_URL)
    if url == "" then return end                 -- nếu bạn muốn luôn gửi, giữ URL khác rỗng
    if not canSend(1.3) then return end

    local cfg = readWebhookConfig()
    local payload = {
        content  = content,
        username = (cfg.SHOW_WEBHOOK_USERNAME and LP.Name) or "Crate Logger",
        embeds   = embeds,
        allowed_mentions = { parse = {"users"} },
    }
    local ok, body = pcall(function() return HttpSvc:JSONEncode(payload) end)
    if not ok then return end

    http_request_compat({
        Url = url, Method = "POST",
        Headers = { ["Content-Type"] = "application/json" },
        Body = body,
    })
    lastSendAt = tick()
end

-- ====== PHÁT HIỆN “VŨ KHÍ” TỪ KẾT QUẢ MỞ BOX ======
local function extractDropInfo(ret)
    -- Tùy game, cố gắng đọc:
    -- { Name="...", Rarity="...", Type="Weapon", Weight=... }
    if type(ret) ~= "table" then return nil end
    local name   = ret.Name or ret.ItemName or ret.WeaponName or ret.PetName
    local rarity = ret.Rarity or ret.Tier or ret.Grade
    local wtype  = ret.Type or ret.Category or ret.ItemType
    local weight = ret.Weight or ret.PetWeight or ret.RarityWeight or ret.RarityValue

    local isWeapon = false
    local t = tostring(wtype or ""):lower()
    if t:find("weapon") or t:find("gun") or t:find("knife") or t:find("blade") then
        isWeapon = true
    end
    local n = tostring(name or ""):lower()
    if (not isWeapon) and (#n > 0) then
        if n:find("knife") or n:find("gun") or n:find("sheriff") or n:find("blade") then
            isWeapon = true
        end
    end

    if not name then return nil end
    return {
        Name   = name,
        Rarity = rarity,
        Weight = weight,
        IsWeapon = isWeapon
    }
end

local function notifyWeapon(drop, beforeBalls, afterBalls, boxName)
    if not drop or not drop.IsWeapon then return end
    local cfg = readWebhookConfig()

    local lines = {}
    table.insert(lines, ("Item: **%s**"):format(drop.Name))
    if drop.Rarity then table.insert(lines, ("Rarity: **%s**"):format(tostring(drop.Rarity))) end
    if drop.Weight then table.insert(lines, ("Weight: **%s**"):format(tostring(drop.Weight))) end
    if boxName then table.insert(lines, ("Box: **%s**"):format(boxName)) end
    table.insert(lines, ("Balls: **%s → %s**"):format(fmtNumber(beforeBalls), fmtNumber(afterBalls)))

    local embeds = buildEmbed("🎉 WEAPON DROPPED!", table.concat(lines, " | "))
    local mention = (cfg.DISCORD_ID ~= "") and ("<@"..cfg.DISCORD_ID.."> ") or ""
    sendDiscord(mention .. "Vừa ra vũ khí!", embeds)
end

-- ====== OPEN WRAPPER ======
local function openOne(displayName)
    local def = BOX_DEFS[displayName]; if not def then return false end

    local before = Balls()
    local args   = { def.crateId, def.crateType, "BeachBalls2025" }

    local ok, ret = pcall(function()
        if UseInvoke then
            return OpenCrate:InvokeServer(unpack(args))
        else
            OpenCrate:FireServer(unpack(args))
            return true
        end
    end)

    local after = Balls()
    if ok then
        -- Thử lấy thông tin drop (nếu server trả table)
        local dropInfo = (type(ret)=="table") and extractDropInfo(ret) or nil
        if dropInfo then
            notifyWeapon(dropInfo, before, after, displayName)
        end
        log(("Opened: %s | Balls %s -> %s"):format(displayName, before, after))
        return true
    else
        wlog("Open error:", ret)
        -- lỗi mở thì không gửi weapon (chỉ gửi khi có weapon)
        return false
    end
end

-- ====== MAIN LOOP ======
task.spawn(function()
    log("OpenCrate:", OpenCrate.ClassName, "| Currency source:", currencySourceDesc)
    while true do
        task.wait(CheckInterval)

        if getgenv().AutoCrateEnabled ~= true then
            continue
        end

        local cfg = CFG()
        if type(cfg) ~= "table" then continue end

        if Balls() < MinBalls then continue end

        for name, on in pairs(cfg) do
            if on == true and BOX_DEFS[name] then
                while boxEnabled(name) and Balls() >= MinBalls do
                    if not openOne(name) then break end

                    local elapsed = 0
                    while elapsed < AfterOpenWait do
                        if not boxEnabled(name) then break end
                        if getgenv().AutoCrateEnabled ~= true then break end
                        if Balls() < MinBalls then break end
                        task.wait(RecheckStep)
                        elapsed += RecheckStep
                    end
                end
            end
        end
    end
end)
--============================== end =================================
