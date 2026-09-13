-- ============================================================================
-- RERMINAL 2.0 (PURE LUA RUNTIME & CALLABLE METATABLE ENGINE)
-- ============================================================================

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    LocalPlayer = Players.LocalPlayer
end

-- Cleanup prior active instances
if _G.RerminalCleanup then pcall(_G.RerminalCleanup) end

-- ----------------------------------------------------------------------------
-- MASTER ENGINE STATE
-- ----------------------------------------------------------------------------
local Rerminal = {
    IsOpen = false,
    History = {},
    HistoryIndex = 0,
    Draft = "",
    Connections = {},
    LoadedPlugins = {},
    AutoloadList = {},
    PluginTracking = {},
    RawBinds = {},
    ActiveLoops = {},
    ActiveToggles = {},
    CurrentLoadingPlugin = nil,
    Colors = {
        SPECIAL  = "#FFE650",
        INSTANCE = "#5AA0FF",
        TABLE    = "#FFA532",
        PLAYER   = "#64FF82",
        CMD      = "#82DCFF",
        TOGGLE   = "#FF6ED2",
        WHITE    = "#FFFFFF",
        ERROR    = "#FF6464",
        SUCCESS  = "#64FF82",
        WARN     = "#FFA532",
        BG       = "#0C0C10",
        PROMPT   = "#FFE650"
    }
}
_G.Rerminal = Rerminal

-- ----------------------------------------------------------------------------
-- FILESYSTEM CONFIGURATION
-- ----------------------------------------------------------------------------
local PLUGIN_FOLDER = "rerminal_plugins"
local CONFIG_FOLDER = "rerminal_config"
local hasFS = (readfile and writefile and isfile and isfolder and makefolder and listfiles) ~= nil

local function ensureDirectories()
    if not hasFS then return end
    if not isfolder(PLUGIN_FOLDER) then makefolder(PLUGIN_FOLDER) end
    if not isfolder(CONFIG_FOLDER) then makefolder(CONFIG_FOLDER) end
end
ensureDirectories()

function Rerminal.SaveBinds()
    if not hasFS then return end
    ensureDirectories()
    local serialized = {}
    for k, v in pairs(Rerminal.RawBinds) do
        if type(v) == "string" then
            serialized[k] = v
        end
    end
    writefile(CONFIG_FOLDER .. "/binds.json", HttpService:JSONEncode(serialized))
end

function Rerminal.LoadBinds()
    if not hasFS or not isfile(CONFIG_FOLDER .. "/binds.json") then return end
    pcall(function()
        local data = HttpService:JSONDecode(readfile(CONFIG_FOLDER .. "/binds.json"))
        for k, v in pairs(data) do
            Rerminal.RawBinds[k] = v
        end
    end)
end

function Rerminal.SaveColors()
    if not hasFS then return end
    ensureDirectories()
    writefile(CONFIG_FOLDER .. "/colors.json", HttpService:JSONEncode(Rerminal.Colors))
end

function Rerminal.LoadColors()
    if not hasFS or not isfile(CONFIG_FOLDER .. "/colors.json") then return end
    pcall(function()
        local data = HttpService:JSONDecode(readfile(CONFIG_FOLDER .. "/colors.json"))
        for k, v in pairs(data) do Rerminal.Colors[k] = v end
    end)
end

function Rerminal.SaveAutoload()
    if not hasFS then return end
    ensureDirectories()
    writefile(CONFIG_FOLDER .. "/autoload.json", HttpService:JSONEncode(Rerminal.AutoloadList))
end

function Rerminal.LoadAutoload()
    if not hasFS or not isfile(CONFIG_FOLDER .. "/autoload.json") then return end
    pcall(function()
        Rerminal.AutoloadList = HttpService:JSONDecode(readfile(CONFIG_FOLDER .. "/autoload.json"))
    end)
end

-- ----------------------------------------------------------------------------
-- TEXT FORMATTING & VALUE RENDERING
-- ----------------------------------------------------------------------------
function Rerminal.Tag(text, color)
    local str = tostring(text or "")
    if not (str:find("<font") and str:find("</font>")) then
        str = str:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
    end
    return string.format('<font color="%s">%s</font>', color or Rerminal.Colors.WHITE, str)
end

function Rerminal.FormatValue(val, isTopLevelString)
    local t = typeof(val)
    if t == "Instance" then
        return Rerminal.Tag(val:GetFullName(), Rerminal.Colors.INSTANCE)
    elseif t == "table" then
        if val._type == "TOGGLE" then
            return Rerminal.Tag(string.format("[Toggle: %s | State: %s | Interval: %s]", val.Name, tostring(val.State), tostring(val.Interval)), Rerminal.Colors.TOGGLE)
        elseif val._type == "FUNCTION" then
            return Rerminal.Tag(string.format("[Function: %s]", val.Name), Rerminal.Colors.CMD)
        else
            local count = 0
            for _ in pairs(val) do count = count + 1 end
            return Rerminal.Tag(string.format("Table (%d items)", count), Rerminal.Colors.TABLE)
        end
    elseif t == "string" then
        if val:find("<font") or val:find("</font>") or isTopLevelString then
            return val
        end
        return Rerminal.Tag('"' .. val .. '"', Rerminal.Colors.SUCCESS)
    elseif t == "number" or t == "boolean" then
        return Rerminal.Tag(tostring(val), Rerminal.Colors.SPECIAL)
    elseif t == "nil" then
        return Rerminal.Tag("nil", Rerminal.Colors.WARN)
    else
        return Rerminal.Tag(tostring(val), Rerminal.Colors.WHITE)
    end
end

-- ----------------------------------------------------------------------------
-- UI CONSTRUCT (CoreGui)
-- ----------------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RerminalUI_v2"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 999999
screenGui.IgnoreGuiInset = true
screenGui.Enabled = true

local okParent = pcall(function() screenGui.Parent = CoreGui end)
if not okParent then screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

local notifContainer = Instance.new("Frame")
notifContainer.Name = "Notifications"
notifContainer.Size = UDim2.new(0, 320, 1, -40)
notifContainer.Position = UDim2.new(1, -334, 0, 20)
notifContainer.BackgroundTransparency = 1
notifContainer.Parent = screenGui

local notifLayout = Instance.new("UIListLayout")
notifLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
notifLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
notifLayout.SortOrder = Enum.SortOrder.LayoutOrder
notifLayout.Padding = UDim.new(0, 8)
notifLayout.Parent = notifContainer

local canvasGroup = Instance.new("CanvasGroup")
canvasGroup.Size = UDim2.new(1, 0, 1, 0)
canvasGroup.BackgroundColor3 = Color3.fromHex(Rerminal.Colors.BG or "#0C0C10")
canvasGroup.BackgroundTransparency = 0.35
canvasGroup.GroupTransparency = 1
canvasGroup.Visible = false
canvasGroup.BorderSizePixel = 0
canvasGroup.Parent = screenGui

local modalSink = Instance.new("TextButton")
modalSink.Size = UDim2.new(0, 0, 0, 0)
modalSink.BackgroundTransparency = 1
modalSink.Modal = true
modalSink.Text = ""
modalSink.Parent = canvasGroup

local outputScroll = Instance.new("ScrollingFrame")
outputScroll.Size = UDim2.new(1, -28, 1, -64)
outputScroll.Position = UDim2.new(0, 14, 0, 14)
outputScroll.BackgroundTransparency = 1
outputScroll.ScrollBarThickness = 4
outputScroll.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 100)
outputScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
outputScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
outputScroll.Parent = canvasGroup

