local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")


Players.PlayerAdded:Connect(function(player: Player)
    local function CharacterAdded(character: Model)
        CollectionService:AddTag(character, "SimpleNav_Agent")
    end
    
    CharacterAdded(player.Character or player.CharacterAdded:Wait())
    player.CharacterAdded:Connect(CharacterAdded)
end)