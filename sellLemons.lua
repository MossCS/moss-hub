--// Rayfield
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
    Name = "Sell Lemons | By MossC",
    LoadingTitle = "Sell Lemons | By MossC",
    LoadingSubtitle = "by MossC",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "LemonAutofarm",
        FileName = "LemonAutofarm",
    },
    KeySystem = false,
})

local MainTab = Window:CreateTab("Main", 4483362458)

--// Services
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

--// Find your tycoon. Wait for it, since on a fresh join it isn't there yet.
local function findTycoon()
    for _, v in pairs(workspace:GetChildren()) do
        if v:IsA("Folder") and v.Name:match("Tycoon%d") then
            if v:FindFirstChild("Owner") and v.Owner.Value == LocalPlayer then
                return v
            end
        end
    end
end

if not game:IsLoaded() then game.Loaded:Wait() end

local userTycoon
local _tStart = tick()
repeat
    userTycoon = findTycoon()
    if not userTycoon then task.wait(0.5) end
until userTycoon or tick() - _tStart > 30

if not userTycoon then
    Rayfield:Notify({
        Title = "Error",
        Content = "Tycoon not found (waited 30s)!",
        Duration = 5,
    })
    return
end

--// Variables
local AutoBuy = false
local AutoUpgrade = false
local AutoFruit = false
local AutoRebirth = false
local AutoEvolve = false
local AutoPowerLevel = false
local AutoAscend = false
local AutoPhoneOffers = false

-- live counters for the status panel (proof the autos are actually firing)
local stats = { buys = 0, upgrades = 0, fruit = 0, rebirths = 0, evolves = 0, ascends = 0, phone = 0 }

--// Game component access (read from the dump). The tycoon's client logic lives in
-- ReplicatedStorage component modules; tapping them lets us read exact values and call
-- the same methods the game does instead of scraping UI text. All pcall-guarded so a
-- missing module never breaks the rest of the script.
local RS = game:GetService("ReplicatedStorage")
local Tycoon
local CompClass = {}
pcall(function()
    Tycoon = require(RS.Modules.Tycoon.Tycoon)
    CompClass.Balances    = require(RS.Modules.Tycoon.Component.Client.ClientTycoonBalances)
    CompClass.Rebirth     = require(RS.Modules.Tycoon.Component.Client.ClientTycoonRebirth)
    CompClass.Ascension   = require(RS.Modules.Tycoon.Component.Client.ClientTycoonAscension)
    CompClass.PhoneOffers = require(RS.Modules.Tycoon.Component.Client.ClientTycoonPhoneOffers)
end)

-- resolve a live component fresh each call (cheap; avoids stale refs across rebirths)
local function comp(class)
    if not (Tycoon and class) then return nil end
    local ok, c = pcall(function()
        local lt = Tycoon.getLocal()
        return lt and lt:GetComponent(class)
    end)
    return ok and c or nil
end

local Buying = false

-- FASTER Auto Buy: every buyable item model has a child "Purchase" RemoteFunction
-- (e.g. ...ItemName.Purchase). We invoke it DIRECTLY instead of walking the
-- character to the button and firetouchinterest-ing it, so buying is instant and
-- works no matter where you are. The server still validates cost/availability.
local function buyAllAffordable()
    for _, obj in ipairs(userTycoon.Purchases:GetDescendants()) do
        if obj:IsA("Model") then
            local shown = obj:GetAttribute("Shown")
            local purchased = obj:GetAttribute("Purchased")
            if shown == true and purchased ~= true then
                local purchase = obj:FindFirstChild("Purchase")
                if purchase and purchase:IsA("RemoteFunction") then
                    pcall(function() purchase:InvokeServer() end)
                    stats.buys = stats.buys + 1
                end
            end
        end
    end
end

task.spawn(function()
    while true do
        task.wait(0.05)   -- a few sweeps per second is plenty for direct remotes

        if AutoBuy then
            pcall(buyAllAffordable)
        end
    end
end)