local listLayout = Instance.new("UIListLayout")
listLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 3)
listLayout.Parent = outputScroll

local promptBar = Instance.new("Frame")
promptBar.Size = UDim2.new(1, -28, 0, 28)
promptBar.Position = UDim2.new(0, 14, 1, -36)
promptBar.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
promptBar.BackgroundTransparency = 0.2
promptBar.BorderColor3 = Color3.fromRGB(45, 45, 60)
promptBar.Parent = canvasGroup

local promptLabel = Instance.new("TextLabel")
promptLabel.Size = UDim2.new(0, 0, 1, 0)
promptLabel.Position = UDim2.new(0, 6, 0, 0)
promptLabel.BackgroundTransparency = 1
promptLabel.Font = Enum.Font.Code
promptLabel.TextSize = 14
promptLabel.RichText = true
promptLabel.TextXAlignment = Enum.TextXAlignment.Left
promptLabel.Parent = promptBar

local ghostLabel = Instance.new("TextLabel")
ghostLabel.BackgroundTransparency = 1
ghostLabel.Font = Enum.Font.Code
ghostLabel.TextSize = 14
ghostLabel.TextColor3 = Color3.fromRGB(110, 110, 125)
ghostLabel.TextXAlignment = Enum.TextXAlignment.Left
ghostLabel.Parent = promptBar

local inputBox = Instance.new("TextBox")
inputBox.BackgroundTransparency = 1
inputBox.Font = Enum.Font.Code
inputBox.TextSize = 14
inputBox.TextColor3 = Color3.fromRGB(255, 255, 255)
inputBox.TextXAlignment = Enum.TextXAlignment.Left
inputBox.ClearTextOnFocus = false
inputBox.Text = ""
inputBox.Parent = promptBar

local suggestionBox = Instance.new("Frame")
suggestionBox.Name = "SuggestionBox"
suggestionBox.Size = UDim2.new(0, 440, 0, 0)
suggestionBox.AnchorPoint = Vector2.new(0, 1)
suggestionBox.Position = UDim2.new(0, 14, 1, -40)
suggestionBox.BackgroundColor3 = Color3.fromRGB(14, 14, 20)
suggestionBox.BorderColor3 = Color3.fromRGB(55, 55, 75)
suggestionBox.BorderSizePixel = 1
suggestionBox.Visible = false
suggestionBox.Parent = canvasGroup

local suggestionScroll = Instance.new("ScrollingFrame")
suggestionScroll.Size = UDim2.new(1, 0, 1, 0)
suggestionScroll.BackgroundTransparency = 1
suggestionScroll.BorderSizePixel = 0
suggestionScroll.ScrollBarThickness = 4
suggestionScroll.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 105)
suggestionScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
suggestionScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
suggestionScroll.Parent = suggestionBox

local suggestionList = Instance.new("UIListLayout")
suggestionList.SortOrder = Enum.SortOrder.LayoutOrder
suggestionList.Padding = UDim.new(0, 2)
suggestionList.Parent = suggestionScroll

local suggestionPadding = Instance.new("UIPadding")
suggestionPadding.PaddingTop = UDim.new(0, 4)
suggestionPadding.PaddingBottom = UDim.new(0, 4)
suggestionPadding.PaddingLeft = UDim.new(0, 4)
suggestionPadding.PaddingRight = UDim.new(0, 4)
suggestionPadding.Parent = suggestionScroll

-- ----------------------------------------------------------------------------
-- NOTIFICATIONS & LOGGING
-- ----------------------------------------------------------------------------
local notifCounter = 0
function Rerminal.Notify(title, message, duration, nType)
    notifCounter = notifCounter + 1
    duration = duration or 3

    local accentColor = Rerminal.Colors.CMD
    if nType == "SUCCESS" then accentColor = Rerminal.Colors.SUCCESS
    elseif nType == "WARN" then accentColor = Rerminal.Colors.WARN
    elseif nType == "ERROR" then accentColor = Rerminal.Colors.ERROR
    end

    local card = Instance.new("Frame")
    card.Name = "Notif_" .. notifCounter
    card.Size = UDim2.new(1, 0, 0, 54)
    card.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
    card.BorderColor3 = Color3.fromRGB(45, 45, 60)
    card.BackgroundTransparency = 0.1
    card.Position = UDim2.new(1, 40, 0, 0)
    card.Parent = notifContainer

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(0, 3, 1, 0)
    bar.BackgroundColor3 = Color3.fromHex(accentColor)
    bar.BorderSizePixel = 0
    bar.Parent = card

    local titleLbl = Instance.new("TextLabel")
    titleLbl.Size = UDim2.new(1, -16, 0, 18)
    titleLbl.Position = UDim2.new(0, 10, 0, 5)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Font = Enum.Font.Code
    titleLbl.TextSize = 13
    titleLbl.TextColor3 = Color3.fromHex(accentColor)
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.Text = string.upper(title or "RERMINAL")
    titleLbl.Parent = card

    local descLbl = Instance.new("TextLabel")
    descLbl.Size = UDim2.new(1, -16, 0, 24)
    descLbl.Position = UDim2.new(0, 10, 0, 23)
    descLbl.BackgroundTransparency = 1
    descLbl.Font = Enum.Font.Code
    descLbl.TextSize = 12
    descLbl.TextColor3 = Color3.fromRGB(220, 220, 220)
    descLbl.TextXAlignment = Enum.TextXAlignment.Left
    descLbl.TextWrapped = true
    descLbl.Text = message or ""
    descLbl.Parent = card

    TweenService:Create(card, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Position = UDim2.new(0, 0, 0, 0)
    }):Play()

    task.delay(duration, function()
        if card and card.Parent then
            local tw = TweenService:Create(card, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                Position = UDim2.new(1, 40, 0, 0),
                BackgroundTransparency = 1
            })
            tw:Play()
            tw.Completed:Connect(function() card:Destroy() end)
        end
    end)
end

function Rerminal.GetPromptRich()
    return Rerminal.Tag("rerminal", Rerminal.Colors.CMD) .. Rerminal.Tag(" > ", Rerminal.Colors.SPECIAL)
end

function Rerminal.UpdatePrompt()
    canvasGroup.BackgroundColor3 = Color3.fromHex(Rerminal.Colors.BG or "#0C0C10")
    promptLabel.Text = Rerminal.GetPromptRich()
    local width = TextService:GetTextSize("rerminal > ", promptLabel.TextSize, promptLabel.Font, Vector2.new(10000, 30)).X + 8
    inputBox.Position = UDim2.new(0, width, 0, 0)
    inputBox.Size = UDim2.new(1, -width - 4, 1, 0)
    ghostLabel.Position = inputBox.Position
    ghostLabel.Size = inputBox.Size
end

local logCounter = 0
function Rerminal.Print(richText)
    logCounter = logCounter + 1
    local line = Instance.new("TextLabel")
    line.LayoutOrder = logCounter
    line.BackgroundTransparency = 1
    line.Size = UDim2.new(1, 0, 0, 0)
    line.AutomaticSize = Enum.AutomaticSize.Y
    line.Font = Enum.Font.Code
    line.TextSize = 14
    line.TextColor3 = Color3.fromRGB(255, 255, 255)
    line.TextXAlignment = Enum.TextXAlignment.Left
    line.TextWrapped = true
    line.RichText = true
    line.Text = tostring(richText)
    line.Parent = outputScroll

    task.defer(function()
        outputScroll.CanvasPosition = Vector2.new(0, outputScroll.AbsoluteCanvasSize.Y + 1000)
    end)
