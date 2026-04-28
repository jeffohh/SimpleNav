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
local WAYPOINT_REACH_DISTANCE = 3.0   -- studs to consider a waypoint reached
local BASE_WALK_SPEED = 16  -- store this once, don't read WalkSpeed each frame

local SEPARATION_RADIUS       = 7.0   -- studs, repulsion range
local SEPARATION_WEIGHT       = 0.5   -- how much steering blends in (0-1)
local MAX_STEERING_OFFSET     = 4.0   -- clamp on steering force magnitude

local PATH_WEIGHT     = 0.6  -- how much path direction dominates
local STEERING_WEIGHT = 0.4  -- how much separation can influence

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

local function computeMovement(pos: Vector3, target: Vector3, steering: Vector3): Vector3
    local pathDir     = (target - pos)
    
    -- flatten to XZ so Y doesn't skew direction
    pathDir  = Vector3.new(pathDir.X,    0, pathDir.Z).Unit
    steering = Vector3.new(steering.X,   0, steering.Z)

    -- Normalize steering only if it has magnitude, else zero
    local steerDir = if steering.Magnitude > 0 
        then steering.Unit 
        else Vector3.zero

    local blended = (pathDir * PATH_WEIGHT) + (steerDir * STEERING_WEIGHT)

    return blended.Unit
end

type SeparationResult = {
    lateral: Vector3,   -- XZ steering force
    speedScale: number  -- 0 (stop) to 1 (full speed)
}

local function computeSeparation(model: Model, pathDir: Vector3): SeparationResult
    local force     = Vector3.zero
    local minScale  = 1.0
    local myPos     = model:GetPivot().Position

    for _, other: Instance in CollectionService:GetTagged(AGENT_TAG) do
        if other == model then continue end

        local otherModel = other :: Model
        local diff       = myPos - otherModel:GetPivot().Position
        local distance   = diff.Magnitude

        if distance > 0 and distance < SEPARATION_RADIUS then
            local strength = 1 - (distance / SEPARATION_RADIUS)

            -- Lateral: push sideways
            force += diff.Unit * strength

            -- Check if this neighbor is ahead of us (dot > 0 means in front)
            -- If so, scale speed down proportional to how close and how ahead
            local aheadDot = (-diff.Unit):Dot(pathDir)
            if aheadDot > 0 then
                -- aheadDot=1 means directly ahead, aheadDot=0 means beside us
                local slowdown = aheadDot * strength
                minScale = math.min(minScale, 1 - slowdown)
            end
        end
    end

    if force.Magnitude > MAX_STEERING_OFFSET then
        force = force.Unit * MAX_STEERING_OFFSET
    end

    return {
        lateral    = force * SEPARATION_WEIGHT * 100,
        speedScale = math.clamp(minScale, 0.0, 1.0)  -- never fully stop
    }
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
        self.janitor:Add(task.defer(function()
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
                    return
                end

                -- Path direction needed for ahead-check in separation
                local pathDir = Vector3.new(target.X - pos.X, 0, target.Z - pos.Z).Unit

                local separation = computeSeparation(self.model, pathDir)
                local direction  = computeMovement(pos, target, separation.lateral)

                -- Apply speed scaling -- Humanoid handles the animation automatically
                self.humanoid.WalkSpeed = BASE_WALK_SPEED * separation.speedScale

                self.humanoid:Move(direction, false)
            end), "Disconnect")
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
    self.Reached:DisconnectAll()

    self.janitor:Destroy()
end


return module