-- FASTER Auto Upgrade. The old version scanned thousands of tycoon objects EVERY
-- frame and fired 100 server calls per machine per frame (huge FPS/network drag).
-- Now we cache the Upgrade remotes, refreshing only every 3s (to catch tycoon
-- rebuilds), and each machine just climbs from its last reached level upward,
-- stopping as soon as the server rejects (can't afford / maxed). Once maxed it
-- costs ~nothing. The level tracker resets on refresh so it re-climbs as cash grows.
local upgradeRemotes  = {}
local upgradeLevel    = {}   -- [remote] = highest level reached this scan window
local lastUpgradeScan = 0

local function refreshUpgradeRemotes()
    upgradeRemotes = {}
    upgradeLevel   = {}
    local purchases = userTycoon:FindFirstChild("Purchases")
    if not purchases then return end
    for _, obj in ipairs(purchases:GetDescendants()) do
        if obj:IsA("RemoteFunction") and obj.Name == "Upgrade" then
            upgradeRemotes[#upgradeRemotes + 1] = obj
        end
    end
end

task.spawn(function()
    while true do
        task.wait(0.25)

        if AutoUpgrade then
            if tick() - lastUpgradeScan > 3 then
                refreshUpgradeRemotes()
                lastUpgradeScan = tick()
            end

            for _, remote in ipairs(upgradeRemotes) do
                if remote.Parent then
                    local lvl = (upgradeLevel[remote] or 0) + 1
                    while lvl <= 100 do
                        local ok, res = pcall(function() return remote:InvokeServer(lvl) end)
                        if (not ok) or res == false then break end
                        upgradeLevel[remote] = lvl
                        stats.upgrades = stats.upgrades + 1
                        lvl = lvl + 1
                    end
                end
            end
        end
    end
end)

--// Auto Power Level (RemoteFunction userTycoon.Remotes.UpgradePowerLevel)
-- Experimental: calls UpgradePowerLevel repeatedly; the server validates cost.
-- If the game needs an argument here we'll see it do nothing (harmless, pcall'd)
-- and can probe the exact arg like we did for WakeIncomeStream.
local function getPowerLevelRemote()
    local remotes = userTycoon:FindFirstChild("Remotes")
    return remotes and remotes:FindFirstChild("UpgradePowerLevel")
end

task.spawn(function()
    while true do
        task.wait(0.25)

        if AutoPowerLevel then
            local remote = getPowerLevelRemote()
            if remote then
                pcall(function() remote:InvokeServer() end)
            end
        end
    end
end)

--// Auto Rebirth (userTycoon.Remotes.Rebirth). Reads the rebirth menu's pending
-- investor count and only rebirths when it's worth it, so we don't spam rebuilds.
-- Default gate: rebirth when pending >= current * RebirthGainMultiple (1.0 = double).
local RebirthGainMultiple = 1.0
-- Optional stricter gate from the UI toggle: when on, rebirth only when pending is
-- at least RebirthInvestorMultiple times current (e.g. 10x).
local RebirthMultMode         = false
local RebirthInvestorMultiple = 10
local MinPotential        = 1
local RebirthCooldown     = 2     -- seconds to let the tycoon rebuild after each rebirth
local RebirthTimeout      = 8     -- max seconds to wait for "Rebirthed" before next
local rebirthBusy         = false

local function getRebirthRemote()
    local remotes = userTycoon:FindFirstChild("Remotes")
    return remotes and remotes:FindFirstChild("Rebirth")
end

local function getRebirthedSignal()
    local remotes = userTycoon:FindFirstChild("Remotes")
    return remotes and remotes:FindFirstChild("Rebirthed")
end

-- parse word/abbrev formatted numbers like "457.345 billion" or "22.4Qn"
local NUM_SCALE = {
    thousand=1e3, million=1e6, billion=1e9, trillion=1e12, quadrillion=1e15,
    quintillion=1e18, sextillion=1e21, septillion=1e24, octillion=1e27,
    nonillion=1e30, decillion=1e33, undecillion=1e36, duodecillion=1e39,
    tredecillion=1e42, quattuordecillion=1e45, quindecillion=1e48,
    sexdecillion=1e51, septendecillion=1e54, octodecillion=1e57,
    novemdecillion=1e60, vigintillion=1e63,
    k=1e3, m=1e6, b=1e9, t=1e12, qd=1e15, qn=1e18, sx=1e21, sp=1e24,
}

-- Build the names past vigintillion exactly like the game's Modules.Huge does, so the
-- text fallback matches the UI at every tier. Note prefix index 3 is "tres" (the game
-- shows "tresvigintillion", not "trevigintillion"). Covers up to centillion (1e303).
do
    local BASE = {
        [0]="thousand",[1]="million",[2]="billion",[3]="trillion",[4]="quadrillion",
        [5]="quintillion",[6]="sextillion",[7]="septillion",[8]="octillion",[9]="nonillion",
        [10]="decillion",[11]="undecillion",[12]="duodecillion",[13]="tredecillion",
        [14]="quattuordecillion",[15]="quindecillion",[16]="sexdecillion",
        [17]="septendecillion",[18]="octodecillion",[19]="novemdecillion",
    }
    local ROOT = {
        [2]="vigintillion",[3]="trigintillion",[4]="quadragintillion",[5]="quinquagintillion",
        [6]="sexagintillion",[7]="septuagintillion",[8]="octogintillion",[9]="nonagintillion",
        [10]="centillion",
    }
    local PREFIX = {
        [0]="",[1]="un",[2]="duo",[3]="tres",[4]="quattuor",[5]="quin",
        [6]="sex",[7]="septen",[8]="octo",[9]="novem",
    }
    for n = 0, 100 do                       -- n = 0-based illion index; magnitude 10^((n+1)*3)
        local name
        if n < 20 then
            name = BASE[n]
        else
            name = PREFIX[n % 10] .. ROOT[n // 10]
        end
        if name and name ~= "" then NUM_SCALE[name] = 10 ^ ((n + 1) * 3) end
    end
end

local function parseNumber(s)
    if not s then return nil end
    s = tostring(s):gsub(",", ""):lower()
    local num = s:match("[%d%.]+")
    local val = num and tonumber(num)
    if not val then return nil end
    local word = s:match("[%d%.%s]+([a-z]+)")
    if word and NUM_SCALE[word] then val = val * NUM_SCALE[word] end
    return val
end

-- read the InvestorsMenu values (works whether or not the menu is open)
local function investorBody()
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local r  = pg and pg:FindFirstChild("Rebirth")
    local im = r and r:FindFirstChild("InvestorsMenu")
    return im and im:FindFirstChild("Body")
end
local function readQuantity(frameName)
    local body  = investorBody()
    local frame = body and body:FindFirstChild(frameName)
    local q     = frame and frame:FindFirstChild("Quantity")
    return q and parseNumber(q.Text)
end
local function getCurrentInvestors()   return readQuantity("Amount")    or 0 end
local function getPotentialInvestors() return readQuantity("Potential")       end

-- Exact investor values straight from the game's components (stored as log10 "Huge").
-- Returns potentialLog, currentLog, or nil if the components aren't ready yet.
local function getInvestorLogs()
    local bal = comp(CompClass.Balances)
    local reb = comp(CompClass.Rebirth)
    if not (bal and reb) then return nil end
    local okp, p = pcall(function() return reb:GetPotentialInvestors() end)
    local okc, c = pcall(function() return bal:GetInvestors() end)
    if okp and okc and type(p) == "number" and type(c) == "number" then
        return p, c
    end
    return nil
end

task.spawn(function()
    while true do
        task.wait(0.5)

        if AutoRebirth and not rebirthBusy then
            local remote = getRebirthRemote()
            -- pick the gate: stricter Nx mode if the toggle is on, else the 1x gate
            local mult   = RebirthMultMode and RebirthInvestorMultiple or RebirthGainMultiple

            local worthIt = false
            local potLog, curLog = getInvestorLogs()
            if remote and potLog then
                -- exact log-space gate: pending >= current*mult AND pending >= MinPotential
                worthIt = potLog >= math.log10(MinPotential)
                    and potLog >= curLog + math.log10(mult)
            elseif remote then
                -- fallback to parsing the InvestorsMenu text
                local potential = getPotentialInvestors()
                local current   = getCurrentInvestors()
                worthIt = potential ~= nil
                    and potential >= MinPotential
                    and potential >= current * mult
            end

            if worthIt then
                rebirthBusy = true

                pcall(function()
                    local done   = false
                    local signal = getRebirthedSignal()
                    local conn
                    if signal and signal:IsA("RemoteEvent") then
                        conn = signal.OnClientEvent:Connect(function() done = true end)
                    end

                    remote:InvokeServer()   -- yields until the server responds
                    stats.rebirths = stats.rebirths + 1

                    local t = 0
                    while not done and t < RebirthTimeout do
                        task.wait(0.1)
                        t = t + 0.1
                    end
                    if conn then conn:Disconnect() end
                end)

                task.wait(RebirthCooldown)   -- let the tycoon settle before next
                rebirthBusy = false
            end
        end
    end
end)

--// Auto Evolve - OPTIMAL (RemoteFunction userTycoon.Remotes.Evolve)
-- Evolution gives x10 income SPEED each, but you can only evolve once the
-- evolution progress bar fills. We read EvolutionMenu.Body.Progress ("1.9%")
-- and evolve when it reaches EvolveAt%. Waits for the "Evolved" event, like rebirth.
local EvolveAt        = 100   -- % progress required before evolving (100 = full bar)
local EvolveCooldown  = 2
local EvolveTimeout   = 8
local evolveBusy      = false

local function getEvolveRemote()
    local remotes = userTycoon:FindFirstChild("Remotes")
    return remotes and remotes:FindFirstChild("Evolve")
end
local function getEvolvedSignal()
    local remotes = userTycoon:FindFirstChild("Remotes")
    return remotes and remotes:FindFirstChild("Evolved")
end
local function getEvolveProgress()
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local r  = pg and pg:FindFirstChild("Rebirth")
    local em = r and r:FindFirstChild("EvolutionMenu")
    local body = em and em:FindFirstChild("Body")
    local p  = body and body:FindFirstChild("Progress")
    if not p then return nil end
    return tonumber(tostring(p.Text):match("[%d%.]+"))
end

task.spawn(function()
    while true do
        task.wait(0.5)

        if AutoEvolve and not evolveBusy then
            local remote   = getEvolveRemote()
            local progress = getEvolveProgress()

            if remote and progress and progress >= EvolveAt then
                evolveBusy = true
                pcall(function()
                    local done   = false
                    local signal = getEvolvedSignal()
                    local conn
                    if signal and signal:IsA("RemoteEvent") then
                        conn = signal.OnClientEvent:Connect(function() done = true end)
                    end
                    remote:InvokeServer()
                    stats.evolves = stats.evolves + 1
                    local t = 0
                    while not done and t < EvolveTimeout do
                        task.wait(0.1); t = t + 0.1
                    end
                    if conn then conn:Disconnect() end
                end)
                task.wait(EvolveCooldown)
                evolveBusy = false
            end
        end
    end
end)

--// Pull All Levers - the 4 colored sewer door levers (Map.Sewer.Doors*.Lever).
-- They're touch-activated (no prompt/clickdetector), so we firetouchinterest each
-- one. Also touches the sewer collectible keys (CashVine / SewerAlien) so the run
-- actually pays out. Returns how many levers it pulled.
local function pullAllLevers()
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return 0 end

    local map   = workspace:FindFirstChild("Map")
    local sewer = map and map:FindFirstChild("Sewer")
    local root  = sewer or workspace

    local pulled = 0
    for _, o in ipairs(root:GetDescendants()) do
        if o:IsA("BasePart") and (o.Name == "Lever" or string.find(string.lower(o.Name), "lever", 1, true)) then
            pcall(function()
                firetouchinterest(hrp, o, 0)
                firetouchinterest(hrp, o, 1)
            end)
            pulled = pulled + 1
        end
    end

    -- touch the sewer collectible keys so the reward is actually grabbed
    if sewer then
        for _, o in ipairs(sewer:GetDescendants()) do
            if o:IsA("BasePart") and (o.Name == "VineKey" or o.Name == "UFOKey") then
                pcall(function()
                    firetouchinterest(hrp, o, 0)
                    firetouchinterest(hrp, o, 1)
                end)
            end
        end
    end

    return pulled
end

--// Sewer Run - pull levers + grab keys + open door from where you are (these
-- fire fine at range), then TELEPORT only to the CashVine to harvest the reward.
local function touchPart(hrp, part)
    pcall(function()
        firetouchinterest(hrp, part, 0)
        firetouchinterest(hrp, part, 1)
    end)
end

local function doSewerRun()
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false, "no character" end

    local map   = workspace:FindFirstChild("Map")
    local sewer = map and map:FindFirstChild("Sewer")
    if not sewer then return false, "sewer not loaded" end

    -- 1) pull all levers (fired in place)
    for _, o in ipairs(sewer:GetDescendants()) do
        if o:IsA("BasePart") and string.find(string.lower(o.Name), "lever", 1, true) then
            touchPart(hrp, o)
        end
    end

    -- 2) grab the keys (VineKey = door key, UFOKey = investor boost)
    for _, folderName in ipairs({ "CashVine", "SewerAlien" }) do
        local folder = sewer:FindFirstChild(folderName)
        if folder then
            for _, o in ipairs(folder:GetDescendants()) do
                if o:IsA("BasePart") and (o.Name == "VineKey" or o.Name == "UFOKey") then
                    touchPart(hrp, o)
                end
            end
        end
    end
    task.wait(0.3)

    local cashVine = sewer:FindFirstChild("CashVine")

    -- 3) open the VineDoor (fired in place; we now hold the key)
    if cashVine then
        local vineDoor = cashVine:FindFirstChild("VineDoor")
        if vineDoor then
            for _, o in ipairs(vineDoor:GetDescendants()) do
                if o:IsA("BasePart") then touchPart(hrp, o) end
            end
        end
    end
    task.wait(0.3)

    -- 4) TELEPORT to the CashVine and harvest it
    if cashVine then
        local vineModel = cashVine:FindFirstChild("CashVine")
        if vineModel then
            local pivot = vineModel:GetPivot()
            pcall(function() hrp.CFrame = pivot + Vector3.new(0, 3, 0) end)
            task.wait(0.2)
            for _, o in ipairs(vineModel:GetDescendants()) do
                if o:IsA("BasePart") then touchPart(hrp, o) end
            end
        end
    end

    return true