end

function Rerminal.ClearConsole()
    for _, v in ipairs(outputScroll:GetChildren()) do
        if v:IsA("TextLabel") then v:Destroy() end
    end
    logCounter = 0
end

-- ----------------------------------------------------------------------------
-- UNIFIED RUNTIME ENVIRONMENT (Env)
-- ----------------------------------------------------------------------------
local Env = {}
local envMetatable = {
    __index = function(t, k)
        if rawget(t, k) ~= nil then return rawget(t, k) end
        if k == "my" then return LocalPlayer end
        if k == "workspace" or k == "Workspace" then return workspace end
        if k == "game" then return game end
        local globalVal = _G[k] or shared[k] or getfenv(0)[k]
        if globalVal ~= nil then return globalVal end
        local serviceOk, service = pcall(game.GetService, game, k)
        if serviceOk and service then return service end
        return nil
    end
}
setmetatable(Env, envMetatable)
Rerminal.Env = Env

-- ----------------------------------------------------------------------------
-- FUNCTION DEFINITION CONSTRUCTS: P_NORMAL & P_TOGGLE
-- ----------------------------------------------------------------------------

function Env.P_NORMAL(properties, fn)
    if type(properties) == "string" then
        properties = { Name = properties }
    end
    assert(type(properties) == "table" and properties.Name, "P_NORMAL requires a properties table with a 'Name' field")
    assert(type(fn) == "function", "P_NORMAL requires a function callback")

    local obj = properties
    obj._type = "FUNCTION"
    obj._isRerminalFunc = true
    obj.Fn = fn

    setmetatable(obj, {
        __call = function(self, ...)
            return fn(self, ...)
        end,
        __tostring = function(self)
            return string.format("[Rerminal Function: %s]", self.Name)
        end
    })

    local currentPlugin = Rerminal.CurrentLoadingPlugin
    if currentPlugin then
        Rerminal.PluginTracking[currentPlugin] = Rerminal.PluginTracking[currentPlugin] or { EnvKeys = {}, Toggles = {}, Loops = {}, Binds = {} }
        table.insert(Rerminal.PluginTracking[currentPlugin].EnvKeys, obj.Name)
    end

    Env[obj.Name] = obj
    return obj
end

