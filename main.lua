-- ==============================================================================
-- Orbitus Auto Server Hop (Dedicated: Second Sea / โลก 2 เท่านั้น)
-- Target Place ID: 4442272183
-- Fix: 773 blacklist, race condition, dismissTeleportError safe path
-- ==============================================================================

local Players          = game:GetService("Players")
local TeleportService  = game:GetService("TeleportService")
local HttpService      = game:GetService("HttpService")
local TweenService     = game:GetService("TweenService")
local GuiService       = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

-- Global Configuration & State
getgenv().OrbitusHopConfig = getgenv().OrbitusHopConfig or {
    Enabled        = true,
    Timeout        = 10,
    TargetBossName = "orbitus",
    TargetPlaceId  = 4442272183,
    MaxServerPlayers = 11,
}

if not getgenv().VisitedServers then
    getgenv().VisitedServers = {}
end
getgenv().VisitedServers[game.JobId] = true
getgenv()._lastAttemptedServer = nil

-- ==============================================================================
-- [FIX 3] dismissTeleportError — no firesignal, safe on all executors
-- ==============================================================================
local function dismissTeleportError()
    pcall(function() GuiService:ClearError() end)
    pcall(function()
        local cg      = game:GetService("CoreGui")
        local rpg     = cg:FindFirstChild("RobloxPromptGui")
        if not rpg then return end
        local overlay = rpg:FindFirstChild("promptOverlay")
        if not overlay then return end
        local errP    = overlay:FindFirstChild("ErrorPrompt")
        if not errP or not errP.Visible then return end
        local btn     = errP:FindFirstChildWhichIsA("TextButton", true)
        if btn then
            -- ไม่ใช้ firesignal; ยิง MouseButton1Click ผ่าน event โดยตรง
            pcall(function() btn.MouseButton1Click:Fire() end)
            pcall(function() btn:Activate() end)
        end
    end)
end

-- Continuous background dismisser
task.spawn(function()
    while true do
        task.wait(0.5)
        dismissTeleportError()
    end
end)

-- ==============================================================================
-- Boss Detection (Physical Models Only)
-- ==============================================================================
local function isOrbitusAlive()
    local targetName = "orbitus"
    local fajitaName = "fajita"

    local function checkModel(obj)
        if not obj:IsA("Model") then return false end
        local low = string.lower(obj.Name)
        if not (string.find(low, targetName) or string.find(low, fajitaName)) then return false end
        local hum = obj:FindFirstChildOfClass("Humanoid")
        local hrp = obj:FindFirstChild("HumanoidRootPart")
        if hum and hum.Health > 0 and hrp then
            return true, obj.Name, math.floor(hum.Health), math.floor(hum.MaxHealth)
        end
        return false
    end

    -- 1. workspace.Enemies
    local enemies = workspace:FindFirstChild("Enemies")
    if enemies then
        for _, e in ipairs(enemies:GetChildren()) do
            local ok, n, hp, mhp = checkModel(e)
            if ok then return true, n, hp, mhp end
        end
    end

    -- 2. workspace root
    for _, obj in ipairs(workspace:GetChildren()) do
        local ok, n, hp, mhp = checkModel(obj)
        if ok then return true, n, hp, mhp end
    end

    return false, nil, 0, 0
end

-- ==============================================================================
-- Server Hop (Locked to Sea 2 — Anti-773 blacklist + race fix)
-- ==============================================================================
local isHopping = false