end

--// Teleport to the Sewer Alien - fixed coordinates
local SEWER_ALIEN_POS = Vector3.new(-42, -41, 180)
local function teleportToAlien()
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false, "no character" end

    pcall(function() hrp.CFrame = CFrame.new(SEWER_ALIEN_POS) end)
    return true
end

local Trees = {}

local function addTree(obj)
    if obj:IsA("Model") and obj.Name == "LemonTree" then

        if not table.find(Trees, obj) then
            table.insert(Trees, obj)
        end
    end
end

local function removeTree(obj)

    local index = table.find(Trees, obj)

    if index then
        table.remove(Trees, index)
    end
end

-- initial scan
for _, v in ipairs(workspace:GetDescendants()) do
    addTree(v)
end

-- realtime update
workspace.DescendantAdded:Connect(addTree)
workspace.DescendantRemoving:Connect(removeTree)

local function noCollisionTree(tree)

    for _, obj in ipairs(tree:GetDescendants()) do
        if obj:IsA("BasePart") then
            obj.CanCollide = false
        end
    end
end

local function teleportToTree(tree)

    local character = LocalPlayer.Character
    if not character then
        return false
    end

    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then
        return false
    end

    local cf = tree:GetPivot()

    hrp.CFrame = cf + Vector3.new(0, 5, 0)

    return true
