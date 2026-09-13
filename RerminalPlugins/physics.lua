
return function(Env, plugin)
    local PLRS = game:GetService('Players')
    local RS = game:GetService('RunService')
    local Physics = settings().Physics

    local myplr = PLRS.LocalPlayer

    Env.P_TOGGLE({
        Name = 'simulate',
        Description = 'physics ownership yay',
        LastMax = math.huge,
        LastFocus = workspace,
        OtherMax = {},
        OtherFocus = {},
        OtherRad = {},
        LastThrottleState = nil,
        PlrConnection = nil
    }, function(self, state)
        Physics.AllowSleep = not state
        if state then
            self.LastMax = gethiddenproperty(myplr, 'MaximumSimulationRadius')
            self.LastFocus = gethiddenproperty(myplr, 'ReplicationFocus')
            sethiddenproperty(myplr, 'MaximumSimulationRadius', 1e9)
            sethiddenproperty(myplr, 'ReplicationFocus', workspace)
            local function ImplementPlayer(plr)
                if plr == myplr then return end
                self.OtherMax[plr] = gethiddenproperty(plr, 'MaximumSimulationRadius')
                self.OtherFocus[plr] = gethiddenproperty(plr, 'ReplicationFocus')
                self.OtherRad[plr] = gethiddenproperty(plr, 'SimulationRadius')
                sethiddenproperty(plr, 'MaximumSimulationRadius', 0)
                sethiddenproperty(plr, 'ReplicationFocus', nil)
                sethiddenproperty(plr, 'SimulationRadius', 0)
            end
            for _, plr in ipairs(PLRS:GetPlayers()) do
                ImplementPlayer(plr)
            end
            self.PlrConnection = PLRS.PlayerAdded:Connect(ImplementPlayer)

            self.LastThrottleState = Physics.PhysicsEnvironmentalThrottle
            Physics.PhysicsEnvironmentalThrottle = Enum.EnviromentalPhysicsThrottle.Disabled
            for _, part in ipairs(workspace:GetDescendants()) do
                if not part:IsA('BasePart') or part:IsGrounded() then
                    continue
                end
                if part.AssemblyLinearVelocity.Magnitude < 0.01 then
                    part.AssemblyLinearVelocity = Vector3.new(0,0.025,0)
                end
            end
        else
            sethiddenproperty(myplr, 'MaximumSimulationRadius', self.LastMax)
            sethiddenproperty(myplr, 'ReplicationFocus', self.LastFocus)
            for plr, max in pairs(self.OtherMax) do
                if not plr.Parent then
                    self.OtherMax[plr] = nil
                    self.OtherFocus[plr] = nil
                    self.OtherRad[plr] = nil
                    continue
                end
                sethiddenproperty(plr, 'MaximumSimulationRadius', max)
                sethiddenproperty(plr, 'ReplicationFocus', self.OtherFocus[plr])
                sethiddenproperty(plr, 'SimulationRadius', self.OtherRad[plr])
            end
            Physics.PhysicsEnvironmentalThrottle = self.LastThrottleState
            self.PlrConnection:Disconnect()
        end
    end, function(self, dt, time)
        sethiddenproperty(myplr, 'SimulationRadius', 1e9)
        sethiddenproperty(myplr, 'MaximumSimulationRadius', 1e9)
        for plr, max in pairs(self.OtherMax) do
            if not plr.Parent then continue end
            sethiddenproperty(plr, 'SimulationRadius', 0)
        end
    end, RunService.PreSimulation)

    Env.P_TOGGLE({
        Name = 'vel',
        Description = 'server thinks ur velocity is constant',
        Velocity = Vector3.zero
    }, function(self, state, velocity)
        if typeof(velocity) == 'Vector3' then
            self.Velocity = velocity
        end
        if state then
            Env.fling(false)
        end
    end, function(self, dt, time)
        local hrp = Env.me() and Env.me():FindFirstChild('HumanoidRootPart')
        if not hrp then return end
        local prevel = hrp.AssemblyLinearVelocity
        hrp.AssemblyLinearVelocity = Vector3.zero
        RS.PreRender:Wait()
        hrp.AssemblyLinearVelocity = prevel
    end)

    Env.P_TOGGLE({
        Name = 'fling',
        Description = 'server thinks ur rlly fast'
    }, function(self, state)
        if state then
            Env.vel(false)
        end
    end, function(self, dt, time)
        local root = Env.me() and Env.me():FindFirstChild('HumanoidRootPart')
        if not root then return end
        if root.AssemblyLinearVelocity.Magnitude >= 0.2 then return end
        local actual = root.AssemblyAngularVelocity
        root.AssemblyAngularVelocity = Vector3.one * 1e10
        RS.PreRender:Wait()
        root.AssemblyAngularVelocity = actual
    end)
end