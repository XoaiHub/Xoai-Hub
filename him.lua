-- Chest Farm (standalone)
-- Giữ nguyên: tìm Chest hợp lệ (ngoài Fog), ưu tiên gần nhất, TTL 10s, bấm Prompt tối đa 10s
-- Không gồm: hop server, UI, noclip, boost/fps, tối ưu đồ hoạ...

repeat task.wait() until game:IsLoaded() and game.Players.LocalPlayer

-- ============== CONFIG ==============
local CONST = {
    FARM_PLACE_ID       = 126509999114328, -- nơi farm
    CHEST_NEW_WINDOW    = 10,              -- chỉ coi chest "mới" trong 10s
    CHEST_TIMEOUT       = 10,              -- bấm prompt tối đa 10s/chest
    SCAN_INTERVAL       = 0.1,             -- chu kỳ quét chest
}

-- ============== SERVICES ==============
local Players = game:GetService("Players")
local lp      = Players.LocalPlayer

-- ============== FOG BOUNDING BOX ==============
local FogCF, FogSize
pcall(function()
    local m = workspace:FindFirstChild("Map")
    local b = m and m:FindFirstChild("Boundaries")
    local f = b and b:FindFirstChild("Fog")
    if f and f.GetBoundingBox then
        FogCF, FogSize = f:GetBoundingBox()
    end
end)

-- ============== HELPERS ==============
local function tpTo(cf)
    local char = lp.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    if not char.PrimaryPart then char.PrimaryPart = hrp end
    pcall(function()
        -- dùng SetPrimaryPartCFrame đúng như bản gốc
        char:SetPrimaryPartCFrame(cf)
    end)
end

local function inFog(pos)
    if not (FogCF and FogSize) then return false end
    local min = FogCF.Position - FogSize/2
    local max = FogCF.Position + FogSize/2
    return (pos.X >= min.X and pos.X <= max.X)
       and (pos.Y >= min.Y and pos.Y <= max.Y)
       and (pos.Z >= min.Z and pos.Z <= max.Z)
end

local chestSeen = {} -- id -> firstSeenTick (TTL 10s)

local function closestChest()
    local hrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end

    local best, bestDist
    local container = workspace:FindFirstChild("Items") or workspace
    for _, v in ipairs(container:GetDescendants()) do
        if v:IsA("Model") and v.Name:find("Chest") and (not v.Name:find("Snow")) then
            local prox = v:FindFirstChild("ProximityInteraction", true) or v:FindFirstChildWhichIsA("ProximityPrompt", true)
            if prox then
                local id = v:GetDebugId()
                if not chestSeen[id] then chestSeen[id] = tick() end
                if (tick() - chestSeen[id]) <= CONST.CHEST_NEW_WINDOW then
                    local p = v:GetPivot().Position
                    if not inFog(p) then
                        local d = (hrp.Position - p).Magnitude
                        if (not best) or d < bestDist then
                            best, bestDist = v, d
                        end
                    end
                end
            else
                chestSeen[v:GetDebugId()] = nil
            end
        end
    end
    return best
end

local function firePrompt(prox)
    if not prox then return end
    if typeof(fireproximityprompt) == "function" then
        fireproximityprompt(prox)
    else
        -- fallback nếu môi trường không có fireproximityprompt
        pcall(function()
            prox.HoldDuration = 0
            prox:InputHoldBegin()
            task.wait(0.05)
            prox:InputHoldEnd()
        end)
    end
end

-- ============== MAIN LOOP ==============
task.spawn(function()
    while task.wait(CONST.SCAN_INTERVAL) do
        if game.PlaceId ~= CONST.FARM_PLACE_ID then
            -- Chỉ chạy ở place farm như bản gốc
            continue
        end

        local chest = closestChest()
        if chest then
            local start = os.time()
            local targetCF = chest:GetPivot() + Vector3.new(0, 2, 0)
            local prox = chest:FindFirstChild("ProximityInteraction", true) or chest:FindFirstChildWhichIsA("ProximityPrompt", true)

            while prox and prox.Parent and (os.time() - start) < CONST.CHEST_TIMEOUT do
                tpTo(targetCF)
                firePrompt(prox)
                task.wait(0.4)
                prox = chest:FindFirstChild("ProximityInteraction", true) or chest:FindFirstChildWhichIsA("ProximityPrompt", true)
            end
            -- timeout thì bỏ qua chest này, vòng sau sẽ tự chọn chest khác (nhờ TTL)
        end
    end
end)