end

local function collectFruit(tree)

    noCollisionTree(tree)

    local success = teleportToTree(tree)

    if not success then
        return
    end

    for _, obj in ipairs(tree:GetDescendants()) do

        if obj:IsA("BasePart") and obj.Name == "Fruit" then

            obj.CanCollide = false

            local clickPart = obj:FindFirstChild("ClickPart")

            if clickPart then

                local detector = clickPart:FindFirstChildOfClass("ClickDetector")

                if detector then

                    task.wait(0.45)

                    pcall(function()
                        fireclickdetector(detector)
                    end)
                    stats.fruit = stats.fruit + 1
                end
            end
        end
    end
end

task.spawn(function()
    while true do
        task.wait(0.1)

        if AutoFruit then

            for _, tree in ipairs(Trees) do

                if not AutoFruit then
                    break
                end

                if tree and tree.Parent then

                    pcall(function()
                        collectFruit(tree)
                    end)
                end
            end
        end
    end
end)


--// Auto Accept Phone Offers. The server fires userTycoon.Remotes.PhoneOffer with a
-- number when an offer is live; firing back "Accept" takes the deal. Remote-based so the
-- connection survives rebirths; the component is only used to spot an already-open offer.
task.spawn(function()
    local remotes = userTycoon:FindFirstChild("Remotes")
    local phone   = remotes and remotes:WaitForChild("PhoneOffer", 30)
    if not phone then return end

    local function accept()
        if AutoPhoneOffers then
            pcall(function() phone:FireServer("Accept") end)
            stats.phone = stats.phone + 1
        end
    end

    phone.OnClientEvent:Connect(function(v)
        if type(v) == "number" then accept() end   -- a number means an offer is on the table
    end)

    -- backstop: catch an offer that was already live when the toggle got flipped on
    while true do
        task.wait(0.5)
        if AutoPhoneOffers then
            local po, cur = comp(CompClass.PhoneOffers)
            if po then pcall(function() cur = po:GetCurrentOffer() end) end
            if type(cur) == "number" then accept() end
        end
    end
end)

