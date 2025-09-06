-- bám sàn nhẹ để tránh nhảy Y đột ngột
local function groundSnap(pos)
    local ray = Ray.new(pos + Vector3.new(0, 6, 0), Vector3.new(0, -30, 0))
    local hit, hitPos = workspace:FindPartOnRayWithIgnoreList(ray, { Char })
    if hit then
        return Vector3.new(hitPos.X, hitPos.Y + Config.GroundOffset, hitPos.Z)
    end
    return pos
end

-- tween an toàn: đi theo đoạn ngắn thay vì phóng 1 phát
local currentTween
local function cancelTween()
    if currentTween then pcall(function() currentTween:Cancel() end); currentTween = nil end
end

local function tpTo(targetPart)
    if not (HRP and targetPart and targetPart.CFrame) then return end

    -- KHÔNG đặt Physics/PlatformStand để tránh bị xem là tele
    local target = targetPart.Position

    local function tweenTo(destPos)
        local here = HRP.Position
        local delta = destPos - here
        local dist  = delta.Magnitude
        if dist < 0.5 then return end
        local t = math.clamp(dist / Config.TweenSpeedDiv, Config.TweenMinTime, Config.TweenMaxTime)
        -- kìm trục Y để tránh “Invalid position”
        local dy = math.clamp(destPos.Y - here.Y, -Config.MaxVerticalDelta, Config.MaxVerticalDelta)
        destPos = Vector3.new(destPos.X, here.Y + dy, destPos.Z)
        destPos = groundSnap(destPos)

        cancelTween()
        currentTween = TweenService:Create(HRP, TweenInfo.new(t, Enum.EasingStyle.Linear), {
            CFrame = CFrame.new(destPos)
        })
        currentTween:Play()
        currentTween.Completed:Wait()
        task.wait(Config.SegmentPause)
    end

    -- đi theo nhiều đoạn ngắn
    while true do
        local here = HRP.Position
        local delta = target - here
        local dist  = delta.Magnitude
        if dist <= Config.MaxSegmentDist + 2 then
            tweenTo(target) -- đoạn cuối
            break
        else
            local step = delta.Unit * Config.MaxSegmentDist
            tweenTo(here + step)
        end
        -- target có thể dịch chuyển (coin rơi), cập nhật lại
        if targetPart.Parent then
            target = targetPart.Position
        else
            break
        end
    end
end

