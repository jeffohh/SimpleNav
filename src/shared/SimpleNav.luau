--!strict
--[[ Imports ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Janitor = require(Packages:WaitForChild("janitor"))

--[[ Header ]]--
type Impl = {
    __index: Impl,

    Example: (self: SimpleNav) -> ()
}

type Proto = {

}

local module = {}

local SimpleNav: Impl = {} :: Impl
SimpleNav.__index = SimpleNav
export type SimpleNav = typeof(setmetatable({} :: Proto, {} :: Impl))

--[[ Globals ]]--

--[[ Services ]]--
local Players = game:GetService("Players")

--[[ Private Variables ]]--

--[[ Object ]]--
function module.new(humanoid: Humanoid)
    local self = setmetatable({} :: Proto, SimpleNav)

	

    return self
end



return module