--// Auto Ascend (optimal). Ascension resets the tycoon for a permanent cash multiplier
-- and becomes available once every purchase is bought (GetAscensionProgress hits 1).
-- Mirrors the rebirth flow: invoke the Ascend remote, wait for "Ascended", then cooldown.
local AscendCooldown = 2
local AscendTimeout  = 8
local ascendBusy     = false

local function getAscendRemote()
    local remotes = userTycoon:FindFirstChild("Remotes")
    return remotes and remotes:FindFirstChild("Ascend")
end
local function getAscendedSignal()
    local remotes = userTycoon:FindFirstChild("Remotes")
    return remotes and remotes:FindFirstChild("Ascended")
end

task.spawn(function()
    while true do
        task.wait(0.5)

        if AutoAscend and not ascendBusy then
            local remote   = getAscendRemote()
            local asc      = comp(CompClass.Ascension)
            local progress
            if asc then pcall(function() progress = asc:GetAscensionProgress() end) end

            if remote and progress and progress >= 1 then
                ascendBusy = true
                pcall(function()
                    local done   = false
                    local signal = getAscendedSignal()
                    local conn
                    if signal and signal:IsA("RemoteEvent") then
                        conn = signal.OnClientEvent:Connect(function() done = true end)
                    end
                    remote:InvokeServer()
                    stats.ascends = stats.ascends + 1
                    local t = 0
                    while not done and t < AscendTimeout do
                        task.wait(0.1); t = t + 0.1
                    end
                    if conn then conn:Disconnect() end
                end)
                task.wait(AscendCooldown)
                ascendBusy = false
            end
        end
    end
end)

