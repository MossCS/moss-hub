-- UI Library
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

-- Window
local Window = Rayfield:CreateWindow({
   Name = "Craft Food | By MossC",
   Icon = 0, 
   LoadingTitle = "Craft Food | By MossC",
   LoadingSubtitle = "by MossC",
   ShowText = "Toggle",
   Theme = "Default", 

   ToggleUIKeybind = "K", 

   DisableRayfieldPrompts = false,
   DisableBuildWarnings = false, 

   ConfigurationSaving = {
      Enabled = true,
      FolderName = "mosshub",
      FileName = "Moss Hub"
   },

   Discord = {
      Enabled = false, 
      Invite = "noinvitelink", 
      RememberJoins = true 
   },

   KeySystem = false, 
   KeySettings = {
      Title = "Untitled",
      Subtitle = "Key System",
      Note = "No method of obtaining the key is provided", 
      FileName = "Key", 
      SaveKey = true,
      GrabKeyFromSite = false, 
      Key = {"Hello"} 
   }
})

local Tab = Window:CreateTab("Auto Buy", "shopping-cart")

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

local function CreateAutoBuyToggle(item)
   local toggleName = "Auto Buy " .. item.name
   
   local Toggle = Tab:CreateToggle({
      Name = toggleName,
      CurrentValue = false,
      Flag = "AutoBuy_" .. item.name, 
      Callback = function(Value)
         if Value then
            Rayfield:Notify({
               Title = toggleName .. " Enabled",
               Content = "Auto purchasing " .. item.name,
               Duration = 4,
               Image = "check" 
            })

            Loops[item.name] = task.spawn(function()
               while task.wait(2) do
                  if not _G["AutoBuy_" .. item.name] then break end 
                  
                  local args = {item.id}
                  pcall(function()
                     game:GetService("ReplicatedStorage")
                        :WaitForChild("EventFolder")
                        :WaitForChild("BuyEvent")
                        :FireServer(unpack(args))
                  end)
               end
            end)
           
            _G["AutoBuy_" .. item.name] = true
         else
         
            Rayfield:Notify({
               Title = toggleName .. " Disabled",
               Content = "Stopped auto purchasing " .. item.name,
               Duration = 4,
               Image = "x" 
            })

            if Loops[item.name] then
               task.cancel(Loops[item.name])
               Loops[item.name] = nil
            end
            _G["AutoBuy_" .. item.name] = false
         end
      end,
   })
end

for _, item in ipairs(Items) do
   CreateAutoBuyToggle(item)
end

Rayfield:LoadConfiguration()