local function RandomServerHop(statusCallback)
    if isHopping then return end
    isHopping = true
    dismissTeleportError()

    local targetPlaceId = 4442272183
    local currentJobId  = game.JobId

    -- Not in Sea 2 yet → matchmaking teleport
    if game.PlaceId ~= targetPlaceId then
        if statusCallback then statusCallback("🚀 Teleporting to Sea 2...") end
        pcall(function() TeleportService:Teleport(targetPlaceId, LocalPlayer) end)
        task.wait(2)
        dismissTeleportError()
        isHopping = false
        return
    end

    if statusCallback then statusCallback("🔍 Finding healthy Sea 2 servers...") end

    local validServers = {}

    local function parseServers(response)
        local ok, data = pcall(function() return HttpService:JSONDecode(response) end)
        if not ok or not data or not data.data then return end
        for _, s in ipairs(data.data) do
            if type(s) == "table" and s.id
               and s.id ~= currentJobId
               and not getgenv().VisitedServers[s.id]
            then
                local playing = tonumber(s.playing) or 0
                local maxP    = tonumber(s.maxPlayers) or 12
                if playing >= 3 and playing <= 11 and playing < maxP then
                    table.insert(validServers, s.id)
                end
            end
        end
    end

    -- Step 1: Desc sort
    local ok1, res1 = pcall(function()
        return game:HttpGet(string.format(
            "https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Desc&excludeFullGames=true&limit=100",
            tostring(targetPlaceId)
        ))
    end)
    if ok1 and res1 then parseServers(res1) end

    -- Step 2: Asc fallback
    if #validServers == 0 then
        local ok2, res2 = pcall(function()
            return game:HttpGet(string.format(
                "https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Asc&excludeFullGames=true&limit=100",
                tostring(targetPlaceId)
            ))
        end)
        if ok2 and res2 then
            -- relax floor to 2 on fallback
            local ok3, data = pcall(function() return HttpService:JSONDecode(res2) end)
            if ok3 and data and data.data then
                for _, s in ipairs(data.data) do
                    if type(s) == "table" and s.id
                       and s.id ~= currentJobId
                       and not getgenv().VisitedServers[s.id]
                    then
                        local playing = tonumber(s.playing) or 0
                        local maxP    = tonumber(s.maxPlayers) or 12
                        if playing >= 2 and playing <= 11 and playing < maxP then
                            table.insert(validServers, s.id)
                        end
                    end
                end
            end
        end
    end

    -- Step 3: Teleport
    if #validServers > 0 then
        local chosen = validServers[math.random(1, #validServers)]
        getgenv().VisitedServers[chosen]    = true
        getgenv()._lastAttemptedServer      = chosen   -- [FIX 1] save for blacklist on 773

        if statusCallback then statusCallback("🚀 Teleporting to Sea 2...") end

        local tpOk, tpErr = pcall(function()
            TeleportService:TeleportToPlaceInstance(targetPlaceId, chosen, LocalPlayer)
        end)

        if not tpOk then
            warn("[Orbitus] TeleportToPlaceInstance failed:", tpErr)
            -- already blacklisted via VisitedServers above
            dismissTeleportError()
            task.wait(1)
            isHopping = false
            pcall(function() TeleportService:Teleport(targetPlaceId, LocalPlayer) end)
        end
    else
        -- Pool exhausted → reset visited (keep current + last bad) and matchmake
        if statusCallback then statusCallback("🔄 Hopping to Sea 2 (Matchmaking)...") end
        local keepCurrent = currentJobId
        local keepLast    = getgenv()._lastAttemptedServer
        getgenv().VisitedServers = {
            [keepCurrent] = true,
            [keepLast or ""] = true,
        }
        pcall(function() TeleportService:Teleport(targetPlaceId, LocalPlayer) end)
        task.wait(2)
        dismissTeleportError()
        isHopping = false
    end
end

-- [FIX 1] TeleportInitFailed — blacklist + retry, no infinite loop on same server
TeleportService.TeleportInitFailed:Connect(function(player, result, errorMessage)
    warn("[Orbitus] TeleportInitFailed | result:", result, "| msg:", errorMessage)
    dismissTeleportError()

    -- Blacklist the server that caused 773
    if getgenv()._lastAttemptedServer then
        getgenv().VisitedServers[getgenv()._lastAttemptedServer] = true
        getgenv()._lastAttemptedServer = nil
    end

    task.wait(1.5)
    isHopping = false
    RandomServerHop()
end)

-- ==============================================================================
-- GUI
-- ==============================================================================
local function getGuiParent()
    local p
    pcall(function() p = gethui and gethui() end)
    if not p then pcall(function() p = game:GetService("CoreGui") end) end
    if not p then p = LocalPlayer:WaitForChild("PlayerGui") end
    return p
end

local guiParent = getGuiParent()
if guiParent:FindFirstChild("OrbitusAutoHopGui") then
    guiParent:FindFirstChild("OrbitusAutoHopGui"):Destroy()
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name          = "OrbitusAutoHopGui"
ScreenGui.ResetOnSpawn  = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent        = guiParent

local MainFrame = Instance.new("Frame")
MainFrame.Name              = "MainFrame"
MainFrame.Size              = UDim2.new(0, 310, 0, 195)
MainFrame.Position          = UDim2.new(0.02, 0, 0.25, 0)
MainFrame.BackgroundColor3  = Color3.fromRGB(18, 18, 24)
MainFrame.BorderSizePixel   = 0
MainFrame.ClipsDescendants  = true
MainFrame.Parent            = ScreenGui

Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 10)

local UIStroke = Instance.new("UIStroke", MainFrame)
UIStroke.Thickness = 1.5
UIStroke.Color     = Color3.fromRGB(80, 120, 200)

-- Top Bar
local TopBar = Instance.new("Frame", MainFrame)
TopBar.Size             = UDim2.new(1, 0, 0, 34)
TopBar.BackgroundColor3 = Color3.fromRGB(24, 30, 48)
TopBar.BorderSizePixel  = 0

local TitleLabel = Instance.new("TextLabel", TopBar)
TitleLabel.Size               = UDim2.new(1, -40, 1, 0)
TitleLabel.Position           = UDim2.new(0, 10, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Font               = Enum.Font.GothamBold
TitleLabel.Text               = "🌊 Orbitus Hop [Sea 2]"
TitleLabel.TextColor3         = Color3.fromRGB(220, 235, 255)
TitleLabel.TextSize           = 13
TitleLabel.TextXAlignment     = Enum.TextXAlignment.Left

local CloseBtn = Instance.new("TextButton", TopBar)
CloseBtn.Size             = UDim2.new(0, 26, 0, 26)
CloseBtn.Position         = UDim2.new(1, -30, 0, 4)
CloseBtn.BackgroundColor3 = Color3.fromRGB(40, 50, 75)
CloseBtn.Font             = Enum.Font.GothamBold
CloseBtn.Text             = "✕"
CloseBtn.TextColor3       = Color3.fromRGB(200, 210, 230)
CloseBtn.TextSize         = 12
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 6)
CloseBtn.MouseButton1Click:Connect(function() ScreenGui:Destroy() end)

-- Drag
local dragging, dragInput, dragStart, startPos
TopBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        dragging  = true
        dragStart = input.Position
        startPos  = MainFrame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)
