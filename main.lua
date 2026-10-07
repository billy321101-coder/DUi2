-- ==============================================================================
-- Orbitus Auto Server Hop (Fixed Error 773 & Anti-Full Server)
-- ==============================================================================

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

-- Global Configuration & State
getgenv().OrbitusHopConfig = getgenv().OrbitusHopConfig or {
    Enabled = true,
    Timeout = 10, -- นับถอยหลัง 10 วิเมื่อไม่เจอบอส
    TargetBossName = "orbitus",
    MaxServerPlayers = 11 -- กรองเฉพาะเซิร์ฟเวอร์ที่มีคนไม่เกิน 11 คน (ไม่เต็ม)
}

if not getgenv().VisitedServers then
    getgenv().VisitedServers = {}
end
getgenv().VisitedServers[game.JobId] = true

-- Auto-dismiss Error 773 modal if appears
local function dismissTeleportError()
    pcall(function()
        GuiService:ClearError()
    end)
    pcall(function()
        local prompt = game:GetService("CoreGui"):FindFirstChild("RobloxPromptGui")
        if prompt and prompt:FindFirstChild("promptOverlay") then
            local err = prompt.promptOverlay:FindFirstChild("ErrorPrompt")
            if err and err:FindFirstChild("MessageArea") then
                local btn = err.MessageArea:FindFirstChildWhichIsA("TextButton", true)
                if btn and typeof(firesignal) == "function" then
                    firesignal(btn.MouseButton1Click)
                end
            end
        end
    end)
end

-- ==============================================================================
-- Boss Detection Logic
-- ==============================================================================
local function isOrbitusAlive()
    local targetName = string.lower(getgenv().OrbitusHopConfig.TargetBossName)

    -- 1. Check workspace.Enemies
    local enemies = workspace:FindFirstChild("Enemies")
    if enemies then
        for _, enemy in ipairs(enemies:GetChildren()) do
            if string.find(string.lower(enemy.Name), targetName) then
                local hum = enemy:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    return true, enemy.Name
                end
            end
        end
    end

    -- 2. Check workspace general models
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("Model") and string.find(string.lower(obj.Name), targetName) then
            local hum = obj:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                return true, obj.Name
            end
        end
    end

    -- 3. Check world Billboard labels / Spawn signs
    for _, desc in ipairs(workspace:GetDescendants()) do
        if desc:IsA("TextLabel") and desc.Visible then
            local txt = string.lower(desc.Text)
            if string.find(txt, targetName) then
                -- Must not be respawn timer or defeated
                if not string.find(txt, "respawn") and not string.find(txt, "00:00") and not string.find(txt, "defeated") then
                    return true, desc.Text
                end
            end
        end
    end

    return false, nil
end

-- ==============================================================================
-- Server Hop Logic (Uses game.PlaceId + Filters Full Servers)
-- ==============================================================================
local isHopping = false

local function RandomServerHop(statusCallback)
    if isHopping then return end
    isHopping = true

    dismissTeleportError()

    if statusCallback then statusCallback("🔍 Finding non-full servers...") end

    -- Use current game.PlaceId directly (prevents Error 773 restricted place)
    local targetPlaceId = game.PlaceId
    local currentJobId = game.JobId
    local validServers = {}

    -- Fetch multiple pages or Ascending to find free slots
    local success, response = pcall(function()
        local url = string.format(
            "https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Asc&excludeFullGames=true&limit=100",
            tostring(targetPlaceId)
        )
        return game:HttpGet(url)
    end)

    if success and response then
        local parseOk, data = pcall(function() return HttpService:JSONDecode(response) end)
        if parseOk and data and data.data then
            for _, s in ipairs(data.data) do
                if type(s) == "table" and s.id and s.id ~= currentJobId then
                    local playersCount = tonumber(s.playing) or 0
                    local maxCount = tonumber(s.maxPlayers) or 12
                    -- Ensure server has available spots and not visited
                    if playersCount <= getgenv().OrbitusHopConfig.MaxServerPlayers and playersCount < maxCount and not getgenv().VisitedServers[s.id] then
                        table.insert(validServers, s.id)
                    end
                end
            end
        end
    end

    if #validServers > 0 then
        -- Random pick among available non-full servers
        local chosenServer = validServers[math.random(1, #validServers)]
        getgenv().VisitedServers[chosenServer] = true

        if statusCallback then statusCallback("🚀 Teleporting to new server...") end

        local tpSuccess, tpErr = pcall(function()
            TeleportService:TeleportToPlaceInstance(targetPlaceId, chosenServer, LocalPlayer)
        end)

        if not tpSuccess then
            dismissTeleportError()
            task.wait(1.5)
            isHopping = false
            RandomServerHop(statusCallback)
        end
    else
        -- If no servers in first batch, clear visited and teleport
        if statusCallback then statusCallback("🔄 Resetting server cache...") end
        getgenv().VisitedServers = { [currentJobId] = true }
        pcall(function()
            TeleportService:Teleport(targetPlaceId, LocalPlayer)
        end)
        task.wait(2)
        dismissTeleportError()
        isHopping = false
    end
end

-- Auto-retry on teleport failure
TeleportService.TeleportInitFailed:Connect(function(player, teleportResult, errorMessage)
    dismissTeleportError()
    task.wait(1)
    isHopping = false
    RandomServerHop()
end)

-- ==============================================================================
-- GUI Creation (Modern, Clean, Draggable)
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
ScreenGui.Name = "OrbitusAutoHopGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = guiParent

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 310, 0, 195)
MainFrame.Position = UDim2.new(0.02, 0, 0.25, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = true
MainFrame.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 10)
UICorner.Parent = MainFrame

local UIStroke = Instance.new("UIStroke")
UIStroke.Thickness = 1.5
UIStroke.Color = Color3.fromRGB(70, 70, 100)
UIStroke.Parent = MainFrame

-- Top Bar
local TopBar = Instance.new("Frame")
TopBar.Name = "TopBar"
TopBar.Size = UDim2.new(1, 0, 0, 34)
TopBar.BackgroundColor3 = Color3.fromRGB(26, 26, 36)
TopBar.BorderSizePixel = 0
TopBar.Parent = MainFrame

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Name = "TitleLabel"
TitleLabel.Size = UDim2.new(1, -40, 1, 0)
TitleLabel.Position = UDim2.new(0, 10, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.Text = "🌌 Orbitus Auto Hop"
TitleLabel.TextColor3 = Color3.fromRGB(240, 240, 255)
TitleLabel.TextSize = 13
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = TopBar

local CloseBtn = Instance.new("TextButton")
CloseBtn.Name = "CloseBtn"
CloseBtn.Size = UDim2.new(0, 26, 0, 26)
CloseBtn.Position = UDim2.new(1, -30, 0, 4)
CloseBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 60)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.Text = "✕"
CloseBtn.TextColor3 = Color3.fromRGB(200, 200, 220)
CloseBtn.TextSize = 12
CloseBtn.Parent = TopBar

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 6)
CloseCorner.Parent = CloseBtn

