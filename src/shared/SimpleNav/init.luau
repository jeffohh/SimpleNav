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
local WAYPOINT_REACH_DISTANCE = 2.0   -- studs to consider a waypoint reached

local SEPARATION_RADIUS       = 4.0   -- studs, repulsion range
local MAX_STEERING_OFFSET     = 5.0   -- clamp on steering force magnitude

local PATH_WEIGHT       = 0.9  -- how much path direction dominates
local SEPARATION_WEIGHT = 0.7  -- how much separation can influence

local STUCK_TIMEOUT  = 2.0  -- seconds without meaningful movement = stuck

local AGENT_TAG = "SimpleNav_Agent"

--[[ Services ]]--
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

--[[ Private Variables ]]--
local function iter(t: {any})
    local i: number = 0
    local n: number = #t
    return function()
        i = i + 1
        return if i <= n then t[i] else nil
    end
end

local function computeSeparation(model: Model, pathDir: Vector3): Vector3
    local force  = Vector3.zero
    local myPos  = model:GetPivot().Position

    local right = Vector3.new(pathDir.Z, 0, -pathDir.X)

    for _, other: Instance in CollectionService:GetTagged(AGENT_TAG) do
        if other == model then continue end

        local otherModel = other :: Model
        local otherPos   = otherModel:GetPivot().Position
        local diff       = myPos - otherPos
        local distance   = diff.Magnitude

        if distance > 0 and distance < SEPARATION_RADIUS then
            local rawRepulsion = diff / distance

            -- check if the other agent is roughly head-on (dot < 0 means facing us)
            local otherPivot = otherModel:GetPivot()
            local otherForward = otherPivot.LookVector
            local headOn = pathDir:Dot(otherForward) < -0.5

            if headOn then
                -- replace pure pushback with a rightward sidestep bias
                -- blending to keep some raw repulsion so they still spread apart in depth
                rawRepulsion = (rawRepulsion * 0.5) + (right * 0.8)
            end

            force += rawRepulsion
        end
    end

    if force.Magnitude > MAX_STEERING_OFFSET then
        force = force.Unit * MAX_STEERING_OFFSET
    end

    return force
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

    self.Reached = LemonSignal.new()

    CollectionService:AddTag(model, AGENT_TAG)

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

        for waypoint in iter(self.path:GetWaypoints()) do
            local part = Instance.new("Part")
            part.Position = waypoint.Position
            part.Size = Vector3.new(0.5, 0.5, 0.5)
            part.Color = Color3.new(1, 0, 1)
            part.Anchored = true
            part.CanCollide = false
            part.Parent = workspace

            self.janitor:Add(part, "Destroy")
        end

        -- create movement task
        local timeout = STUCK_TIMEOUT
        local nextWaypoint = iter(self.path:GetWaypoints())
        local current = nextWaypoint() :: PathWaypoint

        self.janitor:Add(RunService.Heartbeat:Connect(function(dt: number)
            if not current then
                self.humanoid:Move(Vector3.zero)
                self.Reached:Fire(true)
                self.janitor:Cleanup()
                return
            end

            local pos = self.model:GetPivot().Position
            local target = current.Position
            local dist = (
                Vector3.new(target.X, 0, target.Z) - 
                Vector3.new(pos.X,    0, pos.Z)
            ).Magnitude

            if (dist < WAYPOINT_REACH_DISTANCE) then
                current = nextWaypoint() :: PathWaypoint
                timeout = STUCK_TIMEOUT -- reset timeout
                return
            end

            -- path direction needed for ahead-check in separation
            local pathDir   = Vector3.new(target.X - pos.X, 0, target.Z - pos.Z).Unit
            local separation = computeSeparation(self.model, pathDir)

            self.humanoid:Move(pathDir * PATH_WEIGHT + separation * SEPARATION_WEIGHT, false)

            timeout -= dt
            if timeout <= 0 then
                self:Run(self.goalPos :: Vector3)
            end
        end), "Disconnect")

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
    self.Reached:DisconnectAll()

    self.janitor:Destroy()
end


return module