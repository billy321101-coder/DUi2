-- Blox Fruits | Orbitus Auto Hop v3 — bypass 773
-- Lua 5.1 / Luau | executor (Synapse X / Wave / KRNL)
-- 773 fix: ละทิ้ง TeleportToPlaceInstance ทั้งหมด
-- ใช้ TeleportAsync + TeleportOptions แทน, fallback Teleport(placeId)

local Players         = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService     = game:GetService("HttpService")
local TweenService    = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer
local playerGui   = localPlayer:WaitForChild("PlayerGui")

-- ── CONFIG ────────────────────────────────────────────────────────────────────
local BOSS_NAME = "Orbitus"
local HOP_DELAY = 30
local SCAN_RATE = 1
-- ─────────────────────────────────────────────────────────────────────────────

-- ── GUI PARENT ────────────────────────────────────────────────────────────────
local guiParent
if syn and syn.protect_gui then
    guiParent = game:GetService("CoreGui")
elseif gethui then
    guiParent = gethui()
else
    guiParent = playerGui
end

-- ── UI BUILD ──────────────────────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name = "OrbitusHopUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = guiParent
if syn and syn.protect_gui then syn.protect_gui(gui) end

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 260, 0, 110)
frame.Position = UDim2.new(0, 16, 0.5, -55)
frame.BackgroundColor3 = Color3.fromRGB(10, 12, 22)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new("UIStroke", frame)
stroke.Color = Color3.fromRGB(60, 110, 255)
stroke.Thickness = 1.5

local topbar = Instance.new("Frame")
topbar.Size = UDim2.new(1, 0, 0, 32)
topbar.BackgroundColor3 = Color3.fromRGB(14, 17, 32)
topbar.BorderSizePixel = 0
topbar.Parent = frame
Instance.new("UICorner", topbar).CornerRadius = UDim.new(0, 10)
local fix = Instance.new("Frame", topbar)
fix.Size = UDim2.new(1, 0, 0, 10)
fix.Position = UDim2.new(0, 0, 1, -10)
fix.BackgroundColor3 = Color3.fromRGB(14, 17, 32)
fix.BorderSizePixel = 0

local titleLbl = Instance.new("TextLabel", topbar)
titleLbl.Size = UDim2.new(1, -40, 1, 0)
titleLbl.Position = UDim2.new(0, 12, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "⚡ Orbitus Auto Hop"
titleLbl.TextColor3 = Color3.fromRGB(160, 190, 255)
titleLbl.TextSize = 13
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextXAlignment = Enum.TextXAlignment.Left

local closeBtn = Instance.new("TextButton", topbar)
closeBtn.Size = UDim2.new(0, 24, 0, 24)
closeBtn.Position = UDim2.new(1, -28, 0, 4)
closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
closeBtn.Text = "✕"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.TextSize = 11
closeBtn.Font = Enum.Font.GothamBold
closeBtn.BorderSizePixel = 0
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)
closeBtn.MouseButton1Click:Connect(function() frame.Visible = not frame.Visible end)

local statusLabel = Instance.new("TextLabel", frame)
statusLabel.Size = UDim2.new(1, -24, 0, 20)
statusLabel.Position = UDim2.new(0, 12, 0, 38)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "🔍 Status: กำลังสแกน..."
statusLabel.TextColor3 = Color3.fromRGB(200, 210, 255)
statusLabel.TextSize = 12
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextXAlignment = Enum.TextXAlignment.Left

local bossLabel = Instance.new("TextLabel", frame)
bossLabel.Size = UDim2.new(1, -24, 0, 20)
bossLabel.Position = UDim2.new(0, 12, 0, 60)
bossLabel.BackgroundTransparency = 1
bossLabel.Text = "👹 Orbitus: ไม่พบ"
bossLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
bossLabel.TextSize = 12
bossLabel.Font = Enum.Font.Gotham
bossLabel.TextXAlignment = Enum.TextXAlignment.Left

local barBg = Instance.new("Frame", frame)
barBg.Size = UDim2.new(1, -24, 0, 8)
barBg.Position = UDim2.new(0, 12, 0, 88)
barBg.BackgroundColor3 = Color3.fromRGB(20, 25, 50)
barBg.BorderSizePixel = 0
Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 4)

local barFill = Instance.new("Frame", barBg)
barFill.Size = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3 = Color3.fromRGB(60, 110, 255)
barFill.BorderSizePixel = 0
Instance.new("UICorner", barFill).CornerRadius = UDim.new(0, 4)