CloseBtn.MouseButton1Click:Connect(function()
    ScreenGui:Destroy()
end)

-- Draggable Logic
local dragging, dragInput, dragStart, startPos
TopBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = MainFrame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)
TopBar.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

-- Content Frame
local ContentFrame = Instance.new("Frame")
ContentFrame.Name = "ContentFrame"
ContentFrame.Size = UDim2.new(1, -20, 1, -44)
ContentFrame.Position = UDim2.new(0, 10, 0, 40)
ContentFrame.BackgroundTransparency = 1
ContentFrame.Parent = MainFrame

local BossStatusLabel = Instance.new("TextLabel")
BossStatusLabel.Name = "BossStatusLabel"
BossStatusLabel.Size = UDim2.new(1, 0, 0, 22)
BossStatusLabel.Position = UDim2.new(0, 0, 0, 0)
BossStatusLabel.BackgroundTransparency = 1
BossStatusLabel.Font = Enum.Font.GothamSemibold
BossStatusLabel.Text = "🔍 Checking Orbitus..."
BossStatusLabel.TextColor3 = Color3.fromRGB(255, 200, 80)
BossStatusLabel.TextSize = 13
BossStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
BossStatusLabel.Parent = ContentFrame

local CountdownLabel = Instance.new("TextLabel")
CountdownLabel.Name = "CountdownLabel"
CountdownLabel.Size = UDim2.new(1, 0, 0, 20)
CountdownLabel.Position = UDim2.new(0, 0, 0, 24)
CountdownLabel.BackgroundTransparency = 1
CountdownLabel.Font = Enum.Font.Gotham
CountdownLabel.Text = "⏳ Hop Countdown: 10s"
CountdownLabel.TextColor3 = Color3.fromRGB(180, 180, 200)
CountdownLabel.TextSize = 12
CountdownLabel.TextXAlignment = Enum.TextXAlignment.Left
CountdownLabel.Parent = ContentFrame

local ProgressBg = Instance.new("Frame")
ProgressBg.Name = "ProgressBg"
ProgressBg.Size = UDim2.new(1, 0, 0, 7)
ProgressBg.Position = UDim2.new(0, 0, 0, 48)
ProgressBg.BackgroundColor3 = Color3.fromRGB(35, 35, 48)
ProgressBg.BorderSizePixel = 0
ProgressBg.Parent = ContentFrame

local ProgressBgCorner = Instance.new("UICorner")
ProgressBgCorner.CornerRadius = UDim.new(0, 4)
ProgressBgCorner.Parent = ProgressBg

local ProgressBar = Instance.new("Frame")
ProgressBar.Name = "ProgressBar"
ProgressBar.Size = UDim2.new(0, 0, 1, 0)
ProgressBar.BackgroundColor3 = Color3.fromRGB(240, 70, 70)
ProgressBar.BorderSizePixel = 0
ProgressBar.Parent = ProgressBg

local ProgressCorner = Instance.new("UICorner")
ProgressCorner.CornerRadius = UDim.new(0, 4)
ProgressCorner.Parent = ProgressBar