function Env.P_TOGGLE(properties, ontoggle, onstep, event)
    if type(properties) == "string" then
        properties = { Name = properties }
    end
    assert(type(properties) == "table" and properties.Name, "P_TOGGLE requires a properties table with a 'Name' field")

    local obj = properties
    obj.State = (obj.State == true)
    obj.Interval = tonumber(obj.Interval) or 0
    obj.OnToggle = ontoggle
    obj.OnStep = onstep
    obj.Event = event or properties.Event or RunService.Heartbeat
    obj._elapsed = 0
    obj._totalTime = 0
    obj._lastTime = os.clock()
    obj._connection = nil
    obj._type = "TOGGLE"
    obj._isToggle = true

    setmetatable(obj, {
        __call = function(self, ...)
            local args = table.pack(...)
            local firstArg = args[1]
            local explicitState = nil
            local extraArgs = {}

            if type(firstArg) == "boolean" then
                explicitState = firstArg
                for i = 2, args.n do
                    table.insert(extraArgs, args[i])
                end
            elseif args.n > 0 then
                -- Non-boolean 1st arg passed (e.g. bang(plr('random'), 50))
                explicitState = true
                for i = 1, args.n do
                    table.insert(extraArgs, args[i])
                end
            else
                -- No arguments passed: toggle()
                explicitState = not self.State
            end

            local newState = explicitState
            local stateChanged = (self.State ~= newState)
            self.State = newState

            if newState then
                if stateChanged or not self._connection then
                    self._elapsed = 0
                    self._totalTime = 0
                    self._lastTime = os.clock()
                    Rerminal.ActiveToggles[self] = true

                    if self._connection then
                        pcall(function() self._connection:Disconnect() end)
                        self._connection = nil
                    end

                    local ev = self.Event or RunService.Heartbeat
                    if self.OnStep and ev and (typeof(ev) == "RBXScriptSignal" or type(ev) == "table" or type(ev) == "userdata") and ev.Connect then
                        self._connection = ev:Connect(function(...)
                            if not self.State then return end
                            local now = os.clock()
                            local dt = (type(...) == "number" and ...) or (now - (self._lastTime or now))
                            self._lastTime = now
                            self._totalTime = (self._totalTime or 0) + dt

                            local interval = self.Interval or 0
                            if interval > 0 then
                                self._elapsed = (self._elapsed or 0) + dt
                                if self._elapsed >= interval then
                                    local stepDt = self._elapsed
                                    self._elapsed = 0
                                    local ok, err = pcall(self.OnStep, self, stepDt, self._totalTime, ...)
                                    if not ok then
                                        Env.log(Rerminal.Tag("[Step Error: " .. tostring(self.Name) .. "] " .. tostring(err), Rerminal.Colors.ERROR))
                                        self(false)
                                    end
                                end
                            else
                                local ok, err = pcall(self.OnStep, self, dt, self._totalTime, ...)
                                if not ok then
                                    Env.log(Rerminal.Tag("[Step Error: " .. tostring(self.Name) .. "] " .. tostring(err), Rerminal.Colors.ERROR))
                                    self(false)
                                end
                            end
                        end)
                    end
                end
            else
                Rerminal.ActiveToggles[self] = nil
                if self._connection then
                    pcall(function() self._connection:Disconnect() end)
                    self._connection = nil
                end
            end

            if self.OnToggle and (stateChanged or #extraArgs > 0) then
                local ok, err = pcall(self.OnToggle, self, newState, table.unpack(extraArgs, 1, #extraArgs))
                if not ok then
                    Env.log(Rerminal.Tag("[Toggle Error: " .. tostring(self.Name) .. "] " .. tostring(err), Rerminal.Colors.ERROR))
                end
            end

            if stateChanged then
                Rerminal.Notify("Toggle " .. (newState and "ON" or "OFF"), self.Name, 1.5, newState and "SUCCESS" or "WARN")
            end

            return self.State
        end,
        __tostring = function(self)
            return string.format("[Rerminal Toggle: %s | State: %s | Interval: %s]", self.Name, tostring(self.State), tostring(self.Interval))
        end
    })

    local currentPlugin = Rerminal.CurrentLoadingPlugin
    if currentPlugin then
        Rerminal.PluginTracking[currentPlugin] = Rerminal.PluginTracking[currentPlugin] or { EnvKeys = {}, Toggles = {}, Loops = {}, Binds = {} }
        table.insert(Rerminal.PluginTracking[currentPlugin].EnvKeys, obj.Name)
        table.insert(Rerminal.PluginTracking[currentPlugin].Toggles, obj)
    end

    Env[obj.Name] = obj
    return obj
end

-- Central Stepper Loop for Active Loops
Rerminal.Connections["HeartbeatRunner"] = RunService.Heartbeat:Connect(function(dt)
    for loopObj in pairs(Rerminal.ActiveLoops) do
        if loopObj.Active and loopObj.Fn then
            local interval = loopObj.Interval or 0
            if interval > 0 then
                loopObj._elapsed = (loopObj._elapsed or 0) + dt
                if loopObj._elapsed >= interval then
                    local stepDt = loopObj._elapsed
                    loopObj._elapsed = 0
                    local ok, err = pcall(loopObj.Fn, stepDt)
                    if not ok then loopObj.Stop() end
                end
            else
                local ok, err = pcall(loopObj.Fn, dt)
                if not ok then loopObj.Stop() end
            end
        end
    end
end)

-- ----------------------------------------------------------------------------
-- CORE BUILT-IN FUNCTIONS
-- ----------------------------------------------------------------------------

Env.P_NORMAL({
    Name = "arged",
    Description = "Dynamically prepends arguments from argGetter() to fn(...)"
}, function(self, fn, argGetter)
    assert(type(fn) == "function" or (type(fn) == "table" and getmetatable(fn) and getmetatable(fn).__call), "arged requires a callable function as arg 1")
    assert(type(argGetter) == "function", "arged requires an argument getter function as arg 2")

    return function(...)
        local callerArgs = table.pack(...)
        local injectedArgs = table.pack(argGetter())
        local combined = {}
        for i = 1, injectedArgs.n do
            table.insert(combined, injectedArgs[i])
        end
        for i = 1, callerArgs.n do
            table.insert(combined, callerArgs[i])
        end
        return fn(table.unpack(combined, 1, #combined))
    end
end)

local function resolvePlayerInternal(query)
    if not query or query == "" or query == "me" or query == "self" then
        return LocalPlayer
    end
    local q = tostring(query):lower()
    if q == "random" then
        local plrs = Players:GetPlayers()
        return #plrs > 0 and plrs[math.random(1, #plrs)] or nil
    elseif q == "closest" or q == "near" or q == "nearby" then
        local myChar = LocalPlayer.Character
        local myHrp = myChar and (myChar:FindFirstChild("HumanoidRootPart") or myChar.PrimaryPart)
        if not myHrp then return nil end

        local closest, minDist = nil, math.huge
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character then
                local pHrp = p.Character:FindFirstChild("HumanoidRootPart") or p.Character.PrimaryPart
                if pHrp then
                    local dist = (pHrp.Position - myHrp.Position).Magnitude
                    if dist < minDist then
                        minDist = dist
                        closest = p
                    end
                end
            end
        end
        return closest
    end

    for _, p in ipairs(Players:GetPlayers()) do
        if p.Name:lower() == q or p.DisplayName:lower() == q then return p end
    end
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Name:lower():sub(1, #q) == q or p.DisplayName:lower():sub(1, #q) == q then return p end
    end
    return nil
end

Env.P_NORMAL({
    Name = "plr",
    Description = "Finds and returns a Player object"
}, function(self, query)
    return resolvePlayerInternal(query)
end)

Env.P_NORMAL({
    Name = "char",
    Description = "Finds and returns a Player's Character Model"
}, function(self, query)
    local p = resolvePlayerInternal(query)
    return p and p.Character or nil
end)

Env.P_NORMAL({
    Name = "me",
    Description = "Returns the local player's character model"
}, function(self)
    return LocalPlayer.Character
end)

Env.P_NORMAL({
    Name = "each",
    Description = "Iterates over a table or instance children"
}, function(self, list, fn)
    assert(list ~= nil, "each requires a table or Instance as arg 1")
    assert(type(fn) == "function", "each requires a function as arg 2")
    if typeof(list) == "Instance" then
        list = list:GetChildren()
    end
    if type(list) == "table" then
        for k, v in pairs(list) do
            fn(v, k)
        end
    end
end)

Env.P_NORMAL({
    Name = "loop",
    Description = "Runs a callback repeatedly at a given Hz frequency"
}, function(self, hz, fn)
    assert(type(fn) == "function", "loop requires a function as arg 2")
    local rate = tonumber(hz) or 60
    local loopObj = {
        Active = true,
        Interval = rate > 0 and (1 / rate) or 0,
        Fn = fn,
        _elapsed = 0
    }
    local function stop()
        loopObj.Active = false
        Rerminal.ActiveLoops[loopObj] = nil
    end
    loopObj.Stop = stop
    Rerminal.ActiveLoops[loopObj] = true

    local currentPlugin = Rerminal.CurrentLoadingPlugin
    if currentPlugin then
        Rerminal.PluginTracking[currentPlugin] = Rerminal.PluginTracking[currentPlugin] or { EnvKeys = {}, Toggles = {}, Loops = {}, Binds = {} }
        table.insert(Rerminal.PluginTracking[currentPlugin].Loops, loopObj)
    end

    return stop
end)

local function normalizeKey(keyInput)
    if typeof(keyInput) == "EnumItem" then return keyInput end
    local str = tostring(keyInput)
    for _, item in ipairs(Enum.KeyCode:GetEnumItems()) do
        if item.Name:lower() == str:lower() then return item end
    end
    for _, item in ipairs(Enum.UserInputType:GetEnumItems()) do
        if item.Name:lower() == str:lower() then return item end
    end
    return nil
end

Env.P_NORMAL({
    Name = "bind",
    Description = "Binds a key to an action string or function and persists to file"
}, function(self, key, action)
    local keyEnum = normalizeKey(key)
    if not keyEnum then
        Env.log(Rerminal.Tag("Invalid KeyCode: " .. tostring(key), Rerminal.Colors.ERROR))
        return false
    end
    Rerminal.RawBinds[keyEnum.Name] = action
    Rerminal.SaveBinds()
    Env.log(Rerminal.Tag(string.format("Bound [%s] to action", keyEnum.Name), Rerminal.Colors.SUCCESS))
    return true
end)

Env.P_NORMAL({
    Name = "unbind",
    Description = "Unbinds a key and updates saved binds"
}, function(self, key)
    local keyEnum = normalizeKey(key)
    if not keyEnum then return false end
    Rerminal.RawBinds[keyEnum.Name] = nil
    Rerminal.SaveBinds()
    Env.log(Rerminal.Tag(string.format("Unbound key [%s]", keyEnum.Name), Rerminal.Colors.WARN))
    return true
end)

Rerminal.Connections["KeybindListener"] = UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe or Rerminal.IsOpen then return end
    local keyName = input.KeyCode ~= Enum.KeyCode.Unknown and input.KeyCode.Name or input.UserInputType.Name
    local action = Rerminal.RawBinds[keyName]
    if action then
        if type(action) == "function" then
            pcall(action)
        elseif type(action) == "string" then
            Rerminal.Run(action, true)
        elseif type(action) == "table" and getmetatable(action) and getmetatable(action).__call then
            pcall(action)
        end
    end
end)

-- ----------------------------------------------------------------------------
-- PLUGIN LIFECYCLE & DEPENDENCY RESOLUTION
-- ----------------------------------------------------------------------------

function Rerminal.GetPluginDependencies(pluginName)
    local cleanName = pluginName:gsub("%.lua$", "")
    if Rerminal.LoadedPlugins[cleanName] and Rerminal.LoadedPlugins[cleanName].Dependencies then
        return Rerminal.LoadedPlugins[cleanName].Dependencies
    end
    if not hasFS then return {} end

    local path = PLUGIN_FOLDER .. "/" .. cleanName .. ".lua"
    if not isfile(path) then
        path = PLUGIN_FOLDER .. "/" .. cleanName
    end
    if not isfile(path) then return {} end

    local content = readfile(path)

    -- 1. Static literal pattern: Dependencies = { ... } or dependencies = { ... }
    local depBlock = content:match("[Dd]ependenc[%a_]*%s*=%s*{(.-)}")
    if depBlock then
        local deps = {}
        for dep in depBlock:gmatch('["\']([^"\']+)["\']') do
            table.insert(deps, dep:gsub("%.lua$", "")[1])
        end
        return deps
    end

    -- 2. Comment pattern: -- Dependencies: a, b, c
    local commentDeps = content:match("%-%-%s*[Dd]ependenc[%a_]*%s*:%s*([%w_%-%.,%s]+)")
    if commentDeps then
        local deps = {}
        for dep in commentDeps:gmatch("[%w_%-]+") do
            table.insert(deps, dep:gsub("%.lua$", ""))
        end
        return deps
    end

    -- 3. Dry-run sandboxed attempt
    local fn = loadstring(content, "=" .. cleanName)
    if fn then
        local dryPlugin = { Name = cleanName, Dependencies = {} }
        local dryEnv = setmetatable({}, {
            __index = function(_, k)
                if Env[k] ~= nil then return Env[k] end
                return function() end
            end
        })
        setfenv(fn, dryEnv)
        local ok, res = pcall(fn, dryEnv, dryPlugin)
        if ok and type(res) == "function" then
            ok, res = pcall(res, dryEnv, dryPlugin)
        end
        if ok then
            local raw = (type(res) == "table" and (res.Dependencies or res.dependencies))
                or dryPlugin.Dependencies or dryPlugin.dependencies
            if type(raw) == "table" then
                local deps = {}
                for _, d in ipairs(raw) do
                    table.insert(deps, tostring(d):gsub("%.lua$", ""))
                end
                return deps
            end
        end
    end

    return {}
end

function Rerminal.ResolvePluginOrder(pluginList)
    local toLoad = {}
    local queue = {}

    for _, name in ipairs(pluginList) do
        local clean = name:gsub("%.lua$", "")
        if not toLoad[clean] then
            toLoad[clean] = true
            table.insert(queue, clean)
        end
    end

    -- Collect all transitive dependencies
    while #queue > 0 do
        local curr = table.remove(queue, 1)
        local deps = Rerminal.GetPluginDependencies(curr)
        for _, dep in ipairs(deps) do
            local cleanDep = dep:gsub("%.lua$", "")
            if not Rerminal.LoadedPlugins[cleanDep] and not toLoad[cleanDep] then
                toLoad[cleanDep] = true
                table.insert(queue, cleanDep)
            end
        end
    end

    -- Construct dependency graph
    local inDegree = {}
    local dependents = {}
    for u in pairs(toLoad) do
        inDegree[u] = 0
        dependents[u] = {}
    end

    for u in pairs(toLoad) do
        local deps = Rerminal.GetPluginDependencies(u)
        for _, dep in ipairs(deps) do
            local cleanDep = dep:gsub("%.lua$", "")
            if toLoad[cleanDep] then
                table.insert(dependents[cleanDep], u)
                inDegree[u] = inDegree[u] + 1
            end
        end
    end

    -- Nodes with inDegree == 0 are ready to load
    local available = {}
    for u in pairs(toLoad) do
        if inDegree[u] == 0 then
            table.insert(available, u)
        end
    end

    local sorted = {}
    local totalNodes = 0
    for _ in pairs(toLoad) do totalNodes = totalNodes + 1 end

    -- Kahn's Algorithm with randomized tie-breaking (random if no dependency)
    while #available > 0 do
        local randIdx = math.random(1, #available)
        local u = table.remove(available, randIdx)
        table.insert(sorted, u)

        for _, v in ipairs(dependents[u]) do
            inDegree[v] = inDegree[v] - 1
            if inDegree[v] == 0 then
                table.insert(available, v)
            end
        end
    end

    -- Circular dependency detection
    if #sorted < totalNodes then
        local cycleNodes = {}
        for u, deg in pairs(inDegree) do
            if deg > 0 then
                table.insert(cycleNodes, u)
            end
        end
        table.sort(cycleNodes)
        error("Circular dependency detected in plugins: " .. table.concat(cycleNodes, ", "), 2)
    end

    return sorted
end

function Rerminal.LoadPlugin(pluginName, skipAutoload)
    if not hasFS then return false, "No filesystem access" end
    ensureDirectories()

    local cleanName = pluginName:gsub("%.lua$", "")
    local path = PLUGIN_FOLDER .. "/" .. cleanName .. ".lua"
    if not isfile(path) then
        path = PLUGIN_FOLDER .. "/" .. cleanName
    end

    if not isfile(path) then return false, "File not found: " .. PLUGIN_FOLDER .. "/" .. cleanName .. ".lua" end

    -- Resolve dependency tree and calculate load order
    local okOrder, resolved = pcall(Rerminal.ResolvePluginOrder, { cleanName })
    if not okOrder then
        return false, tostring(resolved)
    end

    for _, depName in ipairs(resolved) do
        if depName ~= cleanName and not Rerminal.LoadedPlugins[depName] then
            local dOk, dErr = Rerminal.LoadPlugin(depName, true)
            if not dOk then
                return false, string.format("Failed loading dependency '%s': %s", depName, tostring(dErr))
            end
        end
    end

    if Rerminal.LoadedPlugins[cleanName] then Rerminal.UnloadPlugin(cleanName) end

    local content = readfile(path)
    local fn, err = loadstring(content, "=" .. cleanName)
    if not fn then return false, "Compile error: " .. tostring(err) end
    setfenv(fn, Env)

    local pluginObj = {
        Name = cleanName,
        OnUnload = nil,
        Dependencies = {}
    }

    Rerminal.CurrentLoadingPlugin = cleanName
    Rerminal.PluginTracking[cleanName] = { EnvKeys = {}, Toggles = {}, Loops = {}, Binds = {} }

    local ok, result = pcall(fn, Env, pluginObj)
    if ok and type(result) == "function" then
        ok, result = pcall(result, Env, pluginObj)
    end

    Rerminal.CurrentLoadingPlugin = nil

    if not ok then
        Rerminal.UnloadPlugin(cleanName)
        return false, "Runtime error: " .. tostring(result)
    end

    local rawDeps = (type(result) == "table" and (result.Dependencies or result.dependencies))
        or pluginObj.Dependencies or pluginObj.dependencies
    if type(rawDeps) == "table" then
        pluginObj.Dependencies = {}
        for _, d in ipairs(rawDeps) do
            table.insert(pluginObj.Dependencies, tostring(d):gsub("%.lua$", "")[1])
        end
    else
        pluginObj.Dependencies = Rerminal.GetPluginDependencies(cleanName)
    end

    if type(result) == "table" then
        if type(result.OnUnload) == "function" then
            pluginObj.OnUnload = result.OnUnload
        end
        for k, v in pairs(result) do
            if k ~= "OnUnload" and k ~= "Dependencies" and k ~= "dependencies" then
                Env[k] = v
                table.insert(Rerminal.PluginTracking[cleanName].EnvKeys, k)
            end
        end
    end

    Rerminal.LoadedPlugins[cleanName] = pluginObj
    if not skipAutoload and not table.find(Rerminal.AutoloadList, cleanName) then
        table.insert(Rerminal.AutoloadList, cleanName)
        Rerminal.SaveAutoload()
    end

    Rerminal.Notify("Plugin Loaded", cleanName, 2, "SUCCESS")
    return true
end

function Rerminal.UnloadPlugin(pluginName)
    local cleanName = pluginName:gsub("%.lua$", "")
    local pluginObj = Rerminal.LoadedPlugins[cleanName]
    if not pluginObj then return false, "Plugin not loaded" end

    if type(pluginObj.OnUnload) == "function" then
        pcall(pluginObj.OnUnload)
    end

    local tracking = Rerminal.PluginTracking[cleanName]
    if tracking then
        for _, toggleObj in ipairs(tracking.Toggles) do
            if toggleObj.State then toggleObj(false) end
            if toggleObj._connection then
                pcall(function() toggleObj._connection:Disconnect() end)
                toggleObj._connection = nil
            end
            Rerminal.ActiveToggles[toggleObj] = nil
        end
        for _, loopObj in ipairs(tracking.Loops) do
            loopObj.Stop()
        end
        for _, key in ipairs(tracking.EnvKeys) do
            Env[key] = nil
        end
    end

    Rerminal.LoadedPlugins[cleanName] = nil
    Rerminal.PluginTracking[cleanName] = nil
    Rerminal.Notify("Plugin Unloaded", cleanName, 2, "WARN")
    return true
end

Env.P_NORMAL({
    Name = "plugin",
    Description = "Loads, unloads, imports, or lists Rerminal plugins"
}, function(self, action, name)
    action = tostring(action or "list"):lower()
    if (action == "load" or action == "import") and name then
        local isImport = (action == "import")
        local ok, err = Rerminal.LoadPlugin(name, not isImport)
        if ok then
            Env.log(Rerminal.Tag("Successfully " .. (isImport and "imported (autoloaded)" or "loaded") .. " plugin: " .. name, Rerminal.Colors.SUCCESS))
        else
            Env.log(Rerminal.Tag("Failed to load plugin: " .. tostring(err), Rerminal.Colors.ERROR))
        end
    elseif action == "unload" and name then
        local ok, err = Rerminal.UnloadPlugin(name)
        if ok then
            Env.log(Rerminal.Tag("Unloaded plugin: " .. name, Rerminal.Colors.WARN))
        else
            Env.log(Rerminal.Tag("Failed to unload plugin: " .. tostring(err), Rerminal.Colors.ERROR))
        end
    elseif action == "reload" and name then
        Rerminal.UnloadPlugin(name)
        local ok, err = Rerminal.LoadPlugin(name)
        if ok then
            Env.log(Rerminal.Tag("Reloaded plugin: " .. name, Rerminal.Colors.SUCCESS))
        else
            Env.log(Rerminal.Tag("Failed to reload plugin: " .. tostring(err), Rerminal.Colors.ERROR))
        end
    else
        Env.log(Rerminal.Tag("=== LOADED PLUGINS ===", Rerminal.Colors.CMD))
        local count = 0
        for pName, pObj in pairs(Rerminal.LoadedPlugins) do
            count = count + 1
            local isAuto = table.find(Rerminal.AutoloadList, pName) ~= nil
            local autoTag = isAuto and Rerminal.Tag(" (autoload)", Rerminal.Colors.SPECIAL) or ""
            local depTag = ""
            if pObj and pObj.Dependencies and #pObj.Dependencies > 0 then
                depTag = " " .. Rerminal.Tag("[requires: " .. table.concat(pObj.Dependencies, ", ") .. "]", Rerminal.Colors.TABLE)
            end
            Env.log("• " .. Rerminal.Tag(pName, Rerminal.Colors.WHITE) .. autoTag .. depTag)
        end
        if count == 0 then Env.log(Rerminal.Tag("(No plugins loaded)", Rerminal.Colors.WHITE)) end
    end
end)

-- Help Command
Env.P_NORMAL({
    Name = "help",
    Description = "Lists all available functions, toggles, and plugins"
}, function(self, query)
    if query then
        local target = Env[query]
        if target then
            Env.log(Rerminal.Tag("=== OBJECT: " .. tostring(query) .. " ===", Rerminal.Colors.CMD))
            Env.log("• Type: " .. Rerminal.Tag(target._type or type(target), Rerminal.Colors.SPECIAL))
            if target.Description then Env.log("• Description: " .. tostring(target.Description)) end
            if target._type == "TOGGLE" then
                Env.log("• State: " .. Rerminal.Tag(tostring(target.State), target.State and Rerminal.Colors.SUCCESS or Rerminal.Colors.WARN))
                Env.log("• Interval: " .. tostring(target.Interval) .. "s")
            end
            return
        end
        local plug = Rerminal.LoadedPlugins[query]
        if plug then
            Env.log(Rerminal.Tag("=== PLUGIN: " .. tostring(query) .. " ===", Rerminal.Colors.CMD))
            local isAuto = table.find(Rerminal.AutoloadList, query) ~= nil
            Env.log("• Autoload: " .. Rerminal.Tag(tostring(isAuto), isAuto and Rerminal.Colors.SUCCESS or Rerminal.Colors.WARN))
            if plug.Dependencies and #plug.Dependencies > 0 then
                Env.log("• Dependencies: " .. Rerminal.Tag(table.concat(plug.Dependencies, ", "), Rerminal.Colors.TABLE))
            else
                Env.log("• Dependencies: " .. Rerminal.Tag("None", Rerminal.Colors.WHITE))
            end
            return
        end
    end

    Env.log(Rerminal.Tag("================ RERMINAL HELP ================", Rerminal.Colors.CMD))
    Env.log("Core Functions: " .. Rerminal.Tag("plr, char, me, my, each, loop, bind, unbind, arged, plugin, recolor, log, clear, exit, help", Rerminal.Colors.WHITE))
    
    local toggles, funcs, tables = {}, {}, {}
    for k, v in pairs(Env) do
        if type(v) == "table" then
            if v._type == "TOGGLE" then table.insert(toggles, k)
            elseif v._type == "FUNCTION" and not table.find({"plr","char","me","each","loop","bind","unbind","arged","plugin","recolor","log","clear","exit","help","P_NORMAL","P_TOGGLE"}, k) then
                table.insert(funcs, k)
            elseif not v._type then
                table.insert(tables, k)
            end
        end
    end

    if #toggles > 0 then Env.log("Custom Toggles: " .. Rerminal.Tag(table.concat(toggles, ", "), Rerminal.Colors.TOGGLE)) end
    if #funcs > 0 then Env.log("Custom Functions: " .. Rerminal.Tag(table.concat(funcs, ", "), Rerminal.Colors.CMD)) end
    if #tables > 0 then Env.log("Custom Tables: " .. Rerminal.Tag(table.concat(tables, ", "), Rerminal.Colors.TABLE)) end
end)

-- Recolor / Theme
Env.P_NORMAL({
    Name = "recolor",
    Description = "Sets syntax and UI colors"
}, function(self, element, hex)
    element = tostring(element or ""):upper()
    if not hex or hex == "" then
        Env.log(Rerminal.Tag("=== RERMINAL UI & SYNTAX THEME ===", Rerminal.Colors.CMD))
        for k, v in pairs(Rerminal.Colors) do
            Env.log(string.format("• %s: %s", Rerminal.Tag(k, v), Rerminal.Tag(v, Rerminal.Colors.WHITE)))
        end
        return
    end
    if Rerminal.Colors[element] ~= nil then
        Rerminal.Colors[element] = tostring(hex)
        Rerminal.SaveColors()
        Rerminal.UpdatePrompt()
        Env.log(Rerminal.Tag("Updated " .. element .. " to " .. hex, Rerminal.Colors.SUCCESS))
    else
        Env.log(Rerminal.Tag("Unknown color element: " .. element, Rerminal.Colors.ERROR))
    end
end)

-- log, clear, exit
Env.P_NORMAL({
    Name = "log",
    Description = "Prints formatted values to Rerminal console"
}, function(self, ...)
    local args = table.pack(...)
    local parts = {}
    for i = 1, args.n do
        local v = args[i]
        if type(v) == "string" then
            table.insert(parts, Rerminal.FormatValue(v, true))
        else
            table.insert(parts, Rerminal.FormatValue(v, false))
        end
    end
    Rerminal.Print(table.concat(parts, " "))
end)

Env.P_NORMAL({
    Name = "clear",
    Description = "Clears console output"
}, function(self)
    Rerminal.ClearConsole()
end)

Env.P_NORMAL({
    Name = "exit",
    Description = "Cleans up and unloads Rerminal"
}, function(self)
    Rerminal.Cleanup()
end)

-- ----------------------------------------------------------------------------
-- PROMPT EXECUTION & SESSION-WIDE VARIABLES
-- ----------------------------------------------------------------------------
function Rerminal.Run(codeStr, silentPrompt)
    local raw = (codeStr or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if raw == "" then return end

    if not silentPrompt then
        Rerminal.Print(Rerminal.GetPromptRich() .. Rerminal.Tag(raw, Rerminal.Colors.WHITE))
        table.insert(Rerminal.History, raw)
        Rerminal.HistoryIndex = #Rerminal.History + 1
    end

    local sanitized = raw
    local varName, rest = raw:match("^local%s+([%a_][%w_]*)%s*=%s*(.+)$")
    if varName and rest then
        sanitized = varName .. " = " .. rest
    end

    -- 1. Try evaluating as an expression (`return <expr>`)
    local exprFn, _ = loadstring("return " .. sanitized, "=Rerminal")
    if exprFn then
        setfenv(exprFn, Env)
        local ok, result = pcall(exprFn)
        if ok then
            if result ~= nil then
                Rerminal.Print(Rerminal.FormatValue(result, false))
            end
            return
        end
    end

    -- 2. Evaluate as a standard Lua statement
    local stmtFn, stmtErr = loadstring(sanitized, "=Rerminal")
    if stmtFn then
        setfenv(stmtFn, Env)
        local ok, err = pcall(stmtFn)
        if not ok then
            Rerminal.Print(Rerminal.Tag("[Runtime Error] " .. tostring(err), Rerminal.Colors.ERROR))
        end
    else
        Rerminal.Print(Rerminal.Tag("[Syntax Error] " .. tostring(stmtErr), Rerminal.Colors.ERROR))
    end
end

-- ----------------------------------------------------------------------------
-- AUTOCOMPLETE
-- ----------------------------------------------------------------------------
local currentMatches = {}
local selectedMatchIdx = 1

local function getAutocompleteList(rawText)
    local matches = {}
    local text = rawText:match("([%a_][%w_%.%:]*)$") or ""
    if text == "" then return matches end

    local parts = {}
    for seg in text:gmatch("[^%.]+") do table.insert(parts, seg) end
    local hasEndDot = text:sub(-1) == "."

    -- Dot Member Inspection
    if #parts > 1 or hasEndDot then
        local curr = Env
        local limit = hasEndDot and #parts or (#parts - 1)
        for idx = 1, limit do
            if type(curr) == "table" or typeof(curr) == "Instance" then
                curr = curr[parts[idx]]
            else
                curr = nil
                break
            end
        end

        local query = hasEndDot and "" or (parts[#parts]:lower())

        if type(curr) == "table" then
            for k, v in pairs(curr) do
                if tostring(k):lower():sub(1, #query) == query then
                    local mType = "TABLE_PROP"
                    if type(v) == "function" or (type(v) == "table" and v._type == "FUNCTION") then mType = "FUNC"
                    elseif type(v) == "table" and v._type == "TOGGLE" then mType = "TOGGLE"
                    elseif type(v) == "table" then mType = "TABLE"
                    end
                    table.insert(matches, {
                        Type = mType,
                        Display = tostring(k),
                        Apply = rawText:sub(1, #rawText - #query) .. tostring(k)
                    })
                end
            end
        elseif typeof(curr) == "Instance" then
            for _, ch in ipairs(curr:GetChildren()) do
                if ch.Name:lower():sub(1, #query) == query then
                    table.insert(matches, {
                        Type = "INST",
                        Display = ch.Name,
                        Apply = rawText:sub(1, #rawText - #query) .. ch.Name
                    })
                end
            end
        end
        return matches
    end

    -- Top-Level Identifiers & Keywords
    local q = text:lower()

    for k, v in pairs(Env) do
        if tostring(k):lower():sub(1, #q) == q then
            local mType = "GLOBAL"
            if type(v) == "function" or (type(v) == "table" and v._type == "FUNCTION") then mType = "FUNC"
            elseif type(v) == "table" and v._type == "TOGGLE" then mType = "TOGGLE"
            elseif type(v) == "table" then mType = "TABLE"
            end
            table.insert(matches, {
                Type = mType,
                Display = tostring(k),
                Apply = rawText:sub(1, #rawText - #text) .. tostring(k)
            })
        end
    end

    for _, kw in ipairs({"local", "function", "return", "for", "if", "then", "end", "while", "do", "in", "workspace", "game"}) do
        if kw:sub(1, #q) == q then
            table.insert(matches, {
                Type = "KEYWORD",
                Display = kw,
                Apply = rawText:sub(1, #rawText - #text) .. kw
            })
        end
    end

    return matches
end

local function renderSuggestions()
    for _, ch in ipairs(suggestionScroll:GetChildren()) do
        if ch:IsA("Frame") then ch:Destroy() end
    end

    if #currentMatches == 0 then
        suggestionBox.Visible = false
        ghostLabel.Text = ""
        return
    end

    suggestionBox.Visible = true
    selectedMatchIdx = math.clamp(selectedMatchIdx, 1, #currentMatches)

    local totalHeight = math.min((#currentMatches * 24) + 8, 180)
    suggestionBox.Size = UDim2.new(0, 440, 0, totalHeight)

    for i, item in ipairs(currentMatches) do
        local row = Instance.new("Frame")
        row.Name = "Row_" .. i
        row.Size = UDim2.new(1, 0, 0, 22)
        row.BorderSizePixel = 0
        row.BackgroundColor3 = (i == selectedMatchIdx) and Color3.fromRGB(35, 45, 65) or Color3.fromRGB(18, 18, 24)
        row.Parent = suggestionScroll

        local badge = Instance.new("TextLabel")
        badge.Size = UDim2.new(0, 75, 1, 0)
        badge.Position = UDim2.new(0, 4, 0, 0)
        badge.BackgroundTransparency = 1
        badge.Font = Enum.Font.Code
        badge.TextSize = 11
        badge.TextXAlignment = Enum.TextXAlignment.Left

        if item.Type == "FUNC" then badge.TextColor3 = Color3.fromHex(Rerminal.Colors.CMD); badge.Text = "[FUNC]"
        elseif item.Type == "TOGGLE" then badge.TextColor3 = Color3.fromHex(Rerminal.Colors.TOGGLE); badge.Text = "[TOGGLE]"
        elseif item.Type == "TABLE" then badge.TextColor3 = Color3.fromHex(Rerminal.Colors.TABLE); badge.Text = "[TABLE]"
        elseif item.Type == "INST" then badge.TextColor3 = Color3.fromHex(Rerminal.Colors.INSTANCE); badge.Text = "[INST]"
        elseif item.Type == "KEYWORD" then badge.TextColor3 = Color3.fromHex(Rerminal.Colors.SPECIAL); badge.Text = "[KEY]"
        else badge.TextColor3 = Color3.fromHex(Rerminal.Colors.WHITE); badge.Text = "[VAR]"
        end
        badge.Parent = row

        local textLbl = Instance.new("TextLabel")
        textLbl.Size = UDim2.new(1, -85, 1, 0)
        textLbl.Position = UDim2.new(0, 80, 0, 0)
        textLbl.BackgroundTransparency = 1
        textLbl.Font = Enum.Font.Code
        textLbl.TextSize = 13
        textLbl.TextColor3 = (i == selectedMatchIdx) and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(180, 180, 190)
        textLbl.TextXAlignment = Enum.TextXAlignment.Left
        textLbl.Text = item.Display
        textLbl.Parent = row
    end

    local targetY = (selectedMatchIdx - 1) * 24
    suggestionScroll.CanvasPosition = Vector2.new(0, math.clamp(targetY - 48, 0, 9999))

    local selected = currentMatches[selectedMatchIdx]
    if selected and selected.Apply:lower():sub(1, #inputBox.Text) == inputBox.Text:lower() then
        ghostLabel.Text = inputBox.Text .. selected.Apply:sub(#inputBox.Text + 1)
    else
        ghostLabel.Text = ""
    end
end

-- ----------------------------------------------------------------------------
-- CONSOLE VISIBILITY & INPUT ROUTING
-- ----------------------------------------------------------------------------
local function setConsole(state)
    Rerminal.IsOpen = state
    if Rerminal.IsOpen then
        canvasGroup.Visible = true
        Rerminal.UpdatePrompt()
        inputBox.Text = ""
        ghostLabel.Text = ""
        currentMatches = {}
        renderSuggestions()
        TweenService:Create(canvasGroup, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {GroupTransparency = 0}):Play()
        task.defer(function()
            inputBox.Text = ""
            inputBox:CaptureFocus()
        end)
    else
        inputBox:ReleaseFocus()
        local tw = TweenService:Create(canvasGroup, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {GroupTransparency = 1})
        tw:Play()
        tw.Completed:Connect(function()
            if not Rerminal.IsOpen then canvasGroup.Visible = false end
        end)
    end
end

Rerminal.Connections["ToggleUI"] = UserInputService.InputBegan:Connect(function(input, gpe)
    if input.KeyCode == Enum.KeyCode.Home then
        setConsole(not Rerminal.IsOpen)
    end
end)

Rerminal.Connections["TextChange"] = inputBox:GetPropertyChangedSignal("Text"):Connect(function()
    local text = inputBox.Text
    if text:find("\t") then
        inputBox.Text = text:gsub("\t", "")
        return
    end
    currentMatches = getAutocompleteList(inputBox.Text)
    selectedMatchIdx = 1
    renderSuggestions()
end)

local isExecuting = false
local function executeNow()
    if isExecuting then return end
    isExecuting = true
    local text = inputBox.Text
    inputBox.Text = ""
    ghostLabel.Text = ""
    currentMatches = {}
    renderSuggestions()
    Rerminal.Run(text)
    task.defer(function()
        if Rerminal.IsOpen then inputBox:CaptureFocus() end
        isExecuting = false
    end)
end

Rerminal.Connections["KeyNav"] = UserInputService.InputBegan:Connect(function(input, _)
    if not Rerminal.IsOpen then return end

    if input.KeyCode == Enum.KeyCode.Tab then
        if #currentMatches > 0 and currentMatches[selectedMatchIdx] then
            inputBox.Text = currentMatches[selectedMatchIdx].Apply
            inputBox.CursorPosition = #inputBox.Text + 1
            currentMatches = {}
            renderSuggestions()
        end
        task.defer(function() if Rerminal.IsOpen then inputBox:CaptureFocus() end end)

    elseif input.KeyCode == Enum.KeyCode.Return then
        executeNow()

    elseif input.KeyCode == Enum.KeyCode.Up then
        if #currentMatches > 1 then
            selectedMatchIdx = (selectedMatchIdx - 2) % #currentMatches + 1
            renderSuggestions()
        elseif #Rerminal.History > 0 then
            if Rerminal.HistoryIndex > #Rerminal.History then Rerminal.Draft = inputBox.Text end
            Rerminal.HistoryIndex = math.max(1, Rerminal.HistoryIndex - 1)
            inputBox.Text = Rerminal.History[Rerminal.HistoryIndex] or ""
            inputBox.CursorPosition = #inputBox.Text + 1
        end

    elseif input.KeyCode == Enum.KeyCode.Down then
        if #currentMatches > 1 then
            selectedMatchIdx = selectedMatchIdx % #currentMatches + 1
            renderSuggestions()
        elseif Rerminal.HistoryIndex <= #Rerminal.History then
            Rerminal.HistoryIndex = Rerminal.HistoryIndex + 1
            inputBox.Text = Rerminal.History[Rerminal.HistoryIndex] or Rerminal.Draft
            inputBox.CursorPosition = #inputBox.Text + 1
        end
    end
end)

-- ----------------------------------------------------------------------------
-- CLEANUP & BOOT
-- ----------------------------------------------------------------------------
function Rerminal.Cleanup()
    Rerminal.IsOpen = false
    for toggleObj in pairs(Rerminal.ActiveToggles) do
        toggleObj(false)
    end
    for _, loopObj in pairs(Rerminal.ActiveLoops) do
        loopObj.Stop()
    end
    for plugName in pairs(Rerminal.LoadedPlugins) do
        Rerminal.UnloadPlugin(plugName)
    end
    for _, c in pairs(Rerminal.Connections) do
        if c and c.Disconnect then pcall(function() c:Disconnect() end) end
    end
    table.clear(Rerminal.Connections)
    if screenGui then screenGui:Destroy() end
    _G.Rerminal = nil
    _G.RerminalCleanup = nil
end
_G.RerminalCleanup = Rerminal.Cleanup

Rerminal.LoadColors()
Rerminal.LoadBinds()
Rerminal.LoadAutoload()

if #Rerminal.AutoloadList > 0 then
    task.spawn(function()
        local okOrder, ordered = pcall(Rerminal.ResolvePluginOrder, Rerminal.AutoloadList)
        if not okOrder then
            Env.log(Rerminal.Tag("[Autoload Dependency Error] " .. tostring(ordered), Rerminal.Colors.ERROR))
            Rerminal.Notify("Dependency Error", tostring(ordered), 4, "ERROR")
        else
            for _, plug in ipairs(ordered) do
                Rerminal.LoadPlugin(plug, true)
            end
        end
    end)
end

Rerminal.UpdatePrompt()
Rerminal.Notify("Rerminal Ready", "Press 'Home' to open console", 3, "SUCCESS")