-- ── NOTIFY ────────────────────────────────────────────────────────────────────
local function notify(msg, color)
    local n = Instance.new("Frame", gui)
    n.Size = UDim2.new(0, 240, 0, 36)
    n.Position = UDim2.new(0, 16, 1, 10)
    n.BackgroundColor3 = color or Color3.fromRGB(14, 17, 32)
    n.BorderSizePixel = 0
    Instance.new("UICorner", n).CornerRadius = UDim.new(0, 8)
    local ns = Instance.new("UIStroke", n)
    ns.Color = color or Color3.fromRGB(60, 110, 255)
    ns.Thickness = 1
    local nt = Instance.new("TextLabel", n)
    nt.Size = UDim2.new(1, -16, 1, 0)
    nt.Position = UDim2.new(0, 8, 0, 0)
    nt.BackgroundTransparency = 1
    nt.Text = msg
    nt.TextColor3 = Color3.fromRGB(230, 235, 255)
    nt.TextSize = 11
    nt.Font = Enum.Font.Gotham
    nt.TextXAlignment = Enum.TextXAlignment.Left
    nt.TextWrapped = true
    TweenService:Create(n, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
        { Position = UDim2.new(0, 16, 1, -52) }):Play()
    task.delay(3, function()
        TweenService:Create(n, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
            { Position = UDim2.new(0, 16, 1, 10) }):Play()
        task.wait(0.35)
        n:Destroy()
    end)
end

-- ── HOP — แก้หลัก ─────────────────────────────────────────────────────────────
-- TeleportToPlaceInstance ทุก form โดน 773 ใน Blox Fruits Sea 2
-- ใช้ TeleportAsync + TeleportOptions (ระบุ server id แบบ non-restricted)
-- fallback: Teleport(placeId) → random server
local function hopServer()
    local placeId = game.PlaceId
    local hopped  = false

    -- ดึง server list
    local ok, raw = pcall(game.HttpGet, game,
        "https://games.roblox.com/v1/games/" .. placeId ..
        "/servers/Public?sortOrder=Asc&limit=100"
    )

    if ok and raw then
        local ok2, data = pcall(HttpService.JSONDecode, HttpService, raw)
        if ok2 and data and data.data then
            for _, server in ipairs(data.data) do
                if  server.id ~= game.JobId
                and type(server.playing)    == "number"
                and type(server.maxPlayers) == "number"
                and server.playing < server.maxPlayers
                then
                    -- ✅ TeleportOptions แทน TeleportToPlaceInstance
                    local opts = Instance.new("TeleportOptions")
                    opts.ServerInstanceId = server.id

                    local ok3, err = pcall(function()
                        TeleportService:TeleportAsync(placeId, { localPlayer }, opts)
                    end)

                    if ok3 then
                        hopped = true
                        break
                    else
                        -- ถ้า TeleportAsync ก็ยัง fail → ลอง next server
                        warn("[AutoHop] TeleportAsync fail:", err)
                    end
                end
            end
        end
    end

    -- fallback สุดท้าย: random server hop
    if not hopped then
        notify("⚠️ TeleportAsync fail ทุก server — random hop", Color3.fromRGB(180, 80, 20))
        task.wait(0.3)
        pcall(TeleportService.Teleport, TeleportService, placeId)
    end
end

-- ── MAIN LOOP ─────────────────────────────────────────────────────────────────
local Enemies = workspace:WaitForChild("Enemies")

local function findBoss()
    for _, m in ipairs(Enemies:GetChildren()) do
        if m.Name == BOSS_NAME then
            local h = m:FindFirstChildOfClass("Humanoid")
            if h and h.Health > 0 then return m end
        end
    end
end

notify("⚡ Orbitus Auto Hop v3 เริ่มแล้ว", Color3.fromRGB(30, 80, 200))

task.spawn(function()
    task.wait(3)
    local notFoundSince = nil

    while task.wait(SCAN_RATE) do
        local boss = findBoss()

        if boss then
            notFoundSince = nil
            bossLabel.Text      = "👹 Orbitus: พบแล้ว ✅"
            bossLabel.TextColor3 = Color3.fromRGB(80, 220, 120)
            statusLabel.Text    = "🔍 Status: รอ Boss ตาย..."
            barFill.Size        = UDim2.new(0, 0, 1, 0)
            barFill.BackgroundColor3 = Color3.fromRGB(60, 110, 255)
        else
            bossLabel.Text      = "👹 Orbitus: ไม่พบ ❌"
            bossLabel.TextColor3 = Color3.fromRGB(255, 100, 100)

            if not notFoundSince then
                notFoundSince = tick()
                notify("⚠️ ไม่พบ Orbitus — รอ " .. HOP_DELAY .. "s",
                    Color3.fromRGB(180, 120, 20))
            end

            local elapsed = tick() - notFoundSince
            local ratio   = math.clamp(elapsed / HOP_DELAY, 0, 1)

            barFill.Size = UDim2.new(ratio, 0, 1, 0)
            barFill.BackgroundColor3 = ratio < 0.6
                and Color3.fromRGB(60, 110, 255)
                or  Color3.fromRGB(255, math.floor(110 * (1 - ratio)), 50)

            statusLabel.Text = string.format("⏱ Hop ใน: %.1fs",
                math.max(0, HOP_DELAY - elapsed))

            if elapsed >= HOP_DELAY then
                statusLabel.Text = "🚀 กำลัง Hop..."
                notify("🚀 Hop! ไม่เจอ Orbitus " .. HOP_DELAY .. "s",
                    Color3.fromRGB(60, 110, 255))
                notFoundSince = nil
                task.wait(0.5)
                task.spawn(hopServer)
            end
        end
    end
end)
