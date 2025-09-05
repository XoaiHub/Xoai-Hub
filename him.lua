--// ================= AUTO CHỌN "Phone" KHI VÀO GAME =================
local g  = game
local RS = g:GetService("ReplicatedStorage")
local Players = g:GetService("Players")
local LP = Players.LocalPlayer

local DEVICE = "Phone"
local isTrying = false

local function findRemote(timeout)
    local t0 = tick()
    local function _search(scope)
        local cand = scope:FindFirstChild("ChangeLastDevice", true)
        if cand and (cand:IsA("RemoteEvent") or cand:IsA("RemoteFunction")) then
            return cand
        end
        return nil
    end
    repeat
        -- Ưu tiên tìm trong ReplicatedStorage, nếu không có thì quét toàn game
        local r = _search(RS) or _search(g)
        if r then return r end
        task.wait(0.2)
    until timeout and (tick() - t0) > timeout
    return nil
end

local function sendSelect(remote)
    if not remote then return false, "remote_nil" end
    local ok, res
    if remote:IsA("RemoteEvent") then
        ok, res = pcall(function()
            remote:FireServer(DEVICE)
        end)
    elseif remote:IsA("RemoteFunction") then
        ok, res = pcall(function()
            return remote:InvokeServer(DEVICE)
        end)
    else
        return false, "wrong_class_" .. remote.ClassName
    end
    return ok, res
end

local function trySelect()
    if isTrying then return end
    isTrying = true

    -- Tìm remote (đợi tối đa 10s)
    local remote = RS:FindFirstChild("Remotes") and RS.Remotes:FindFirstChild("Extras") and RS.Remotes.Extras:FindFirstChild("ChangeLastDevice")
    if not (remote and (remote:IsA("RemoteEvent") or remote:IsA("RemoteFunction"))) then
        remote = findRemote(10)
    end

    if not remote then
        warn("[AUTO-DEVICE] Không tìm thấy Remote ChangeLastDevice sau 10s, sẽ tiếp tục nghe sự kiện xuất hiện.")
        isTrying = false
        return
    end

    -- Gửi nhiều lần có backoff phòng server/UI chưa sẵn sàng
    for i = 1, 5 do
        local ok, err = sendSelect(remote)
        if ok then
            warn(("[AUTO-DEVICE] Đã chọn thiết bị '%s' qua %s."):format(DEVICE, remote.ClassName))
            isTrying = false
            return
        else
            warn(("[AUTO-DEVICE] Thử %d thất bại: %s"):format(i, tostring(err)))
            task.wait(0.5 * i)
        end
    end

    isTrying = false
end

-- Đảm bảo game đã load
if not g:IsLoaded() then g.Loaded:Wait() end

-- Khi nhân vật spawn/respawn → thử chọn
LP.CharacterAdded:Connect(function()
    task.delay(1, trySelect)
end)

-- Nếu đã có character sẵn → thử luôn
if LP.Character then
    task.delay(1, trySelect)
end

-- Khi Remote xuất hiện muộn → bắt sự kiện để thử ngay
local function onDescendantAdded(d)
    if d.Name == "ChangeLastDevice" and (d:IsA("RemoteEvent") or d:IsA("RemoteFunction")) then
        task.delay(0.2, trySelect)
    end
end
RS.DescendantAdded:Connect(onDescendantAdded)
g.DescendantAdded:Connect(onDescendantAdded)

-- Nếu UI vào chậm (nhiều game chỉ spawn Remote khi mở UI) → nghe PlayerGui
task.spawn(function()
    local pg = LP:WaitForChild("PlayerGui", 10)
    if pg then
        pg.DescendantAdded:Connect(function(inst)
            -- nếu trong tên có "device" thì khả năng là UI chọn thiết bị vừa bật
            if tostring(inst.Name):lower():find("device") then
                task.delay(0.1, trySelect)
            end
        end)
    end
end)

-- Thử lần đầu
task.delay(1, trySelect)
--// =================== HẾT KHỐI AUTO ===================