TopBar.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement
    or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        MainFrame.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end
end)

-- Content
local ContentFrame = Instance.new("Frame", MainFrame)
ContentFrame.Size                 = UDim2.new(1, -20, 1, -44)
ContentFrame.Position             = UDim2.new(0, 10, 0, 40)
ContentFrame.BackgroundTransparency = 1

local BossStatusLabel = Instance.new("TextLabel", ContentFrame)
BossStatusLabel.Size              = UDim2.new(1, 0, 0, 22)
BossStatusLabel.Position          = UDim2.new(0, 0, 0, 0)
BossStatusLabel.BackgroundTransparency = 1
BossStatusLabel.Font              = Enum.Font.GothamSemibold
BossStatusLabel.Text              = "🔍 Checking Orbitus..."
BossStatusLabel.TextColor3        = Color3.fromRGB(255, 200, 80)
BossStatusLabel.TextSize          = 13
BossStatusLabel.RichText          = true
BossStatusLabel.TextXAlignment    = Enum.TextXAlignment.Left

local CountdownLabel = Instance.new("TextLabel", ContentFrame)
CountdownLabel.Size               = UDim2.new(1, 0, 0, 20)
CountdownLabel.Position           = UDim2.new(0, 0, 0, 24)
CountdownLabel.BackgroundTransparency = 1
CountdownLabel.Font               = Enum.Font.Gotham
CountdownLabel.Text               = "⏳ Hop Countdown: 10s"
CountdownLabel.TextColor3         = Color3.fromRGB(180, 190, 210)
CountdownLabel.TextSize           = 12
CountdownLabel.TextXAlignment     = Enum.TextXAlignment.Left

local ProgressBg = Instance.new("Frame", ContentFrame)
ProgressBg.Size             = UDim2.new(1, 0, 0, 7)
ProgressBg.Position         = UDim2.new(0, 0, 0, 48)
ProgressBg.BackgroundColor3 = Color3.fromRGB(30, 36, 52)
ProgressBg.BorderSizePixel  = 0
Instance.new("UICorner", ProgressBg).CornerRadius = UDim.new(0, 4)

local ProgressBar = Instance.new("Frame", ProgressBg)
ProgressBar.Size             = UDim2.new(0, 0, 1, 0)
ProgressBar.BackgroundColor3 = Color3.fromRGB(240, 70, 70)
ProgressBar.BorderSizePixel  = 0
Instance.new("UICorner", ProgressBar).CornerRadius = UDim.new(0, 4)

local LogLabel = Instance.new("TextLabel", ContentFrame)
LogLabel.Size                 = UDim2.new(1, 0, 0, 18)
LogLabel.Position             = UDim2.new(0, 0, 0, 60)
LogLabel.BackgroundTransparency = 1
LogLabel.Font                 = Enum.Font.Gotham
LogLabel.Text                 = "Target: Second Sea (4442272183)"
LogLabel.TextColor3           = Color3.fromRGB(120, 150, 190)
LogLabel.TextSize             = 11
LogLabel.TextXAlignment       = Enum.TextXAlignment.Left