--// Anti-AFK + Auto Rejoin. Anti-AFK is always on to beat the 20 min idle kick.
-- Auto Rejoin (toggle) teleports back into the same place on a disconnect.
local AutoRejoin      = false
local TeleportService = game:GetService("TeleportService")
local VirtualUser     = game:GetService("VirtualUser")
local PLACE_ID        = game.PlaceId

LocalPlayer.Idled:Connect(function()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end)

local function tryRejoin()
    if not AutoRejoin then return end
    pcall(function()
        local players = Players:GetPlayers()
        if #players <= 1 then
            TeleportService:Teleport(PLACE_ID, LocalPlayer)
        else
            -- prefer the same server instance when we can
            TeleportService:TeleportToPlaceInstance(PLACE_ID, game.JobId, LocalPlayer)
        end
    end)
end

-- Primary detector: the disconnect/error dialog. ErrorMessageChanged isn't on every
-- client build, so it's pcall-guarded; the CoreGui prompt watcher below is the backup.
pcall(function()
    game:GetService("GuiService").ErrorMessageChanged:Connect(function()
        if AutoRejoin then task.wait(0.5); tryRejoin() end
    end)
end)

-- Backup detector: watch CoreGui for the Roblox "you were disconnected / reconnect"
-- prompt appearing, then rejoin.
task.spawn(function()
    local cg = game:GetService("CoreGui")
    cg.DescendantAdded:Connect(function(d)
        if not AutoRejoin then return end
        local n = string.lower(d.Name)
        if n:find("disconnect") or n:find("reconnect") or n:find("errorprompt") then
            task.wait(0.5); tryRejoin()
        end
    end)
end)

TeleportService.TeleportInitFailed:Connect(function(_, _, _)
    if AutoRejoin then task.wait(2); tryRejoin() end
end)

MainTab:CreateToggle({
    Name = "Auto Buy",
    CurrentValue = false,
    Flag = "AutoBuy",
    Callback = function(Value)
        AutoBuy = Value

        Rayfield:Notify({
            Title = "Auto Buy",
            Content = Value and "Enabled" or "Disabled",
            Duration = 3,
        })
    end,
})

MainTab:CreateToggle({
    Name = "Auto Upgrade",
    CurrentValue = false,
    Flag = "AutoUpgrade",
    Callback = function(Value)
        AutoUpgrade = Value

        Rayfield:Notify({
            Title = "Auto Upgrade",
            Content = Value and "Enabled" or "Disabled",
            Duration = 3,
        })
    end,
})

MainTab:CreateToggle({
    Name = "Auto Fruit",
    CurrentValue = false,
    Flag = "AutoFruit",
    Callback = function(Value)
        AutoFruit = Value

        Rayfield:Notify({
            Title = "Auto Fruit",
            Content = Value and "Enabled" or "Disabled",
            Duration = 3,
        })
    end,
})

MainTab:CreateToggle({
    Name = "Auto Rebirth",
    CurrentValue = false,
    Flag = "AutoRebirth",
    Callback = function(Value)
        AutoRebirth = Value

        if Value and not getRebirthRemote() then
            Rayfield:Notify({
                Title = "Auto Rebirth",
                Content = "Rebirth remote not found in your tycoon!",
                Duration = 5,
            })
            return
        end

        Rayfield:Notify({
            Title = "Auto Rebirth",
            Content = Value and "Enabled" or "Disabled",
            Duration = 3,
        })
    end,
})

MainTab:CreateToggle({
    Name = "Rebirth only at big multiple",
    CurrentValue = false,
    Flag = "RebirthMultMode",
    Callback = function(Value)
        RebirthMultMode = Value
        Rayfield:Notify({
            Title = "Rebirth Multiple Gate",
            Content = Value
                and ("Enabled - only rebirth at " .. RebirthInvestorMultiple .. "x current investors")
                or "Disabled (using normal gate)",
            Duration = 3,
        })
    end,
})

MainTab:CreateInput({
    Name = "Rebirth at this many x current investors",
    CurrentValue = "10",
    PlaceholderText = "e.g. 10",
    RemoveTextAfterFocusLost = false,
    Flag = "RebirthInvestorMultiple",
    Callback = function(Text)
        local n = tonumber((tostring(Text):gsub("[^%d%.]", "")))
        if n and n > 0 then
            RebirthInvestorMultiple = n
            Rayfield:Notify({
                Title = "Rebirth Multiple",
                Content = "Will rebirth at " .. n .. "x current investors (when gate is on)",
                Duration = 3,
            })
        else
            Rayfield:Notify({
                Title = "Rebirth Multiple",
                Content = "Enter a number > 0 (e.g. 10)",
                Duration = 3,
            })
        end
    end,
})

