local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local pgui = player:WaitForChild("PlayerGui")

-- Window
local Window = Rayfield:CreateWindow({
   Name = "Craft Food | By MossC",
   LoadingTitle = "Craft Food | By MossC",
   LoadingSubtitle = "by MossC",
   Theme = "Default", 
   ShowText = "Toggle",
   ConfigurationSaving = {
      Enabled = true,
      FolderName = "mosshub",
      FileName = "Moss Hub"
   },
   KeySystem = false,
})

_G.IsLoadingConfig = true

-- AUTO BUY
local AutoBuyTab = Window:CreateTab("Auto Buy", "shopping-cart")

local Items = {
   {id = 1, name = "Flour"},      
   {id = 2, name = "Milk"},
   {id = 3, name = "Eggs"},       
   {id = 4, name = "Sugar"},
   {id = 5, name = "Potato"},     
   {id = 6, name = "Carrot"},
   {id = 7, name = "Tomato"},     
   {id = 8, name = "Lettuce"},
   {id = 9, name = "Meat"},       
   {id = 10, name = "Lemon"},
   {id = 11, name = "Strawberry"},
   {id = 12, name = "Banana"},
   {id = 13, name = "Blueberry"}, 
   {id = 14, name = "Cocoa"},
   {id = 15, name = "Seafood"},   
   {id = 16, name = "Bean"}
}

local Loops = {}

-- RESTOCK
local RestockLabel = AutoBuyTab:CreateLabel("🛒 Restock dalam Loading...")
local LastText = ""

local function UpdateCountdown()
   local buyGui = pgui:FindFirstChild("BuyScreenGui")
   if not buyGui then
      local newText = "🛒 Restock dalam "
      if newText ~= LastText then
         RestockLabel:Set(newText)
         LastText = newText
      end
      return
   end
   
   local frame1 = buyGui:FindFirstChild("Frame")
   if not frame1 then return end
   
   local frame2 = frame1:FindFirstChild("Frame")
   if not frame2 then return end
   
   local imageLabel = frame2:FindFirstChild("ImageLabel")
   if not imageLabel then return end
   
   local frame3 = imageLabel:FindFirstChild("Frame")
   if not frame3 then return end
   
   local headFrame = frame3:FindFirstChild("HeadFrame")
   if not headFrame then return end
   
   local timerLabel = headFrame:FindFirstChild("TimeTextLabel")
   if not timerLabel or timerLabel.Text == "" then return end
   
   local newText = "🛒 Restock dalam " .. timerLabel.Text
   
   if newText ~= LastText then
      RestockLabel:Set(newText)
      LastText = newText
   end
end

RunService.Heartbeat:Connect(function()
   task.wait(1)
   pcall(UpdateCountdown)
end)

task.delay(1, function()
   pcall(UpdateCountdown)
end)

-- MONEY
local MoneyLabel = AutoBuyTab:CreateLabel("💸 Sisa Uang : Loading...")
local LastMoneyText = ""

local function UpdatePlayerMoney()
   local playerGui = player:WaitForChild("PlayerGui")
   local goldGui = playerGui:FindFirstChild("GoldScreenGui")
   if not goldGui then
      local newText = "💸 Sisa Uang : Buka game lebih lama / tunggu load"
      if newText ~= LastMoneyText then
         MoneyLabel:Set(newText)
         LastMoneyText = newText
      end
      return
   end
   
   local frame = goldGui:FindFirstChild("Frame")
   if not frame then return end
   
   local textLabel = frame:FindFirstChild("TextLabel")
   if not textLabel or textLabel.Text == "" then return end
   
   local newText = "💸 Sisa Uang : " .. textLabel.Text
   
   if newText ~= LastMoneyText then
      MoneyLabel:Set(newText)
      LastMoneyText = newText
   end
end

RunService.Heartbeat:Connect(function()
   task.wait(1.2)
   pcall(UpdatePlayerMoney)
end)

task.delay(1.5, function()
   pcall(UpdatePlayerMoney)
end)

-- AUTO BUY
local function CreateAutoBuyToggle(item)
   local toggleName = "Auto Buy " .. item.name
   local flagName = "AutoBuy_" .. item.name
   
   local Toggle = AutoBuyTab:CreateToggle({
      Name = toggleName,
      CurrentValue = false,
      Flag = flagName, 
      Callback = function(Value)
         _G[flagName] = Value
         
         if Value then
            Rayfield:Notify({
               Title = toggleName .. " Enabled",
               Content = "Auto purchasing " .. item.name,
               Duration = 3.5,
               Image = "check"
            })
         else
            Rayfield:Notify({
               Title = toggleName .. " Disabled",
               Content = "Stopped auto purchasing " .. item.name,
               Duration = 3.5,
               Image = "x"
            })
         end
      end,
   })
end

for _, item in ipairs(Items) do
   CreateAutoBuyToggle(item)
end

task.spawn(function()
   while true do
      task.wait(1.8)  
      
      for _, item in ipairs(Items) do
         local flagName = "AutoBuy_" .. item.name
         local shouldRun = _G[flagName] or Rayfield.Flags[flagName] or false
         
         if shouldRun then
            if not Loops[item.name] or coroutine.status(Loops[item.name]) == "dead" then
               Loops[item.name] = task.spawn(function()
                  while task.wait(2) do
                     if not (_G[flagName] or Rayfield.Flags[flagName]) then break end
                     
                     pcall(function()
                        game:GetService("ReplicatedStorage")
                           :WaitForChild("EventFolder")
                           :WaitForChild("BuyEvent")
                           :FireServer(item.id)
                     end)
                  end
                  
                  Loops[item.name] = nil  
               end)
            end
         else
            if Loops[item.name] then
               task.cancel(Loops[item.name])
               Loops[item.name] = nil
            end
         end
      end
   end
end)

-- UTILITY
local UtilityTab = Window:CreateTab("Utility", "wrench")
local AntiAFKRunning = false

UtilityTab:CreateToggle({
   Name = "Anti AFK",
   CurrentValue = false,
   Flag = "AntiAFK",
   Callback = function(Value)
      if _G.IsLoadingConfig then return end
      
      if Value then
         Rayfield:Notify({
            Title = "Anti AFK Enabled",
            Content = "You will no longer be kicked for being AFK",
            Duration = 4,
            Image = "shield"
         })
         
         AntiAFKRunning = true
         task.spawn(function()
            while AntiAFKRunning do
               local vu = game:GetService("VirtualUser")
               vu:CaptureController()
               vu:ClickButton2(Vector2.new())
               task.wait(60) 
            end
         end)
      else
         Rayfield:Notify({
            Title = "Anti AFK Disabled",
            Content = "Anti AFK has been turned off",
            Duration = 4,
            Image = "x"
         })
         AntiAFKRunning = false
      end
   end,
})

Rayfield:LoadConfiguration()

task.delay(0.5, function()
   _G.IsLoadingConfig = false
end)