-- Moss Hub Loader 

local expectedGames = {
   [102574559184919] = {
      name = "Craft Food",
      scriptUrl = "https://raw.githubusercontent.com/mosscs/repo/main/craftfood.lua"
}

local currentPlaceId = game.PlaceId
local gameData = expectedGames[currentPlaceId]

if gameData then
   print("Game terdeteksi: " .. gameData.name .. " (PlaceId: " .. currentPlaceId .. ")")
   print("Memuat script khusus untuk game ini...")
 loadstring(game:HttpGet(gameData.scriptUrl, true))()
   
else
   local msg = "Script nya ga support game ini kocakk!\n"
   msg = msg .. "\n -- Made by MossC."
   
   game.Players.LocalPlayer:Kick(msg)
end