MainTab:CreateToggle({
    Name = "Auto Evolve (x10 income)",
    CurrentValue = false,
    Flag = "AutoEvolve",
    Callback = function(Value)
        AutoEvolve = Value

        if Value and not getEvolveRemote() then
            Rayfield:Notify({
                Title = "Auto Evolve",
                Content = "Evolve remote not found in your tycoon!",
                Duration = 5,
            })
            return
        end

        Rayfield:Notify({
            Title = "Auto Evolve",
            Content = Value and "Enabled (evolves at full progress)" or "Disabled",
            Duration = 3,
        })
    end,
})

MainTab:CreateToggle({
    Name = "Auto Ascend (all-purchases reset)",
    CurrentValue = false,
    Flag = "AutoAscend",
    Callback = function(Value)
        AutoAscend = Value

        if Value and not getAscendRemote() then
            Rayfield:Notify({
                Title = "Auto Ascend",
                Content = "Ascend remote not found in your tycoon!",
                Duration = 5,
            })
            return
        end

        Rayfield:Notify({
            Title = "Auto Ascend",
            Content = Value and "Enabled (ascends when all purchases are bought)" or "Disabled",
            Duration = 3,
        })
    end,
})

MainTab:CreateToggle({
    Name = "Auto Accept Phone Offers",
    CurrentValue = false,
    Flag = "AutoPhoneOffers",
    Callback = function(Value)
        AutoPhoneOffers = Value

        Rayfield:Notify({
            Title = "Auto Phone Offers",
            Content = Value and "Enabled (accepts offers instantly)" or "Disabled",
            Duration = 3,
        })
    end,
})

MainTab:CreateToggle({
    Name = "Auto Power Level",
    CurrentValue = false,
    Flag = "AutoPowerLevel",
    Callback = function(Value)
        AutoPowerLevel = Value

        Rayfield:Notify({
            Title = "Auto Power Level",
            Content = Value and "Enabled" or "Disabled",
            Duration = 3,
        })
    end,
})

MainTab:CreateToggle({
    Name = "Auto Rejoin (on disconnect)",
    CurrentValue = false,
    Flag = "AutoRejoin",
    Callback = function(Value)
        AutoRejoin = Value
        Rayfield:Notify({
            Title = "Auto Rejoin",
            Content = Value and "Enabled - will rejoin if disconnected (anti-AFK always on)"
                or "Disabled",
            Duration = 3,
        })
    end,
})

MainTab:CreateButton({
    Name = "Pull All Levers (sewer)",
    Callback = function()
        local n = pullAllLevers()
        Rayfield:Notify({
            Title = "Pull All Levers",
            Content = n > 0 and ("Pulled " .. n .. " lever(s) + grabbed sewer keys")
                or "No levers found (is the sewer loaded?)",
            Duration = 4,
        })
    end,
})

MainTab:CreateButton({
    Name = "Vine Harvest",
    Callback = function()
        Rayfield:Notify({ Title = "Vine Harvest", Content = "Running...", Duration = 2 })
        task.spawn(function()
            local ok, err = doSewerRun()
            Rayfield:Notify({
                Title = "Vine Harvest",
                Content = ok and "Done! Levers pulled, keys grabbed, vine harvested."
                    or ("Failed: " .. tostring(err)),
                Duration = 5,
            })
        end)
    end,
})

MainTab:CreateButton({
    Name = "Teleport to Sewer Alien",
    Callback = function()
        local ok, err = teleportToAlien()
        Rayfield:Notify({
            Title = "Teleport to Sewer Alien",
            Content = ok and "Teleported to the sewer alien (UFO)" or ("Failed: " .. tostring(err)),
            Duration = 3,
        })
    end,
})

MainTab:CreateButton({
    Name = "Destroy GUI",
    Callback = function()
        Rayfield:Destroy()
    end,
})

