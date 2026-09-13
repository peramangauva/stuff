
return function(Env, plugin)
    local PLRS = game:GetService('Players')
    local RS = game:GetService('RunService')

    local myplr = PLRS.LocalPlayer

    Env.P_TOGGLE({
        Name = 'e',
        Description = ''
    }, function(self, state)

    end, function(self, dt, time)

    end, RunService.PreSimulation)

    plugin.OnUnload = function()

    end
    plugin.Dependencies = {
        'weldie'
    }
end