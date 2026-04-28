--!strict
--[[ Imports ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Janitor = require(Packages:WaitForChild("janitor"))
local LemonSignal = require(Packages:WaitForChild("lemonsignal"))

--[[ Header ]]--
type Impl = {
    __index: Impl,

    Run: (self: SimpleNav, Vector3 | PVInstance) -> (),
    Stop: (self: SimpleNav) -> (),

    Destroy: (self: SimpleNav) -> ()
}

type Proto = {
    janitor: Janitor.Janitor,

    model: Model,
    humanoid: Humanoid,
    path: Path,
    goalPos: Vector3?,

    Reached: LemonSignal.Signal<boolean>
}

local module = {}

local SimpleNav: Impl = {} :: Impl
SimpleNav.__index = SimpleNav
export type SimpleNav = typeof(setmetatable({} :: Proto, {} :: Impl))

--[[ Globals ]]--

--[[ Services ]]--
local PathfindingService = game:GetService("PathfindingService")

--[[ Private Variables ]]--

local function iter(t: {any})
    local i: number = 0
    local n: number = #t
    return function()
        i = i + 1
        return if i <= n then t[i] else nil
    end
end

--[[ Object ]]--
function module.new(model: Model & {Humanoid: Humanoid})
    local self = setmetatable({} :: Proto, SimpleNav)

    self.janitor = Janitor.new()

    self.model = model
    self.humanoid = model.Humanoid
    self.path = PathfindingService:CreatePath({
        AgentRadius = 5,
        AgentHeight = 6,
        AgentCanJump = false
    })

    self.goalPos = nil

    return self
end

function SimpleNav:Run(goal: Vector3 | PVInstance)
    self.janitor:Cleanup()

    if (typeof(goal) == "Vector3") then
        self.goalPos = goal
    elseif (goal:IsA("PVInstance")) then
        self.goalPos = goal:GetPivot().Position
    else
        self.goalPos = nil
        return
    end

    local startPos = self.model:GetPivot().Position
    local success, errorMessage = pcall(function()
        self.path:ComputeAsync(startPos, self.goalPos :: Vector3)
    end)

    if success and self.path.Status == Enum.PathStatus.Success then
        -- create movement task
        self.janitor:Add(task.defer(function()
            local waypoints = iter(self.path:GetWaypoints())

            for pos in waypoints() do
                local reached = false
                repeat
                    -- instead of MoveTo, we should use Move and add steering behavior
                    self.humanoid:MoveTo(pos)
                    reached = self.humanoid.MoveToFinished:Wait()
                until reached
            end
        end), true)

        self.janitor:Add(self.path.Blocked:Connect(function()
            self:Run(self.goalPos :: Vector3)
        end), "Disconnect")
    else
        print(`Path unable to be computed, error: {errorMessage}`)
    end
end

function SimpleNav:Stop()
    self.janitor:Cleanup()
end

function SimpleNav:Destroy()
    self.janitor:Destroy()
end


return module