--// LIVE STATUS PANEL - proves the autos are firing (counters tick, FPS, cash).
-- Native Instance.new GUI (Delta-safe), draggable, parented to PlayerGui.
task.spawn(function()
    local parent = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not parent then
        local okh, hui = pcall(function() return gethui() end)
        parent = (okh and hui) or game:GetService("CoreGui")
    end
    pcall(function()
        local old = parent:FindFirstChild("AutoStatusGui")
        if old then old:Destroy() end
    end)

    local gui = Instance.new("ScreenGui")
    gui.Name = "AutoStatusGui"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 9999
    gui.Parent = parent

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 200, 0, 198)
    frame.Position = UDim2.new(0, 10, 0, 90)
    frame.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
    frame.BackgroundTransparency = 0.1
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Parent = gui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 24)
    title.BackgroundColor3 = Color3.fromRGB(38, 40, 54)
    title.BorderSizePixel = 0
    title.Text = "AUTO STATUS"
    title.TextColor3 = Color3.fromRGB(120, 235, 140)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 13
    title.Parent = frame
    Instance.new("UICorner", title).CornerRadius = UDim.new(0, 8)

    local body = Instance.new("TextLabel")
    body.Size = UDim2.new(1, -12, 1, -30)
    body.Position = UDim2.new(0, 8, 0, 28)
    body.BackgroundTransparency = 1
    body.TextXAlignment = Enum.TextXAlignment.Left
    body.TextYAlignment = Enum.TextYAlignment.Top
    body.RichText = true
    body.Text = "starting..."
    body.TextColor3 = Color3.fromRGB(235, 235, 245)
    body.Font = Enum.Font.Code
    body.TextSize = 12
    body.Parent = frame

    -- drag (mouse + touch)
    local UIS = game:GetService("UserInputService")
    local dragging, ds, sp
    title.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
           or i.UserInputType == Enum.UserInputType.Touch then
            dragging, ds, sp = true, i.Position, frame.Position
            i.Changed:Connect(function()
                if i.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
           or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - ds
            frame.Position = UDim2.new(sp.X.Scale, sp.X.Offset + d.X, sp.Y.Scale, sp.Y.Offset + d.Y)
        end
    end)

    -- FPS counter
    local RunService = game:GetService("RunService")
    local frames, fps, fpsT = 0, 0, tick()
    RunService.RenderStepped:Connect(function()
        frames = frames + 1
        if tick() - fpsT >= 1 then fps, frames, fpsT = frames, 0, tick() end
    end)

    local function on(b) return b and "<font color='#7CFF7C'>ON</font>" or "<font color='#777'>off</font>" end

    while gui.Parent do
        local cashStr = "?"
        local ls = LocalPlayer:FindFirstChild("leaderstats")
        local c  = ls and ls:FindFirstChild("Cash")
        if c then cashStr = tostring(c.Value) end

        body.Text = string.format(
            "FPS:  %d\nCash: %s\n"
          .. "Buys:  %d  %s\nUpgr:  %d  %s\nFruit: %d  %s\nReb:   %d  %s\nEvo:   %d  %s\n"
          .. "Asc:   %d  %s\nPhone: %d  %s",
            fps, cashStr,
            stats.buys,     on(AutoBuy),
            stats.upgrades, on(AutoUpgrade),
            stats.fruit,    on(AutoFruit),
            stats.rebirths, on(AutoRebirth),
            stats.evolves,  on(AutoEvolve),
            stats.ascends,  on(AutoAscend),
            stats.phone,    on(AutoPhoneOffers)
        )
        task.wait(0.25)
    end
end)

--// Keep the Rayfield window on-screen so minimizing near the top can't push the
-- drag bar off-screen and lock you out. Only nudges it back when out of bounds.
task.spawn(function()
    local parent
    pcall(function() parent = (gethui and gethui()) end)
    parent = parent or game:GetService("CoreGui")

    local rg, main
    local t0 = tick()
    repeat
        rg = parent:FindFirstChild("Rayfield")
        if rg then
            main = rg:FindFirstChild("Main")
            if not main then  -- fallback: largest Frame directly under the gui
                for _, c in ipairs(rg:GetChildren()) do
                    if c:IsA("Frame") then main = main or c end
                end
            end
        end
        if not (rg and main) then task.wait(0.25) end
    until (rg and main) or tick() - t0 > 20
    if not (rg and main) then return end

    local cam = workspace.CurrentCamera
    local function clamp()
        if not main.Parent then return end
        local vp  = (cam and cam.ViewportSize) or Vector2.new(1280, 720)
        local sz  = main.AbsoluteSize
        local pos = main.AbsolutePosition          -- top-left, anchor-independent
        local topMargin  = 38                       -- stay below the Roblox topbar
        local keepOnX    = math.min(120, sz.X)      -- always-visible slice horizontally
        local keepOnY    = math.min(46, sz.Y)       -- always-visible slice vertically
        local maxX = math.max(0, vp.X - keepOnX)
        local maxY = math.max(topMargin, vp.Y - keepOnY)
        local nx = math.clamp(pos.X, 0, maxX)
        local ny = math.clamp(pos.Y, topMargin, maxY)
        if math.abs(nx - pos.X) > 0.5 or math.abs(ny - pos.Y) > 0.5 then
            local ax, ay = main.AnchorPoint.X, main.AnchorPoint.Y
            main.Position = UDim2.fromOffset(nx + ax * sz.X, ny + ay * sz.Y)
        end
    end

    pcall(function()
        main:GetPropertyChangedSignal("AbsolutePosition"):Connect(clamp)
        main:GetPropertyChangedSignal("AbsoluteSize"):Connect(clamp)
    end)
    while main.Parent do clamp(); task.wait(0.3) end
end)

Rayfield:Notify({
    Title = "Loaded",
    Content = "Tycoon Autofarm Loaded Successfully",
    Duration = 5,
})