local LogLabel = Instance.new("TextLabel")
LogLabel.Name = "LogLabel"
LogLabel.Size = UDim2.new(1, 0, 0, 18)
LogLabel.Position = UDim2.new(0, 0, 0, 60)
LogLabel.BackgroundTransparency = 1
LogLabel.Font = Enum.Font.Gotham
LogLabel.Text = "Place: " .. tostring(game.PlaceId)
LogLabel.TextColor3 = Color3.fromRGB(130, 130, 160)
LogLabel.TextSize = 11
LogLabel.TextXAlignment = Enum.TextXAlignment.Left
LogLabel.Parent = ContentFrame

local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Name = "ToggleBtn"
ToggleBtn.Size = UDim2.new(0.58, -5, 0, 32)
ToggleBtn.Position = UDim2.new(0, 0, 1, -34)
ToggleBtn.BackgroundColor3 = Color3.fromRGB(35, 120, 70)
ToggleBtn.Font = Enum.Font.GothamBold
ToggleBtn.Text = "Auto Hop: ON"
ToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleBtn.TextSize = 12
ToggleBtn.Parent = ContentFrame

local ToggleCorner = Instance.new("UICorner")
ToggleCorner.CornerRadius = UDim.new(0, 6)
ToggleCorner.Parent = ToggleBtn

local ManualHopBtn = Instance.new("TextButton")
ManualHopBtn.Name = "ManualHopBtn"
ManualHopBtn.Size = UDim2.new(0.42, -5, 0, 32)
ManualHopBtn.Position = UDim2.new(0.58, 5, 1, -34)
ManualHopBtn.BackgroundColor3 = Color3.fromRGB(50, 60, 95)
ManualHopBtn.Font = Enum.Font.GothamBold
ManualHopBtn.Text = "⚡ Hop Now"
ManualHopBtn.TextColor3 = Color3.fromRGB(240, 240, 255)
ManualHopBtn.TextSize = 12
ManualHopBtn.Parent = ContentFrame

local ManualCorner = Instance.new("UICorner")
ManualCorner.CornerRadius = UDim.new(0, 6)
ManualCorner.Parent = ManualHopBtn

ToggleBtn.MouseButton1Click:Connect(function()
    getgenv().OrbitusHopConfig.Enabled = not getgenv().OrbitusHopConfig.Enabled
    if getgenv().OrbitusHopConfig.Enabled then
        ToggleBtn.Text = "Auto Hop: ON"
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(35, 120, 70)
    else
        ToggleBtn.Text = "Auto Hop: OFF"
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(90, 40, 40)
    end
end)

ManualHopBtn.MouseButton1Click:Connect(function()
    RandomServerHop(function(msg)
        LogLabel.Text = msg
    end)
end)

-- ==============================================================================
-- Main Monitor Loop (10 seconds timeout)
-- ==============================================================================
task.spawn(function()
    local missingTimer = 0
    local maxTimeout = getgenv().OrbitusHopConfig.Timeout

    while ScreenGui.Parent do
        task.wait(1)

        if getgenv().OrbitusHopConfig.Enabled and not isHopping then
            local alive, bossName = isOrbitusAlive()

            if alive then
                -- Boss is found! Reset countdown
                missingTimer = 0
                BossStatusLabel.Text = "🟢 Boss Found: " .. tostring(bossName)
                BossStatusLabel.TextColor3 = Color3.fromRGB(80, 240, 120)
                CountdownLabel.Text = "✨ Boss is alive! Timer reset."
                CountdownLabel.TextColor3 = Color3.fromRGB(160, 240, 180)
                
                TweenService:Create(ProgressBar, TweenInfo.new(0.3), {
                    Size = UDim2.new(0, 0, 1, 0),
                    BackgroundColor3 = Color3.fromRGB(80, 220, 120)
                }):Play()
            else
                -- Boss NOT found!
                missingTimer = missingTimer + 1
                local timeLeft = math.max(0, maxTimeout - missingTimer)

                BossStatusLabel.Text = "🔴 Orbitus Not Found!"
                BossStatusLabel.TextColor3 = Color3.fromRGB(240, 80, 80)
                CountdownLabel.Text = string.format("⏳ Hopping in: %ds / %ds", timeLeft, maxTimeout)
                CountdownLabel.TextColor3 = Color3.fromRGB(255, 190, 100)

                local progressRatio = math.clamp(missingTimer / maxTimeout, 0, 1)
                TweenService:Create(ProgressBar, TweenInfo.new(0.5), {
                    Size = UDim2.new(progressRatio, 0, 1, 0),
                    BackgroundColor3 = Color3.fromRGB(240, 70, 70)
                }):Play()

                if missingTimer >= maxTimeout then
                    BossStatusLabel.Text = "🚀 Timeout! Switching server..."
                    CountdownLabel.Text = "Finding new random server..."
                    RandomServerHop(function(msg)
                        LogLabel.Text = msg
                    end)
                end
            end
        end
    end
end)