local ToggleBtn = Instance.new("TextButton", ContentFrame)
ToggleBtn.Size             = UDim2.new(0.58, -5, 0, 32)
ToggleBtn.Position         = UDim2.new(0, 0, 1, -34)
ToggleBtn.BackgroundColor3 = Color3.fromRGB(35, 120, 70)
ToggleBtn.Font             = Enum.Font.GothamBold
ToggleBtn.Text             = "Auto Hop: ON"
ToggleBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
ToggleBtn.TextSize         = 12
Instance.new("UICorner", ToggleBtn).CornerRadius = UDim.new(0, 6)

local ManualHopBtn = Instance.new("TextButton", ContentFrame)
ManualHopBtn.Size             = UDim2.new(0.42, -5, 0, 32)
ManualHopBtn.Position         = UDim2.new(0.58, 5, 1, -34)
ManualHopBtn.BackgroundColor3 = Color3.fromRGB(40, 70, 120)
ManualHopBtn.Font             = Enum.Font.GothamBold
ManualHopBtn.Text             = "⚡ Hop Sea 2"
ManualHopBtn.TextColor3       = Color3.fromRGB(230, 240, 255)
ManualHopBtn.TextSize         = 12
Instance.new("UICorner", ManualHopBtn).CornerRadius = UDim.new(0, 6)

ToggleBtn.MouseButton1Click:Connect(function()
    getgenv().OrbitusHopConfig.Enabled = not getgenv().OrbitusHopConfig.Enabled
    if getgenv().OrbitusHopConfig.Enabled then
        ToggleBtn.Text             = "Auto Hop: ON"
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(35, 120, 70)
    else
        ToggleBtn.Text             = "Auto Hop: OFF"
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(90, 40, 40)
    end
end)

ManualHopBtn.MouseButton1Click:Connect(function()
    RandomServerHop(function(msg) LogLabel.Text = msg end)
end)

-- ==============================================================================
-- Main Monitor Loop
-- ==============================================================================
task.spawn(function()
    local missingTimer = 0
    local maxTimeout   = getgenv().OrbitusHopConfig.Timeout

    while ScreenGui.Parent do
        task.wait(1)

        if getgenv().OrbitusHopConfig.Enabled and not isHopping then
            local alive, bossName, currentHp, maxHp = isOrbitusAlive()

            if alive then
                missingTimer = 0
                local cleanName = string.gsub(tostring(bossName), "<[^>]+>", "")
                if maxHp and maxHp > 0 then
                    BossStatusLabel.Text = string.format("🟢 %s (HP: %d/%d)", cleanName, currentHp, maxHp)
                else
                    BossStatusLabel.Text = "🟢 Boss Found: " .. cleanName
                end
                BossStatusLabel.TextColor3 = Color3.fromRGB(80, 240, 120)
                CountdownLabel.Text        = "✨ Boss is alive! Timer reset."
                CountdownLabel.TextColor3  = Color3.fromRGB(160, 240, 180)
                TweenService:Create(ProgressBar, TweenInfo.new(0.3), {
                    Size             = UDim2.new(0, 0, 1, 0),
                    BackgroundColor3 = Color3.fromRGB(80, 220, 120),
                }):Play()
            else
                missingTimer = missingTimer + 1
                local timeLeft = math.max(0, maxTimeout - missingTimer)

                BossStatusLabel.Text       = "🔴 Orbitus Dead / Not Found"
                BossStatusLabel.TextColor3 = Color3.fromRGB(240, 80, 80)
                CountdownLabel.Text        = string.format("⏳ Hopping in: %ds / %ds", timeLeft, maxTimeout)
                CountdownLabel.TextColor3  = Color3.fromRGB(255, 190, 100)

                local ratio = math.clamp(missingTimer / maxTimeout, 0, 1)
                TweenService:Create(ProgressBar, TweenInfo.new(0.5), {
                    Size             = UDim2.new(ratio, 0, 1, 0),
                    BackgroundColor3 = Color3.fromRGB(240, 70, 70),
                }):Play()

                if missingTimer >= maxTimeout then
                    missingTimer               = 0   -- reset ก่อน hop ป้องกัน double-trigger
                    BossStatusLabel.Text       = "🚀 Timeout! Switching Sea 2..."
                    CountdownLabel.Text        = "Finding Sea 2 server..."
                    RandomServerHop(function(msg) LogLabel.Text = msg end)
                end
            end
        end
    end
end)
