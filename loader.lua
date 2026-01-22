-- Moss Hub Loader 

local Loader_Module = {
    Source = ""
}

Loader_Module.gameMap = {
    [102574559184919] = "CraftFood",  
}

local vLuaCode = game:HttpGet("https://raw.githubusercontent.com/kosuke14/vLuau/main/vLuau.lua")  -- Atau link vLua
local vLua = loadstring(vLuaCode)()

function Loader_Module:LoadScript(id)
    local gameName = Loader_Module.gameMap[id]
    if not gameName then
        warn("Game tidak support! PlaceId: " .. id)
        game.Players.LocalPlayer:Kick("Script ini tidak support game ini! PlaceId: " .. id .. "\nScript By MossC "))
        return  
    end
    
    local scriptUrl = "https://raw.githubusercontent.com/MossC/moss-hub/refs/heads/main/"..gameName.."/"..Loader_Module.Source..".lua"
    local scriptCode = game:HttpGetAsync(scriptUrl)
    
    local success, err = pcall(vLua, scriptCode) 
    if not success then
        warn("Something went wrong | ", err)
    end
end

return Loader_Module
