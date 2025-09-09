--========== AutoCrate (final, realtime-config + autodetect currency, hard-stop aware) ==========
local MinBalls, CheckInterval, AfterOpenWait = 800, 1.0, 1.0  -- AfterOpenWait ngắn để phản ứng nhanh khi tắt
local RecheckStep = 0.10                                      -- bước kiểm tra nhỏ để dừng ngay khi bạn set false

local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LP = Players.LocalPlayer

-- Map hiển thị -> tham số server
local BOX_DEFS = {
    ["Mystery Box"]     = { crateId = "Summer2025Box", crateType = "MysteryBox" },
    ["Summer 2025 Box"] = { crateId = "Summer2025Box", crateType = "MysteryBox" },
}

local Remotes   = RS:WaitForChild("Remotes")
local Shop      = Remotes:WaitForChild("Shop")
local OpenCrate = Shop:WaitForChild("OpenCrate")
local UseInvoke = (OpenCrate.ClassName == "RemoteFunction")

-- ------------------- log helpers -------------------
local function log(...) print("[Crate]", ...) end
local function wlog(...) warn("[Crate]", ...) end

-- ------------------- path helpers -------------------
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

-- ------------------- currency detector -------------------
local currencyGetter, currencySourceDesc

local function install_currency_getter()
    -- 1) Ưu tiên đường dẫn do user chỉ định
    local path = rawget(getgenv(), "CurrencyPath")
    if type(path) == "string" and #path > 0 then
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
                log("Currency via Value:", currencySourceDesc)
                return true
            else
                wlog("CurrencyPath không phải Int/NumberValue:", inst.ClassName)
            end
        else
            wlog("Không resolve được CurrencyPath:", path)
        end
    end

    -- 2) Quét LP rồi tới RS
    local hints = {"beachballs2025","beachballs","beachball","balls","ball","beach"}
    local holder, how = find_number_value(LP, hints)
    if not holder then holder, how = find_number_value(RS, hints) end
    if holder then
        if how == "Value" then
            currencyGetter = function() return holder.Value end
            currencySourceDesc = holder:GetFullName()
            log("Currency via Value:", currencySourceDesc)
            return true
        else
            local att = how:match("Attribute:(.+)")
            currencyGetter = function() return tonumber(holder:GetAttribute(att)) end
            currencySourceDesc = holder:GetFullName() .. "@" .. how
            log("Currency via Attribute:", currencySourceDesc)
            return true
        end
    end

    -- 3) Fallback từ UI text
    local tl = find_textlabel_ball()
    if tl then
        currencyGetter = function()
            local t = tl.Text or ""
            local num = tonumber((t:gsub("[^%d]", "")))
            return num or 0
        end
        currencySourceDesc = tl:GetFullName() .. " (UI parse)"
        log("Currency via UI:", currencySourceDesc)
        return true
    end

    return false
end

assert(install_currency_getter(), "Không tìm thấy nơi đọc ball. Hãy set getgenv().CurrencyPath đúng nếu cần.")

-- ------------------- helpers -------------------
local function Balls()
    local ok, val = pcall(currencyGetter)
    if not ok then return 0 end
    return tonumber(val or 0) or 0
end

-- Bật/tắt toàn cục: mặc định true nếu bạn không set.
if getgenv().AutoCrateEnabled == nil then
    getgenv().AutoCrateEnabled = true
end

local function isEnabled(boxName)
    local CFG = rawget(getgenv(), "Config")
    return (getgenv().AutoCrateEnabled == true)
        and (type(CFG) == "table")
        and (CFG[boxName] == true)
end

local function openOne(displayName)
    local def = BOX_DEFS[displayName]; if not def then return false end
    local args = { def.crateId, def.crateType, "BeachBalls2025" } -- tên currency server-side
    local ok, ret = pcall(function()
        if UseInvoke then
            return OpenCrate:InvokeServer(unpack(args))
        else
            OpenCrate:FireServer(unpack(args))
            return true
        end
    end)
    if ok then log("Opened:", displayName) else wlog("Open error:", ret) end
    return ok
end

-- ------------------- main loop -------------------
task.spawn(function()
    log("OpenCrate:", OpenCrate.ClassName, "| Currency source:", currencySourceDesc)
    while true do
        task.wait(CheckInterval)

        -- Nếu tắt toàn cục => bỏ qua mọi thứ
        if getgenv().AutoCrateEnabled ~= true then
            -- chờ ngắn để giảm CPU nhưng vẫn phản ứng nhanh nếu bật lại
            continue
        end

        local CFG = rawget(getgenv(), "Config")
        if type(CFG) ~= "table" then continue end

        -- Chỉ khi đủ balls mới xét mở
        if Balls() < MinBalls then continue end

        -- Duyệt các box được bật trong Config
        for name, on in pairs(CFG) do
            if on == true and BOX_DEFS[name] then
                -- Vòng mở: mỗi lần mở xong đều RECHECK ngay để tắt kịp thời
                while isEnabled(name) and Balls() >= MinBalls do
                    if not openOne(name) then break end

                    -- Thời gian đợi sau khi gọi mở (server trừ balls, animation, vv.)
                    -- Chia nhỏ thành các "bước" để nếu bạn set false giữa chừng sẽ dừng ngay.
                    local elapsed = 0
                    while elapsed < AfterOpenWait do
                        if not isEnabled(name) then break end
                        if getgenv().AutoCrateEnabled ~= true then break end
                        -- Nếu đã tụt xuống dưới ngưỡng thì thôi
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

