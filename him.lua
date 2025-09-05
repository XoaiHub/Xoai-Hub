-- ==== SPY Remote: log mọi FireServer/InvokeServer trong ReplicatedStorage.Remotes ====
local RS = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local root = RS:WaitForChild("Remotes", 10) or RS

local function safe_tostring(v)
    local t = typeof(v)
    if t=="Instance" then
        return ("<Instance:%s:%s>"):format(v.ClassName, v:GetFullName())
    elseif t=="table" then
        local ok, j = pcall(HttpService.JSONEncode, HttpService, v)
        return ok and j or tostring(v)
    else
        return tostring(v)
    end
end

local function dump_args(...)
    local out = {}
    for i,v in ipairs({...}) do
        out[i] = safe_tostring(v)
    end
    local ok, j = pcall(HttpService.JSONEncode, HttpService, out)
    return ok and j or table.concat(out, ", ")
end

local mt = getrawmetatable(game)
local old = mt.__namecall
setreadonly(mt, false)
mt.__namecall = newcclosure(function(self, ...)
    local m = getnamecallmethod()
    if (m=="FireServer" or m=="InvokeServer") and typeof(self)=="Instance" and self:IsDescendantOf(root) then
        warn(("[SPY] %s via %s | args=%s"):format(self:GetFullName(), m, dump_args(...)))
    end
    return old(self, ...)
end)
setreadonly(mt, true)

warn("[SPY] Sẵn sàng. Hãy bấm nút 'Phone' trong UI để ghi lại remote + args.")

