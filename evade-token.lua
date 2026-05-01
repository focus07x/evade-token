-- =====================================================
-- 🧹 ลบ UI ที่ไม่จำเป็น
-- =====================================================
pcall(function()
    game.CoreGui.ScriptBoxSimpleLabel:Destroy()
end)

-- =====================================================
-- ⚙️ SETTINGS (ปรับตรงนี้อย่างเดียวพอ)
-- =====================================================

getgenv().FarmToken = true      -- true = ฟาร์มโทเคน | false = ไม่ฟาร์ม
getgenv().TokenDelay = 0.50     -- ความเร็ววาร์ปเก็บโทเคน (ยิ่งมากยิ่งนิ่ง)

local SAFE_BLOCK_HEIGHT = 4000   -- 🔼 ความสูงแท่นลอย
local SAFE_BLOCK_SIZE = Vector3.new(20, 1, 20) -- 📦 ขนาดแท่น
local RETURN_DISTANCE = 55      -- 🔁 ระยะดึงกลับแท่น
local JOIN_INTERVAL = 1.5       -- ⏱ ความถี่กด Join (วินาที)

-- =====================================================
-- 🧠 SERVICES / VARIABLES
-- =====================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local joinEvent = ReplicatedStorage:WaitForChild("Events")
    :WaitForChild("Player")
    :WaitForChild("ChangePlayerMode")

local currentBlock = nil
local blockLoopRunning = false
local farmingToken = false -- ⭐ สำคัญ: ใช้แก้ปัญหาวาร์ปกลับเร็ว

-- =====================================================
-- 🛑 กัน AFK
-- =====================================================
player.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

-- =====================================================
-- 🏠 เช็คว่าอยู่ล็อบบี้หรือไม่ (ดูจาก UI Version)
-- =====================================================
local function isInLobby()
    local gui = player:WaitForChild("PlayerGui")
    for _, v in ipairs(gui:GetDescendants()) do
        if (v:IsA("TextLabel") or v:IsA("TextButton"))
        and v.Visible
        and typeof(v.Text) == "string"
        and string.find(v.Text, "Version:") then
            return true
        end
    end
    return false
end

-- =====================================================
-- 🟦 สร้าง Safe Block + วาร์ปขึ้น
-- =====================================================
local function createSafeBlock(character)
    local hrp = character:WaitForChild("HumanoidRootPart")

    if currentBlock then
        currentBlock:Destroy()
    end

    local block = Instance.new("Part")
    block.Size = SAFE_BLOCK_SIZE
    block.Anchored = true
    block.CanCollide = true
    block.Material = Enum.Material.SmoothPlastic
    block.Color = Color3.fromRGB(180, 180, 180)
    block.Name = "SafeBlock"
    block.Parent = workspace

    local pos = hrp.Position + Vector3.new(0, SAFE_BLOCK_HEIGHT, 0)
    block.CFrame = CFrame.new(pos)
    hrp.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))

    currentBlock = block

    if blockLoopRunning then return end
    blockLoopRunning = true

    -- 🔁 ลูปดึงกลับแท่น (เฉพาะตอน NOT ฟาร์มโทเคน)
    task.spawn(function()
        while blockLoopRunning do
            task.wait(1.5)

            if not currentBlock
            or not player.Character
            or not player.Character:FindFirstChild("HumanoidRootPart") then
                blockLoopRunning = false
                break
            end

            if not farmingToken then
                local hrp = player.Character.HumanoidRootPart
                if (hrp.Position - currentBlock.Position).Magnitude > RETURN_DISTANCE then
                    hrp.CFrame = CFrame.new(currentBlock.Position + Vector3.new(0, 3, 0))
                end
            end
        end
    end)
end

-- =====================================================
-- ♻️ Auto Respawn (HUD หาย = ล้ม/ตาย)
-- =====================================================
local function setupHUDListener(hud)
    local lastVisible = hud.Visible
    local sent = false

    hud:GetPropertyChangedSignal("Visible"):Connect(function()
        if hud.Visible == false and lastVisible == true and not sent then
            sent = true
            pcall(function()
                joinEvent:FireServer(true)
            end)
        elseif hud.Visible == true then
            sent = false
        end
        lastVisible = hud.Visible
    end)
end

local function listenHUD()
    local gui = player:WaitForChild("PlayerGui")

    local function hookShared(shared)
        local hud = shared:FindFirstChild("HUD")
        if hud then setupHUDListener(hud) end
        shared.ChildAdded:Connect(function(c)
            if c.Name == "HUD" then
                setupHUDListener(c)
            end
        end)
    end

    local shared = gui:FindFirstChild("Shared")
    if shared then hookShared(shared) end

    gui.ChildAdded:Connect(function(c)
        if c.Name == "Shared" then
            hookShared(c)
        end
    end)
end

listenHUD()

-- =====================================================
-- 🪙 Auto Farm Token (แก้แล้ว เก็บทันแน่นอน)
-- =====================================================
local function getTokenFolder()
    if Workspace:FindFirstChild("Game")
    and Workspace.Game:FindFirstChild("Effects")
    and Workspace.Game.Effects:FindFirstChild("Tickets") then
        return Workspace.Game.Effects.Tickets
    end
end

task.spawn(function()
    while true do
        if getgenv().FarmToken and not isInLobby() then
            farmingToken = true -- 🔓 ปิดการดึงกลับชั่วคราว

            local tokens = getTokenFolder()
            local char = player.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")

            if tokens and char and hrp then
                for _, token in ipairs(tokens:GetChildren()) do
                    if not getgenv().FarmToken then break end
                    local part = token:FindFirstChild("HumanoidRootPart")
                    if part then
                        hrp.CFrame = part.CFrame
                        task.wait(getgenv().TokenDelay) -- ⏱ รอให้เซิร์ฟเวอร์นับ
                    end
                end
            end

            farmingToken = false -- 🔒 เก็บเสร็จ → กลับขึ้น Safe Block
        end
        task.wait(1)
    end
end)

-- =====================================================
-- 👤 ตัวละครเกิดใหม่
-- =====================================================
player.CharacterAdded:Connect(function(char)
    task.wait(0.1)
    if not isInLobby() then
        createSafeBlock(char)
    end
end)

-- =====================================================
-- 🔄 MAIN LOOP (Join / สร้างบล็อก)
-- =====================================================
while true do
    if isInLobby() then
        if currentBlock then
            currentBlock:Destroy()
            currentBlock = nil
        end
        blockLoopRunning = false
        pcall(function()
            joinEvent:FireServer(true)
        end)
        task.wait(JOIN_INTERVAL)
    else
        if player.Character and not currentBlock then
            createSafeBlock(player.Character)
        end
        task.wait(2)
    end
end
