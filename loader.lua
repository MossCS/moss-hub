-- Moss Hub Loader 

local Loader_Module = {
    Source = ""
}

Loader_Module.gameMap = {
    [102574559184919] = "CraftFood", 
}

function Loader_Module:LoadScript(id)
    local gameName = Loader_Module.gameMap[id]
    if not gameName then
        warn("Game tidak support! PlaceId: " .. id)
        game.Players.LocalPlayer:Kick("Script ini tidak support game ini! PlaceId: " .. id .. "\nScript by MossC"))
        return  
    end

    local success, err = pcall(function()
        loadstring(game:HttpGetAsync("https://raw.githubusercontent.com/MossC/moss-hub/refs/heads/main/"..gameName.."/"..Loader_Module.Source..".lua"))()
    end)
    if not success then
        warn("Something went wrong | ", err)
    end
end

return Loader_Module
