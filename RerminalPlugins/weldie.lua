
return function(Env, plugin)
    local PLRS = game:GetService("Players")
    local RS = game:GetService("RunService")

    local CurrentWeld = {}
    local WeldCount = 0
    local unloaded = false

    local function GetTargetPart(target, search)
        if typeof(target) == "string" then
            local character = Env.char(target)
            if character then
                return character:FindFirstChild(search or "HumanoidRootPart")
            end
            return
        end
        if typeof(target) == "Instance" then
            if target:IsA("Player") then
                return target.Character and target.Character:FindFirstChild(search or "HumanoidRootPart")
            elseif target:IsA("Model") then
                return target:FindFirstChild(search or "HumanoidRootPart") or target.PrimaryPart or target:FindFirstChildOfClass("BasePart")
            elseif target:IsA("BasePart") then
                return target
            end
        end
    end

    local function ZeroVel(part)
        if not part then return end
        part.AssemblyLinearVelocity = Vector3.zero
        part.AssemblyAngularVelocity = Vector3.zero
    end

    local function PartFromPath(path, waitforchild)
        local part = workspace
        if waitforchild then
            
        end
        for _, name in ipairs(path:split(".")) do
            part = part:FindFirstChild(name)
            if not part then return end
        end
        return part
    end

    local function ReWeld(offset, path, tocheck, nweld, othercn)
        return function()
            Env.log('REWELD!!!')
            if othercn then othercn:Disconnect() end
            if unloaded then return end
            if WeldCount ~= nweld then return end
            Env.log('passed first check')
            local newPart
            local nm = false
            repeat
                task.wait()
                newPart = PartFromPath(tocheck)
                nm = WeldCount ~= nweld or not CurrentWeld.Part
            until newPart or nm
            Env.log('exited loop (because of nm?): ', nm)
            if nm then return end
            newPart = PartFromPath(path, true)
            Env.weld(newPart, offset)
        end
    end

    Env.P_NORMAL({
        Name = "weld",
        Description = "Weldie!!"
    }, function(self, target, offset)
        local myChar = Env.me()
        if not myChar then return end
        local part = GetTargetPart(target or "closest")
        if not part then return end
        local offset = typeof(offset) == 'Vector3' and CFrame.new(offset) or typeof(offset) == 'CFrame' and offset or CFrame.new()
        CurrentWeld = {
            Part = part,
            Offset = offset,
            Start = myChar:GetPivot()
        }
        WeldCount += 1
        local hum = part.Parent:FindFirstChildOfClass('Humanoid')
        local destroyCn
        local dieCn
        local path = part:GetFullName():gsub('Workspace.','')
        local tocheck = hum and part.Parent:GetFullName():gsub('Workspace.','')..'.HumanoidRootPart' or path
        local nweld = WeldCount
        if hum then
            dieCn = hum.Died:Connect(ReWeld(offset, path, tocheck, nweld, destroyCn))
        end
        destroyCn = part.Destroying:Connect(ReWeld(offset, path, tocheck, nweld, dieCn))
        Env.log("Welded: " .. part.Name)
    end)

    Env.P_NORMAL({
        Name = "unweld",
        Description = "Restores and releases any active weld"
    }, function(self)
        if CurrentWeld.Part then
            CurrentWeld = {}
            Env.log("Released weld.")
        else
            Env.log("No part is currently welded.")
        end
    end)

    Env.P_TOGGLE({
        Name = "bang",
        Description = "Weldie bang toggle",
        Speed = 20,
        Target = nil,
        Length = 1
    }, function(self, state, target, speed, length)
        if state then
            if speed then self.Speed = tonumber(speed) or 20 end
            if length then self.Length = tonumber(length) or 1 end
            
            local targetQuery = target or self.Target or "closest"
            local part = GetTargetPart(targetQuery)

            if not part then
                return self(false)
            end

            if CurrentWeld.Part then
                CurrentWeld = {}
            end

            Env.weld(part, CFrame.new(0,0,0.7))
            Env.log("Bang started on: " .. part.Name .. " (Speed: " .. tostring(self.Speed) .. ")")
        else
            if CurrentWeld.Part then
                CurrentWeld = {}
            end
            Env.log("Bang stopped.")
        end
    end, function(self, dt, time)
        if CurrentWeld.Part then
            local spd = self.Speed or 20
            local length = self.Length or 1
            CurrentWeld.Offset = CFrame.new(0, 0, (math.sin(time * spd) + 1) / 2 * length + 0.7)
        end
    end)

    Env.P_NORMAL({
        Name = 'dih',
        Description = 'Dih'
    }, function(self, player)
        local character = Env.me()
        if not character then return end
        local lfoot, rfoot = character:FindFirstChild("LeftFoot") or character:FindFirstChild("Left Leg"), character:FindFirstChild("RightFoot") or character:FindFirstChild("Right Leg")
        if not lfoot or not rfoot then return end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        local hipheight
        if humanoid then
            hipheight = humanoid.HipHeight
        end
        local pos = (lfoot.Position + rfoot.Position) / 2
        local centerToFeet = pos - character:GetPivot().Position
        local height = (centerToFeet.Magnitude + (hipheight or centerToFeet.Magnitude)) / 2 + 0.5

        local otherChar = Env.char(player)
        if not otherChar then return end
        local torso = otherChar:FindFirstChild("UpperTorso") or otherChar:FindFirstChild("Torso")
        local lower = otherChar:FindFirstChild('LowerTorso') or torso
        if not torso then return end
        Env.weld(torso, CFrame.new(0, -torso.Size.Y / 2, -height) * CFrame.Angles(math.rad(-90), 0, 0))
    end)

    Env.P_NORMAL({
        Name = 'headsit',
        Description = 'Sit on a player\'s head'
    }, function(self, player)
        local head = GetTargetPart(player, 'Head')
        if not head then return end

        local char = Env.me()
        local humanoid = char and char:FindFirstChildOfClass("Humanoid")
        local myRoot = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
        if not myRoot or not humanoid then return end

        humanoid.Sit = true

        local yOffset = head.Size.Y / 2.25
        local zOffset = 0.35
        local offset = Vector3.new(0, yOffset, zOffset)

        task.wait()
        Env.weld(head, offset)
    end)

    local function UpdateEvaluationState()
        local hum = Env.me() and Env.me():FindFirstChildOfClass("Humanoid")
        if not hum then return end
        hum.EvaluateStateMachine = true
        if CurrentWeld.Part then
            hum.EvaluateStateMachine = false
        end
    end

    local function UpdatePartState(hrp, dt)
        if not CurrentWeld.Part then return end
        local hrp = Env.me() and Env.me():FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        hrp:PivotTo(CurrentWeld.Start)
        CurrentWeld.Part:PivotTo(CurrentWeld.Start * CurrentWeld.Offset:Inverse())
        sethiddenproperty(hrp, 'PhysicsRepRootPart', CurrentWeld.Part)
        ZeroVel(hrp)
        ZeroVel(CurrentWeld.Part)
    end

    local heartConnection = RS.Heartbeat:Connect(function()
        UpdatePartState(hrp)
        RS.PreRender:Wait()
        UpdatePartState(hrp)
        UpdateEvaluationState()
    end)

    plugin.OnUnload = function()
        CurrentWeld = {}
        if heartConnection then
            heartConnection:Disconnect()
            heartConnection = nil
        end
        UpdateEvaluationState()
        unloaded = true
    end
end