local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")

PhysicsService:RegisterCollisionGroup("Agents")
PhysicsService:CollisionGroupSetCollidable("Agents", "Agents", false)

Players.PlayerAdded:Connect(function(player: Player)
    local function CharacterAdded(character: Model)
        CollectionService:AddTag(character, "SimpleNav_Agent")
    end
    
    CharacterAdded(player.Character or player.CharacterAdded:Wait())
    player.CharacterAdded:Connect(CharacterAdded)
end)

local function applyCollisionGroup(model: Instance)
    for _, child in next, model:GetChildren() do
        if (child:IsA("BasePart")) then
            child.CollisionGroup = "Agents"
        end
    end
end

for _, instance in next, CollectionService:GetTagged("SimpleNav_Agent") do
    applyCollisionGroup(instance)
end
CollectionService:GetInstanceAddedSignal("SimpleNav_Agent"):Connect(applyCollisionGroup)