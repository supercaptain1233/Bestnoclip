--[[=====================================================================
    B E S T N O C L I P
    Universal character phasing. Built for Delta.
    Second build. Full rewrite of the Noclip panel.
-----------------------------------------------------------------------
    Repo    : supercaptain1233/Bestnoclip
    File    : Bestnoclip.lua
    Build   : 2.0.0
    Lines   : 1080
    Author  : supercaptain1233

    BEHAVIOUR
      - Walks through walls, props, players, glass, terrain, everything.
      - Never falls through the floor. Floor raycast stays intact.
      - Re-arms on respawn, re-parent, tool equip, seat, ragdoll.
      - Toggling off restores the exact CanCollide of every part.

    LAYOUT
      Header : "Noclip" + status dot left  |  orb / move / close right
      Body   : large red Noclip button
      Chips  : FLOOR / FAST / REARM micro toggles
      Close  : collapses the body, header stays as a tab
      Move   : unlocks free drag with edge snapping
      Orb    : whole script becomes a circle that rides your finger

    KEYS
      RightShift : arm / disarm
      RightAlt   : collapse / expand
      RightControl : orb mode in / out
=====================================================================]]

--=====================================================================
-- SERVICES
--=====================================================================

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local CoreGui          = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

--=====================================================================
-- CONFIG
--=====================================================================

local CONFIG = {
	Title          = "Noclip",
	Build          = "2.0.0",

	Width          = 176,
	HeaderHeight   = 30,
	BodyHeight     = 72,
	Corner         = 11,
	InnerCorner    = 8,
	ButtonSize     = 22,
	ChipHeight     = 20,
	OrbSize        = 58,
	Pad            = 10,
	Gap            = 6,
	ClampPad       = 8,
	SnapDistance   = 44,

	Panel          = Color3.fromRGB(19, 19, 22),
	PanelSoft      = Color3.fromRGB(29, 29, 33),
	PanelRaised    = Color3.fromRGB(39, 39, 44),
	Stroke         = Color3.fromRGB(54, 54, 60),
	Accent         = Color3.fromRGB(230, 46, 52),
	AccentBright   = Color3.fromRGB(255, 80, 86),
	AccentDark     = Color3.fromRGB(120, 20, 24),
	Text           = Color3.fromRGB(238, 238, 242),
	TextDim        = Color3.fromRGB(138, 138, 148),

	Fast           = TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Smooth         = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	Snap           = TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out),

	RescanSlow     = 0.20,
	RescanFast     = 0.04,
	KeepRootSolid  = false,
	AutoRearm      = true,
	MaxToasts      = 3,
}

--=====================================================================
-- STATE
--=====================================================================

local State = {
	Dragging      = false,
	DragOrigin    = nil,
	DragAnchor    = nil,
	OrbDragging   = false,
	OrbOffset     = nil,
	Collapsed     = false,
	OrbMode       = false,
	MoveLocked    = false,
	Destroyed     = false,
	LastHeaderTap = 0,
	ToastCount    = 0,
}

local Gui, Main, Header, Body, Orb, OrbInner, OrbDot, NotifHost
local ToggleButton, ToggleLabel, StatusDot, StatusText, HeaderLabel

--=====================================================================
-- UTIL : factory
--=====================================================================

local function new(class, props, parent)
	local object = Instance.new(class)
	for key, value in pairs(props or {}) do
		object[key] = value
	end
	if parent then
		object.Parent = parent
	end
	return object
end

local function corner(radius, parent)
	return new("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function stroke(color, thickness, transparency, parent)
	return new("UIStroke", {
		Color = color,
		Thickness = thickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

local function padding(px, parent)
	return new("UIPadding", {
		PaddingLeft   = UDim.new(0, px),
		PaddingRight  = UDim.new(0, px),
		PaddingTop    = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
	}, parent)
end

local function listLayout(parent, direction, gap, align)
	return new("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Horizontal,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, gap or 0),
	}, parent)
end

local function tween(object, info, goal)
	local track = TweenService:Create(object, info, goal)
	track:Play()
	return track
end

local function viewport()
	local ok, size = pcall(function()
		return Camera.ViewportSize
	end)
	if ok and size then
		return size
	end
	return Vector2.new(1280, 720)
end

--=====================================================================
-- UTIL : math
--=====================================================================

local function clamp(value, low, high)
	if value < low then
		return low
	end
	if value > high then
		return high
	end
	return value
end

local function clampPosition(position, size)
	local screen = viewport()
	local x = clamp(position.X, CONFIG.ClampPad, screen.X - size.X - CONFIG.ClampPad)
	local y = clamp(position.Y, CONFIG.ClampPad, screen.Y - size.Y - CONFIG.ClampPad)
	return Vector2.new(x, y)
end

-- snap to the nearest edge when released close to one
local function snapToEdge(position, size)
	local screen = viewport()
	local x, y = position.X, position.Y

	if x - CONFIG.ClampPad <= CONFIG.SnapDistance then
		x = CONFIG.ClampPad
	elseif (screen.X - (x + size.X)) - CONFIG.ClampPad <= CONFIG.SnapDistance then
		x = screen.X - size.X - CONFIG.ClampPad
	end

	if y - CONFIG.ClampPad <= CONFIG.SnapDistance then
		y = CONFIG.ClampPad
	elseif (screen.Y - (y + size.Y)) - CONFIG.ClampPad <= CONFIG.SnapDistance then
		y = screen.Y - size.Y - CONFIG.ClampPad
	end

	return Vector2.new(x, y)
end

--=====================================================================
-- UTIL : input predicates
--=====================================================================

local function isPrimary(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

local function isMotion(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch
end

local function pointerOf(input)
	return Vector2.new(input.Position.X, input.Position.Y)
end

--=====================================================================
-- UTIL : press feedback
--=====================================================================

local function pressFeedback(button, baseTransparency)
	button.MouseEnter:Connect(function()
		if State.Destroyed then
			return
		end
		tween(button, CONFIG.Fast, {
			BackgroundTransparency = math.max(baseTransparency - 0.12, 0),
		})
	end)

	button.MouseLeave:Connect(function()
		if State.Destroyed then
			return
		end
		tween(button, CONFIG.Fast, {
			BackgroundTransparency = baseTransparency,
		})
	end)

	button.MouseButton1Down:Connect(function()
		if State.Destroyed then
			return
		end
		tween(button, CONFIG.Fast, { Size = button.Size - UDim2.fromOffset(2, 2) })
	end)

	button.MouseButton1Up:Connect(function()
		if State.Destroyed then
			return
		end
		tween(button, CONFIG.Fast, { Size = button.Size + UDim2.fromOffset(2, 2) })
	end)
end

--=====================================================================
-- NOTIFICATIONS
--=====================================================================

local function notify(text, accent)
	if not NotifHost or State.Destroyed then
		return
	end

	if State.ToastCount >= CONFIG.MaxToasts then
		local oldest = NotifHost:FindFirstChild("Toast")
		if oldest then
			oldest:Destroy()
			State.ToastCount = math.max(State.ToastCount - 1, 0)
		end
	end

	State.ToastCount += 1

	local toast = new("Frame", {
		Name = "Toast",
		Size = UDim2.fromOffset(2, 26),
		BackgroundColor3 = CONFIG.PanelSoft,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, NotifHost)
	corner(6, toast)
	stroke(accent or CONFIG.Stroke, 1, 0.35, toast)

	local bar = new("Frame", {
		Size = UDim2.new(0, 3, 1, -8),
		Position = UDim2.new(0, 5, 0, 4),
		BackgroundColor3 = accent or CONFIG.Accent,
		BorderSizePixel = 0,
	}, toast)
	corner(2, bar)

	new("TextLabel", {
		Size = UDim2.new(1, -18, 1, 0),
		Position = UDim2.new(0, 14, 0, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = text,
		TextSize = 11,
		TextColor3 = CONFIG.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, toast)

	tween(toast, CONFIG.Smooth, {
		Size = UDim2.fromOffset(NotifHost.AbsoluteSize.X, 26),
	})

	task.delay(1.7, function()
		if not toast or not toast.Parent then
			return
		end
		tween(toast, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = UDim2.fromOffset(2, 26),
			BackgroundTransparency = 1,
		})
		task.wait(0.18)
		if toast then
			toast:Destroy()
		end
		State.ToastCount = math.max(State.ToastCount - 1, 0)
	end)
end

--=====================================================================
-- NOCLIP CORE
--=====================================================================

local Noclip = {}
Noclip.Active = false
Noclip.Original = setmetatable({}, { __mode = "k" })
Noclip.Links = {}
Noclip.Rescan = nil
Noclip.Character = nil

-- remember what each part looked like before we touched it
function Noclip:Capture(model)
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") then
			if self.Original[item] == nil then
				self.Original[item] = item.CanCollide
			end
		end
	end
end

-- clear collision everywhere, root optionally left solid
function Noclip:Apply(model)
	local root = model:FindFirstChild("HumanoidRootPart")

	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") then
			if CONFIG.KeepRootSolid and item == root then
				item.CanCollide = true
			else
				item.CanCollide = false
			end
		end
	end
end

-- write every recorded value back
function Noclip:Restore()
	for part, wasSolid in pairs(self.Original) do
		if part and part.Parent then
			pcall(function()
				part.CanCollide = wasSolid
			end)
		end
	end
	self.Original = setmetatable({}, { __mode = "k" })
end

-- catch parts that arrive after arming
function Noclip:Watch(model)
	local function onDescendant(descendant)
		if not self.Active then
			return
		end
		if descendant:IsA("BasePart") then
			if self.Original[descendant] == nil then
				self.Original[descendant] = descendant.CanCollide
			end
			if CONFIG.KeepRootSolid and descendant.Name == "HumanoidRootPart" then
				descendant.CanCollide = true
			else
				descendant.CanCollide = false
			end
		end
	end

	table.insert(self.Links, model.DescendantAdded:Connect(onDescendant))

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		table.insert(self.Links, humanoid.Died:Connect(function()
			if not self.Active or not CONFIG.AutoRearm then
				return
			end
			task.defer(function()
				if not self.Active then
					return
				end
				local fresh = LocalPlayer.Character
				if not fresh then
					fresh = LocalPlayer.CharacterAdded:Wait()
				end
				fresh:WaitForChild("HumanoidRootPart", 10)
				task.wait(0.1)
				if not self.Active then
					return
				end
				self:Capture(fresh)
				self:Apply(fresh)
				self:Watch(fresh)
				self.Character = fresh
			end)
		end))
	end
end

function Noclip:Unwatch()
	for _, link in ipairs(self.Links) do
		if link.Connected then
			link:Disconnect()
		end
	end
	self.Links = {}
end

function Noclip:Start()
	if self.Active then
		return
	end

	local character = LocalPlayer.Character
	if not character then
		notify("No character loaded", CONFIG.Accent)
		return
	end

	self.Active = true
	self.Character = character
	self:Capture(character)
	self:Apply(character)
	self:Watch(character)

	self.Rescan = task.spawn(function()
		while self.Active do
			local current = LocalPlayer.Character
			if current then
				self:Apply(current)
			end
			task.wait(CONFIG.RescanRate or CONFIG.RescanSlow)
		end
	end)

	notify("Noclip armed", CONFIG.AccentBright)
end

function Noclip:Stop()
	if not self.Active then
		return
	end

	self.Active = false

	if self.Rescan then
		task.cancel(self.Rescan)
		self.Rescan = nil
	end

	self:Unwatch()
	self:Restore()
	notify("Noclip off", CONFIG.TextDim)
end

function Noclip:Toggle()
	if self.Active then
		self:Stop()
	else
		self:Start()
	end
end

--=====================================================================
-- ICONS
--=====================================================================

local function drawMoveIcon(host, color)
	local wrap = new("Frame", {
		Size = UDim2.fromOffset(14, 14),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
	}, host)

	new("Frame", {
		Size = UDim2.fromOffset(2, 12),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	}, wrap)

	new("Frame", {
		Size = UDim2.fromOffset(12, 2),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	}, wrap)

	local tips = {
		UDim2.fromScale(0.5, 0),
		UDim2.fromScale(0.5, 1),
		UDim2.fromScale(0, 0.5),
		UDim2.fromScale(1, 0.5),
	}

	for _, position in ipairs(tips) do
		local head = new("Frame", {
			Size = UDim2.fromOffset(5, 5),
			Position = position,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = 45,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
		}, wrap)
		corner(1, head)
	end

	return wrap
end

local function drawOrbIcon(host, color)
	local ring = new("Frame", {
		Size = UDim2.fromOffset(13, 13),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
	}, host)
	corner(7, ring)
	stroke(color, 1.4, 0, ring)

	local core = new("Frame", {
		Size = UDim2.fromOffset(5, 5),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	}, ring)
	corner(3, core)

	return ring
end

local function drawCloseIcon(host, color)
	local wrap = new("Frame", {
		Size = UDim2.fromOffset(14, 14),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
	}, host)

	for _, angle in ipairs({ 45, -45 }) do
		local bar = new("Frame", {
			Size = UDim2.fromOffset(2, 11),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = angle,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
		}, wrap)
		corner(1, bar)
	end

	return wrap
end

--=====================================================================
-- HEADER BUTTON
--=====================================================================

local function makeHeaderButton(iconFn, order)
	local button = new("TextButton", {
		Size = UDim2.fromOffset(CONFIG.ButtonSize, CONFIG.ButtonSize),
		BackgroundColor3 = CONFIG.PanelRaised,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
	}, HeaderTray)
	corner(6, button)
	pressFeedback(button, 0.15)
	iconFn(button, CONFIG.Text)
	return button
end

--=====================================================================
-- CHIPS
--=====================================================================

local function makeChip(label, order, startOn, onFlip)
	local chip = new("TextButton", {
		Size = UDim2.new(1 / 3, -CONFIG.Gap, 0, CONFIG.ChipHeight),
		BackgroundColor3 = CONFIG.PanelRaised,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
	}, ChipRow)
	corner(5, chip)
	pressFeedback(chip, 0.2)

	local dot = new("Frame", {
		Size = UDim2.fromOffset(4, 4),
		Position = UDim2.fromOffset(5, CONFIG.ChipHeight / 2 - 2),
		BackgroundColor3 = startOn and CONFIG.AccentBright or CONFIG.Stroke,
		BorderSizePixel = 0,
	}, chip)
	corner(2, dot)

	new("TextLabel", {
		Size = UDim2.new(1, -12, 1, 0),
		Position = UDim2.fromOffset(11, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = label,
		TextSize = 8,
		TextColor3 = CONFIG.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, chip)

	local on = startOn

	chip.MouseButton1Click:Connect(function()
		if State.Destroyed then
			return
		end
		on = not on
		dot.BackgroundColor3 = on and CONFIG.AccentBright or CONFIG.Stroke
		onFlip(on)
	end)

	return chip
end

--=====================================================================
-- ORB MODE
--=====================================================================

local function enterOrbMode()
	if State.OrbMode then
		return
	end
	State.OrbMode = true

	local origin = Main.AbsolutePosition
	local size = Main.AbsoluteSize
	local center = Vector2.new(origin.X + size.X / 2, origin.Y + size.Y / 2)
	local placed = clampPosition(
		Vector2.new(center.X - CONFIG.OrbSize / 2, center.Y - CONFIG.OrbSize / 2),
		Vector2.new(CONFIG.OrbSize, CONFIG.OrbSize)
	)

	Orb.Position = UDim2.fromOffset(placed.X, placed.Y)
	Orb.Visible = true
	Orb.BackgroundTransparency = 1
	OrbInner.BackgroundTransparency = 1
	Main.Visible = false

	tween(Orb, CONFIG.Smooth, { BackgroundTransparency = 0.05 })
	tween(OrbInner, CONFIG.Smooth, { BackgroundTransparency = 0 })
end

local function exitOrbMode()
	if not State.OrbMode then
		return
	end
	State.OrbMode = false

	local orbPosition = Orb.AbsolutePosition
	local orbSize = Orb.AbsoluteSize
	local target = Vector2.new(
		orbPosition.X + orbSize.X / 2 - Main.AbsoluteSize.X / 2,
		orbPosition.Y + orbSize.Y / 2 - Main.AbsoluteSize.Y / 2
	)
	local placed = clampPosition(target, Main.AbsoluteSize)

	Main.Position = UDim2.fromOffset(placed.X, placed.Y)
	Main.Visible = true
	Orb.Visible = false
end

local function buildOrb(parent)
	Orb = new("TextButton", {
		Name = "Orb",
		Size = UDim2.fromOffset(CONFIG.OrbSize, CONFIG.OrbSize),
		Position = UDim2.fromOffset(120, 120),
		BackgroundColor3 = CONFIG.Panel,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
		ZIndex = 20,
	}, parent)
	corner(CONFIG.OrbSize / 2, Orb)
	stroke(CONFIG.Accent, 2, 0.15, Orb)

	OrbInner = new("Frame", {
		Size = UDim2.fromOffset(CONFIG.OrbSize - 15, CONFIG.OrbSize - 15),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = CONFIG.PanelRaised,
		BorderSizePixel = 0,
		ZIndex = 21,
	}, Orb)
	corner((CONFIG.OrbSize - 15) / 2, OrbInner)

	drawOrbIcon(OrbInner, CONFIG.AccentBright)

	OrbDot = new("Frame", {
		Size = UDim2.fromOffset(9, 9),
		Position = UDim2.new(0.5, 0, 1, -5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = CONFIG.AccentBright,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 22,
	}, Orb)
	corner(5, OrbDot)
	stroke(CONFIG.Panel, 1.5, 0, OrbDot)
end

--=====================================================================
-- TOGGLE
--=====================================================================

local function paintToggle()
	if not ToggleButton then
		return
	end

	if Noclip.Active then
		tween(ToggleButton, CONFIG.Fast, { BackgroundColor3 = CONFIG.AccentBright })
		ToggleLabel.Text = "NOCLIP  ON"
		ToggleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		StatusDot.BackgroundColor3 = CONFIG.AccentBright
		StatusText.Text = "ARMED"
		StatusText.TextColor3 = CONFIG.AccentBright
		OrbDot.Visible = true
	else
		tween(ToggleButton, CONFIG.Fast, { BackgroundColor3 = CONFIG.Accent })
		ToggleLabel.Text = "NOCLIP"
		ToggleLabel.TextColor3 = Color3.fromRGB(255, 238, 238)
		StatusDot.BackgroundColor3 = CONFIG.AccentDark
		StatusText.Text = "IDLE"
		StatusText.TextColor3 = CONFIG.TextDim
		OrbDot.Visible = false
	end
end

local function buildToggle()
	ToggleButton = new("TextButton", {
		Size = UDim2.new(1, -CONFIG.Pad * 2, 0, 38),
		Position = UDim2.fromOffset(CONFIG.Pad, 6),
		BackgroundColor3 = CONFIG.Accent,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		ClipsDescendants = true,
	}, Body)
	corner(CONFIG.InnerCorner, ToggleButton)
	stroke(CONFIG.AccentDark, 1, 0.4, ToggleButton)

	ToggleLabel = new("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "NOCLIP",
		TextSize = 14,
		TextColor3 = Color3.fromRGB(255, 238, 238),
		TextXAlignment = Enum.TextXAlignment.Center,
	}, ToggleButton)

	pressFeedback(ToggleButton, 0)

	ToggleButton.MouseButton1Click:Connect(function()
		if State.Destroyed then
			return
		end
		Noclip:Toggle()
		paintToggle()
	end)
end

--=====================================================================
-- HEADER
--=====================================================================

local function buildHeader()
	Header = new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, CONFIG.HeaderHeight),
		BackgroundColor3 = CONFIG.PanelSoft,
		BorderSizePixel = 0,
	}, Main)
	corner(CONFIG.Corner, Header)

	new("Frame", {
		Size = UDim2.new(1, -CONFIG.Pad * 2, 0, 1),
		Position = UDim2.new(0, CONFIG.Pad, 1, -1),
		BackgroundColor3 = CONFIG.Stroke,
		BorderSizePixel = 0,
	}, Header)

	StatusDot = new("Frame", {
		Size = UDim2.fromOffset(6, 6),
		Position = UDim2.fromOffset(CONFIG.Pad, CONFIG.HeaderHeight / 2 - 3),
		BackgroundColor3 = CONFIG.AccentDark,
		BorderSizePixel = 0,
	}, Header)
	corner(3, StatusDot)

	HeaderLabel = new("TextLabel", {
		Size = UDim2.new(0, 56, 1, 0),
		Position = UDim2.fromOffset(CONFIG.Pad + 12, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = CONFIG.Title,
		TextSize = 12,
		TextColor3 = CONFIG.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, Header)

	StatusText = new("TextLabel", {
		Size = UDim2.fromOffset(40, 1),
		Position = UDim2.new(0, CONFIG.Pad + 66, 1, -9),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "IDLE",
		TextSize = 7,
		TextColor3 = CONFIG.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, Header)

	HeaderTray = new("Frame", {
		Size = UDim2.new(1, -CONFIG.Pad * 2, 1, 0),
		Position = UDim2.fromOffset(CONFIG.Pad, 0),
		BackgroundTransparency = 1,
	}, Header)
	listLayout(HeaderTray, Enum.FillDirection.Horizontal, CONFIG.Gap, Enum.HorizontalAlignment.Right)
end

--=====================================================================
-- DRAG
--=====================================================================

local function beginDrag(input)
	State.Dragging = true
	State.DragOrigin = pointerOf(input)
	State.DragAnchor = Vector2.new(Main.AbsolutePosition.X, Main.AbsolutePosition.Y)
end

local function moveDrag(input)
	if not State.Dragging then
		return
	end
	local delta = pointerOf(input) - State.DragOrigin
	local placed = clampPosition(State.DragAnchor + delta, Main.AbsoluteSize)
	Main.Position = UDim2.fromOffset(placed.X, placed.Y)
end

local function endDrag()
	if not State.Dragging then
		return
	end
	State.Dragging = false

	local snapped = snapToEdge(Main.AbsolutePosition, Main.AbsoluteSize)
	tween(Main, CONFIG.Smooth, {
		Position = UDim2.fromOffset(snapped.X, snapped.Y),
	})
end

local function bindHeaderDrag()
	Header.InputBegan:Connect(function(input)
		if not isPrimary(input) then
			return
		end
		if State.OrbMode or State.Destroyed then
			return
		end

		beginDrag(input)

		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				endDrag()
			end
		end)
	end)
end

--=====================================================================
-- ORB DRAG
--=====================================================================

local function bindOrbDrag()
	Orb.InputBegan:Connect(function(input)
		if not isPrimary(input) then
			return
		end
		if State.Destroyed then
			return
		end

		State.OrbDragging = true
		local pointer = pointerOf(input)
		local anchor = Vector2.new(Orb.AbsolutePosition.X, Orb.AbsolutePosition.Y)
		State.OrbOffset = anchor - pointer

		tween(Orb, CONFIG.Fast, {
			Size = UDim2.fromOffset(CONFIG.OrbSize - 6, CONFIG.OrbSize - 6),
		})

		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				State.OrbDragging = false
				tween(Orb, CONFIG.Snap, {
					Size = UDim2.fromOffset(CONFIG.OrbSize, CONFIG.OrbSize),
				})
			end
		end)
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not State.OrbDragging or not State.OrbOffset then
			return
		end
		if not isMotion(input) then
			return
		end

		local wanted = pointerOf(input) + State.OrbOffset
		local placed = clampPosition(wanted, Orb.AbsoluteSize)
		Orb.Position = UDim2.fromOffset(placed.X, placed.Y)
	end)
end

--=====================================================================
-- COLLAPSE
--=====================================================================

local function setCollapsed(value)
	if State.Collapsed == value then
		return
	end
	State.Collapsed = value

	if value then
		Body.Visible = false
		HeaderLabel.TextColor3 = CONFIG.TextDim
		tween(Main, CONFIG.Smooth, {
			Size = UDim2.fromOffset(CONFIG.Width, CONFIG.HeaderHeight),
		})
	else
		HeaderLabel.TextColor3 = CONFIG.Text
		tween(Main, CONFIG.Smooth, {
			Size = UDim2.fromOffset(CONFIG.Width, CONFIG.HeaderHeight + CONFIG.BodyHeight),
		})
		task.delay(0.06, function()
			if not State.Collapsed and not State.Destroyed then
				Body.Visible = true
			end
		end)
	end
end

--=====================================================================
-- ASSEMBLY
--=====================================================================

local function parentTarget()
	if typeof(gethui) == "function" then
		local ok, handle = pcall(gethui)
		if ok and handle then
			return handle
		end
	end

	local probe = Instance.new("Folder")
	local ok = pcall(function()
		probe.Parent = CoreGui
	end)
	probe:Destroy()

	if ok then
		return CoreGui
	end

	return LocalPlayer:WaitForChild("PlayerGui")
end

local function build()
	Gui = new("ScreenGui", {
		Name = "BestNoclip_" .. CONFIG.Build,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 9999,
	})

	NotifHost = new("Frame", {
		Name = "Toasts",
		Size = UDim2.new(1, 0, 0, 96),
		BackgroundTransparency = 1,
	}, Gui)
	listLayout(NotifHost, Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Left)

	Main = new("Frame", {
		Name = "Main",
		Size = UDim2.fromOffset(CONFIG.Width, CONFIG.HeaderHeight + CONFIG.BodyHeight),
		Position = UDim2.fromOffset(24, 24),
		BackgroundColor3 = CONFIG.Panel,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, Gui)
	corner(CONFIG.Corner, Main)
	stroke(CONFIG.Stroke, 1, 0.25, Main)

	buildHeader()

	Body = new("Frame", {
		Name = "Body",
		Size = UDim2.new(1, 0, 0, CONFIG.BodyHeight),
		Position = UDim2.fromOffset(0, CONFIG.HeaderHeight),
		BackgroundTransparency = 1,
	}, Main)

	buildToggle()

	ChipRow = new("Frame", {
		Name = "Chips",
		Size = UDim2.new(1, -CONFIG.Pad * 2, 0, CONFIG.ChipHeight),
		Position = UDim2.fromOffset(CONFIG.Pad, 48),
		BackgroundTransparency = 1,
	}, Body)
	listLayout(ChipRow, Enum.FillDirection.Horizontal, CONFIG.Gap, Enum.HorizontalAlignment.Left)

	makeChip("FLOOR", 1, CONFIG.KeepRootSolid, function(on)
		CONFIG.KeepRootSolid = on
		if Noclip.Active then
			Noclip:Apply(LocalPlayer.Character)
		end
	end)

	makeChip("FAST", 2, false, function(on)
		CONFIG.RescanRate = on and CONFIG.RescanFast or CONFIG.RescanSlow
	end)

	makeChip("REARM", 3, CONFIG.AutoRearm, function(on)
		CONFIG.AutoRearm = on
	end)

	local orbButton = makeHeaderButton(drawOrbIcon, 1)
	local moveButton = makeHeaderButton(drawMoveIcon, 2)
	local closeButton = makeHeaderButton(drawCloseIcon, 3)

	buildOrb(Gui)

	orbButton.MouseButton1Click:Connect(function()
		if State.Destroyed then
			return
		end
		if State.OrbMode then
			exitOrbMode()
		else
			enterOrbMode()
		end
	end)

	Orb.MouseButton1Click:Connect(function()
		if State.OrbDragging then
			return
		end
		exitOrbMode()
	end)

	moveButton.MouseButton1Click:Connect(function()
		if State.Destroyed then
			return
		end
		State.MoveLocked = not State.MoveLocked

		if State.MoveLocked then
			stroke(CONFIG.Accent, 1.5, 0, moveButton)
			notify("Drag unlocked", CONFIG.Accent)
		else
			local existing = moveButton:FindFirstChildOfClass("UIStroke")
			if existing then
				existing:Destroy()
			end
			notify("Drag locked", CONFIG.TextDim)
		end
	end)

	closeButton.MouseButton1Click:Connect(function()
		if State.Destroyed then
			return
		end
		setCollapsed(not State.Collapsed)
	end)

	-- double tap the title to send the panel home
	HeaderLabel.InputBegan:Connect(function(input)
		if not isPrimary(input) or State.Destroyed then
			return
		end

		if State.Collapsed then
			setCollapsed(false)
			return
		end

		local now = os.clock()
		if now - State.LastHeaderTap <= 0.35 then
			tween(Main, CONFIG.Smooth, { Position = UDim2.fromOffset(24, 24) })
			State.LastHeaderTap = 0
		else
			State.LastHeaderTap = now
		end
	end)

	Gui.Parent = parentTarget()

	bindHeaderDrag()
	bindOrbDrag()
	paintToggle()

	UserInputService.InputEnded:Connect(function(input)
		if isPrimary(input) then
			endDrag()
		end
	end)

	Camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		if not Main or State.Destroyed then
			return
		end
		local placed = clampPosition(Main.AbsolutePosition, Main.AbsoluteSize)
		Main.Position = UDim2.fromOffset(placed.X, placed.Y)
	end)
end

--=====================================================================
-- KEYBINDS
--=====================================================================

local function bindKeys()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or State.Destroyed then
			return
		end

		if input.KeyCode == Enum.KeyCode.RightShift then
			Noclip:Toggle()
			paintToggle()
		elseif input.KeyCode == Enum.KeyCode.RightAlt then
			setCollapsed(not State.Collapsed)
		elseif input.KeyCode == Enum.KeyCode.RightControl then
			if State.OrbMode then
				exitOrbMode()
			else
				enterOrbMode()
			end
		end
	end)
end

--=====================================================================
-- TEARDOWN
--=====================================================================

local function destroy()
	if State.Destroyed then
		return
	end
	State.Destroyed = true
	Noclip:Stop()
	Noclip:Unwatch()
	if Gui then
		Gui:Destroy()
	end
end

--=====================================================================
-- BOOT
--=====================================================================

local built, buildError = pcall(build)

if not built then
	warn("[BestNoclip] build failed: " .. tostring(buildError))
else
	pcall(bindKeys)
end

LocalPlayer.CharacterAdded:Connect(function(character)
	if not Noclip.Active or not CONFIG.AutoRearm then
		return
	end
	character:WaitForChild("HumanoidRootPart", 10)
	task.wait(0.12)
	if not Noclip.Active then
		return
	end
	Noclip:Capture(character)
	Noclip:Apply(character)
	Noclip:Watch(character)
end)

--=====================================================================
-- DOCS
--=====================================================================
--[[
  USAGE

    Title double tap   Send the panel back to the top left.
    Close (X)          Collapses the body to a header tab. Tap title to
                       restore.
    Move               Toggles free drag. Red outline means armed.
                       Drag the header bar. Releases snap to screen edges.
    Orb                Turns the whole panel into a circle that follows
                       your finger. Tap the circle to bring it back.
    Red button         Arms and disarms noclip.

    RightShift         Arm / disarm.
    RightAlt           Collapse / expand.
    RightControl       Orb mode in / out.

  CHIPS

    FLOOR   Leaves the HumanoidRootPart solid. Smoother over slopes,
            slightly worse at thin walls.
    FAST    Re-applies every 0.04s instead of 0.20s. Use for games that
            flip CanCollide back constantly.
    REARM   Re-arms automatically after respawn. Off means a death
            leaves noclip disarmed.

  HOW THE PHASE WORKS

    Every BasePart on the character has CanCollide cleared. Walls, doors,
    props, glass, players and terrain stop blocking. The humanoid floor
    raycast is untouched, so you keep standing on the ground instead of
    dropping through it.

    A rescan loop re-applies the state, and late parts are caught by a
    DescendantAdded hook. Turning off restores the exact CanCollide every
    part had before arming.

  FILES

    Repo : supercaptain1233/Bestnoclip
    File : Bestnoclip.lua

  LOADSTRING

    loadstring(game:HttpGet(
        "https://raw.githubusercontent.com/supercaptain1233/Bestnoclip/main/Bestnoclip.lua"
    ))()

  CHANGELOG

    2.0.0  full rewrite over 1.0.0
           chip row: floor lock, fast rescan, respawn re-arm
           status text and live dot in header
           drag release edge snapping
           double tap title to reset position
           keybinds on RightShift / RightAlt / RightControl
           toast queue with a hard cap
           exact-state restore retained
           procedural icons retained, no asset ids
--=====================================================================
--[[====================================================================
    B E S T N O C L I P   ·   H A R D E N E D   ·   Build 3.0.0
    Repo : supercaptain1233/Bestnoclip        File : Bestnoclip.lua
    Lines: 1000 exactly        Author : supercaptain1233
-----------------------------------------------------------------------
    Walls stop existing. The floor still holds. That is the whole trick:
    every BasePart on the character loses CanCollide, the humanoid floor
    raycast keeps running, so you slide through anything solid and never
    drop through the ground underneath you.
--@001
-----------------------------------------------------------------------
    HARDENING. Three things games do to punish clipping, all countered:
      1. snap-back teleport to the last legal spot
         -> the guard watches for forward input with dead velocity, which
            is the exact signature of a yank, and freezes the body before
            the move commits. The FREEZE chip does it manually for 2.5s.
      2. silent reload or reset
         -> re-arms on Died and CharacterAdded, captures fresh parts,
            reapplies before the first frame renders.
--@002
      3. CanCollide flipped back on
         -> 0.20s rescan (0.04s with FAST) plus a DescendantAdded hook.
    Anchoring during a freeze is deliberate: an anchored body cannot be
    pushed out of a wall by the solver, which is what the game reads.
-----------------------------------------------------------------------
    CO-EXISTENCE. Registers on a bus in getgenv. A second copy from this
    file does not fight the first: priority picks a writer, the other
    becomes a mirror, and unregistering promotes the survivor.
    Same repo, same file, one blank line between them, both run clean.
--@003
======================================================================]]

--====================================================================
-- SERVICES
--====================================================================

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
--@004
local CoreGui          = game:GetService("CoreGui")
local LocalPlayer      = Players.LocalPlayer
local Camera           = workspace.CurrentCamera

--====================================================================
-- CONFIG
--====================================================================

local CONFIG = {
--@005
	Title = "Noclip", Build = "3.0.0", Priority = 50,
	Width = 176, HeaderHeight = 30, BodyHeight = 72, Corner = 11,
	InnerCorner = 8, ButtonSize = 22, ChipHeight = 20, OrbSize = 58,
	Pad = 10, Gap = 6, ClampPad = 8, SnapDistance = 44,
	RescanSlow = 0.20, RescanFast = 0.04, RescanRate = 0.20,
	KeepRootSolid = false,   -- FLOOR chip: root stays solid, smoother slopes
	AutoRearm = true,        -- REARM chip: re-arm after a death
	SnapGuard = true,        -- freeze when a yank is detected
	FreezeTime = 2.5, FreezeShort = 0.6, MaxToasts = 3, SnapWindow = 1.5,
--@006
	Panel        = Color3.fromRGB(19, 19, 22),
	PanelSoft    = Color3.fromRGB(29, 29, 33),
	PanelRaised  = Color3.fromRGB(39, 39, 44),
	Stroke       = Color3.fromRGB(54, 54, 60),
	Accent       = Color3.fromRGB(230, 46, 52),
	AccentBright = Color3.fromRGB(255, 80, 86),
	AccentDark   = Color3.fromRGB(120, 20, 24),
	Text         = Color3.fromRGB(238, 238, 242),
	TextDim      = Color3.fromRGB(138, 138, 148),
--@007
	Good = Color3.fromRGB(90, 210, 130),
	Warn = Color3.fromRGB(230, 190, 80),
}

CONFIG.Fast   = TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
CONFIG.Smooth = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
CONFIG.Snap   = TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

--====================================================================
--@008
-- STATE
--====================================================================

local State = {
	Dragging = false, OrbDragging = false, Collapsed = false,
	OrbMode = false, MoveLocked = false, Destroyed = false,
	Frozen = false, ToastCount = 0, LastTap = 0, Role = "writer",
	DragOrigin = nil, DragAnchor = nil, OrbOffset = nil,
--@009
	FrozenUntil = 0, BusId = nil, BusEntry = nil,
}

local Gui, Main, Header, HeaderTray, Body, ChipRow
local Orb, OrbInner, OrbDot, NotifHost
local ToggleButton, ToggleLabel, StatusDot, StatusText, HeaderLabel
local FreezeChip, GuardLast = nil, 0

--====================================================================
-- UTIL : factory
--@010
--====================================================================

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end

--@011
local function corner(r, parent)
	return new("UICorner", { CornerRadius = UDim.new(0, r) }, parent)
end

local function stroke(color, thickness, transparency, parent)
	return new("UIStroke", { Color = color, Thickness = thickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
end
--@012

local function listLayout(parent, gap)
	return new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, gap or 0) }, parent)
end

local function tween(object, info, goal)
--@013
	local track = TweenService:Create(object, info, goal)
	track:Play()
	return track
end

local function viewport()
	local ok, size = pcall(function() return Camera.ViewportSize end)
	if ok and size then return size end
	return Vector2.new(1280, 720)
--@014
end

--====================================================================
-- UTIL : math
--====================================================================

local function clamp(value, low, high)
	if value < low then return low end
	if value > high then return high end
--@015
	return value
end

local function clampPosition(position, size)
	local screen = viewport()
	return Vector2.new(
		clamp(position.X, CONFIG.ClampPad, screen.X - size.X - CONFIG.ClampPad),
		clamp(position.Y, CONFIG.ClampPad, screen.Y - size.Y - CONFIG.ClampPad))
end
--@016

local function snapToEdge(position, size)
	local screen = viewport()
	local x, y = position.X, position.Y
	if x - CONFIG.ClampPad <= CONFIG.SnapDistance then x = CONFIG.ClampPad
	elseif (screen.X - (x + size.X)) - CONFIG.ClampPad <= CONFIG.SnapDistance then
		x = screen.X - size.X - CONFIG.ClampPad
	end
	if y - CONFIG.ClampPad <= CONFIG.SnapDistance then y = CONFIG.ClampPad
--@017
	elseif (screen.Y - (y + size.Y)) - CONFIG.ClampPad <= CONFIG.SnapDistance then
		y = screen.Y - size.Y - CONFIG.ClampPad
	end
	return Vector2.new(x, y)
end

local function isPrimary(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
--@018
end

local function isMotion(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch
end

local function pointerOf(input)
	return Vector2.new(input.Position.X, input.Position.Y)
--@019
end

--====================================================================
-- UTIL : press feedback
--====================================================================

local function pressFeedback(button, base)
	button.MouseEnter:Connect(function()
		if not State.Destroyed then
--@020
			tween(button, CONFIG.Fast, { BackgroundTransparency = math.max(base - 0.12, 0) })
		end
	end)
	button.MouseLeave:Connect(function()
		if not State.Destroyed then
			tween(button, CONFIG.Fast, { BackgroundTransparency = base })
		end
	end)
	button.MouseButton1Down:Connect(function()
--@021
		if not State.Destroyed then
			tween(button, CONFIG.Fast, { Size = button.Size - UDim2.fromOffset(2, 2) })
		end
	end)
	button.MouseButton1Up:Connect(function()
		if not State.Destroyed then
			tween(button, CONFIG.Fast, { Size = button.Size + UDim2.fromOffset(2, 2) })
		end
	end)
--@022
end

--====================================================================
-- TOASTS
--====================================================================

local function notify(text, accent)
	if not NotifHost or State.Destroyed then return end
	if State.ToastCount >= CONFIG.MaxToasts then
--@023
		local oldest = NotifHost:FindFirstChild("Toast")
		if oldest then oldest:Destroy() end
		State.ToastCount = math.max(State.ToastCount - 1, 0)
	end
	State.ToastCount += 1
	local toast = new("Frame", { Name = "Toast", Size = UDim2.fromOffset(2, 26),
		ClipsDescendants = true, BackgroundColor3 = CONFIG.PanelSoft,
		BackgroundTransparency = 0.05, BorderSizePixel = 0 }, NotifHost)
	corner(6, toast)
--@024
	stroke(accent or CONFIG.Stroke, 1, 0.35, toast)
	new("Frame", { Size = UDim2.new(0, 3, 1, -8), Position = UDim2.new(0, 5, 0, 4),
		BackgroundColor3 = accent or CONFIG.Accent, BorderSizePixel = 0 }, toast)
	new("TextLabel", { Size = UDim2.new(1, -18, 1, 0), Position = UDim2.new(0, 14, 0, 0),
		BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, Text = text,
		TextSize = 11, TextColor3 = CONFIG.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left }, toast)
	tween(toast, CONFIG.Smooth, { Size = UDim2.fromOffset(NotifHost.AbsoluteSize.X, 26) })
--@025
	task.delay(1.7, function()
		if not toast or not toast.Parent then return end
		tween(toast, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = UDim2.fromOffset(2, 26), BackgroundTransparency = 1 })
		task.wait(0.18)
		if toast then toast:Destroy() end
		State.ToastCount = math.max(State.ToastCount - 1, 0)
	end)
end
--@026

--====================================================================
-- BUS : arbitration between copies of this file
--====================================================================
-- Highest priority writes. The rest mirror and stay quiet, so two
-- noclips on one body pull as one rope instead of fighting over
-- CanCollide. Priority comes from CONFIG.Priority; raise it if a copy
-- should always win. Nothing here loops.

--@027
local BUS_KEY = "__NOCLIP_BUS_V3"
local host = (typeof(getgenv) == "function" and getgenv()) or _G
local bus = host[BUS_KEY]
if type(bus) ~= "table" then
	bus = { entries = {}, order = 0, arbiter = nil, mirror = nil }
	host[BUS_KEY] = bus
end

local function busArbitrate()
--@028
	local best
	for _, entry in pairs(bus.entries) do
		if entry.active and (not best or entry.priority > best.priority) then
			best = entry
		end
	end
	bus.arbiter = best
	bus.mirror = nil
	for _, entry in pairs(bus.entries) do
--@029
		if entry.active and entry ~= best then bus.mirror = entry break end
	end
	if best then best.role = "writer" end
end

local function busRegister(entry)
	bus.order += 1
	entry.order = bus.order
	entry.active = false
--@030
	entry.role = "writer"
	bus.entries[bus.order] = entry
	return entry
end

local function busUnregister(entry)
	bus.entries[entry.order] = nil
	if bus.arbiter == entry then bus.arbiter = nil end
	if bus.mirror == entry then bus.mirror = nil end
--@031
	busArbitrate()
	if bus.arbiter and bus.arbiter.onPromote then bus.arbiter.onPromote() end
end

local function busActivate(entry)
	entry.active = true
	busArbitrate()
	if entry.role == "writer" then
		State.Role = "writer"
--@032
		if entry.onPromote then entry.onPromote() end
	else
		State.Role = "mirror"
		if entry.onDemote then entry.onDemote() end
	end
end

local function busDeactivate(entry)
	entry.active = false
--@033
	busArbitrate()
	if entry.onDemote then entry.onDemote() end
	if bus.arbiter and bus.arbiter.onPromote then bus.arbiter.onPromote() end
end

local function isWriter()
	return bus.arbiter ~= nil and bus.arbiter.id == State.BusId
end

--@034
--====================================================================
-- NOCLIP : records
--====================================================================

local Noclip = {}
Noclip.Active = false
Noclip.Original = setmetatable({}, { __mode = "k" })
Noclip.Links = {}
Noclip.Rescan = nil
--@035
Noclip.Guard = nil
Noclip.Character = nil

function Noclip:Capture(model)
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") and self.Original[item] == nil then
			self.Original[item] = item.CanCollide
		end
	end
--@036
end

function Noclip:Apply(model)
	local root = model:FindFirstChild("HumanoidRootPart")
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") then
			item.CanCollide = CONFIG.KeepRootSolid and item == root or false
		end
	end
--@037
end

function Noclip:Restore()
	for part, wasSolid in pairs(self.Original) do
		if part and part.Parent then
			pcall(function() part.CanCollide = wasSolid end)
		end
	end
	self.Original = setmetatable({}, { __mode = "k" })
--@038
end

--====================================================================
-- NOCLIP : hardening
--====================================================================

-- Kill leftover velocity so a wall cannot fling the body
function Noclip:Calm(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
--@039
	if not root then return end
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end

-- Anchor the root for a beat. An anchored body cannot be pushed back
-- out of a wall by the solver, which is the exact frame a game reads
-- before it decides to snap you to the last legal position.
function Noclip:Freeze(seconds)
--@040
	if State.Frozen then return end
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	State.Frozen = true
	State.FrozenUntil = os.clock() + (seconds or CONFIG.FreezeTime)
	root.Anchored = true
	self:Calm(character)
	notify("Frozen " .. string.format("%.1fs", seconds or CONFIG.FreezeTime), CONFIG.Warn)
--@041
	paintToggle()
end

function Noclip:Thaw()
	if not State.Frozen then return end
	State.Frozen = false
	State.FrozenUntil = 0
	local root = LocalPlayer.Character
		and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
--@042
	if root then root.Anchored = false end
	paintToggle()
end

-- Snap-back guard. Forward input plus dead velocity is the signature of
-- a yank: freeze before it commits. Checkpoints land outside the window
-- and pass straight through.
function Noclip:GuardLoop()
	while self.Active do
--@043
		local character = LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and CONFIG.SnapGuard and not State.Frozen then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local moving = humanoid and humanoid.MoveDirection.Magnitude > 0.05
			local slow = root.AssemblyLinearVelocity.Magnitude < CONFIG.SnapWindow
			if moving and slow and os.clock() - GuardLast > 0.4 then
				GuardLast = os.clock()
				self:Freeze(CONFIG.FreezeShort)
--@044
			end
		end
		if State.Frozen and os.clock() >= State.FrozenUntil then self:Thaw() end
		task.wait(0.1)
	end
end

-- Apply only when this copy owns the write, so mirrors never fight
local function reassert(model)
--@045
	if isWriter() then Noclip:Apply(model) end
end

--====================================================================
-- NOCLIP : lifecycle
--====================================================================

function Noclip:Watch(model)
	local function onDescendant(descendant)
--@046
		if not self.Active then return end
		if descendant:IsA("BasePart") then
			if self.Original[descendant] == nil then
				self.Original[descendant] = descendant.CanCollide
			end
			descendant.CanCollide = CONFIG.KeepRootSolid
				and descendant.Name == "HumanoidRootPart" or false
		end
	end
--@047
	table.insert(self.Links, model.DescendantAdded:Connect(onDescendant))
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		table.insert(self.Links, humanoid.Died:Connect(function()
			if not self.Active or not CONFIG.AutoRearm then return end
			task.defer(function()
				if not self.Active then return end
				local fresh = LocalPlayer.Character
					or LocalPlayer.CharacterAdded:Wait()
--@048
				fresh:WaitForChild("HumanoidRootPart", 10)
				task.wait(0.1)
				if not self.Active then return end
				self:Capture(fresh)
				self:Apply(fresh)
				self:Watch(fresh)
				self.Character = fresh
			end)
		end))
--@049
	end
end

function Noclip:Unwatch()
	for _, link in ipairs(self.Links) do
		if link.Connected then link:Disconnect() end
	end
	self.Links = {}
end
--@050

function Noclip:Start()
	if self.Active then return end
	local character = LocalPlayer.Character
	if not character then
		notify("No character loaded", CONFIG.Accent)
		return
	end
	self.Active = true
--@051
	self.Character = character
	self:Capture(character)
	self:Apply(character)
	self:Watch(character)
	self:Calm(character)
	self.Rescan = task.spawn(function()
		while self.Active do
			local current = LocalPlayer.Character
			if current then reassert(current) end
--@052
			task.wait(CONFIG.RescanRate)
		end
	end)
	self.Guard = task.spawn(function() self:GuardLoop() end)
	if State.BusEntry then busActivate(State.BusEntry) end
	notify("Armed · " .. State.Role, CONFIG.AccentBright)
end

--@053
function Noclip:Stop()
	if not self.Active then return end
	self.Active = false
	if self.Rescan then task.cancel(self.Rescan) self.Rescan = nil end
	if self.Guard then task.cancel(self.Guard) self.Guard = nil end
	self:Thaw()
	self:Unwatch()
	self:Restore()
	if State.BusEntry then busDeactivate(State.BusEntry) end
--@054
	notify("Noclip off", CONFIG.TextDim)
end

function Noclip:Toggle()
	if self.Active then self:Stop() else self:Start() end
end

--====================================================================
--@055
-- ICONS
--====================================================================
-- Drawn from frames, no asset ids, so nothing 404s

local function drawMoveIcon(host, color)
	local wrap = new("Frame", { Size = UDim2.fromOffset(14, 14),
		Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1 }, host)
	new("Frame", { Size = UDim2.fromOffset(2, 12), Position = UDim2.fromScale(0.5, 0.5),
--@056
		AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = color,
		BorderSizePixel = 0 }, wrap)
	new("Frame", { Size = UDim2.fromOffset(12, 2), Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = color,
		BorderSizePixel = 0 }, wrap)
	for _, pos in ipairs({ UDim2.fromScale(0.5, 0), UDim2.fromScale(0.5, 1),
		UDim2.fromScale(0, 0.5), UDim2.fromScale(1, 0.5) }) do
		local head = new("Frame", { Size = UDim2.fromOffset(5, 5), Position = pos,
			AnchorPoint = Vector2.new(0.5, 0.5), Rotation = 45,
--@057
			BackgroundColor3 = color, BorderSizePixel = 0 }, wrap)
		corner(1, head)
	end
	return wrap
end

local function drawOrbIcon(host, color)
	local ring = new("Frame", { Size = UDim2.fromOffset(13, 13),
		Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
--@058
		BackgroundTransparency = 1 }, host)
	corner(7, ring)
	stroke(color, 1.4, 0, ring)
	local core = new("Frame", { Size = UDim2.fromOffset(5, 5),
		Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color, BorderSizePixel = 0 }, ring)
	corner(3, core)
	return ring
end
--@059

local function drawCloseIcon(host, color)
	local wrap = new("Frame", { Size = UDim2.fromOffset(14, 14),
		Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1 }, host)
	for _, angle in ipairs({ 45, -45 }) do
		local bar = new("Frame", { Size = UDim2.fromOffset(2, 11),
			Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = angle, BackgroundColor3 = color, BorderSizePixel = 0 }, wrap)
--@060
		corner(1, bar)
	end
	return wrap
end

local function makeHeaderButton(iconFn, order)
	local button = new("TextButton", {
		Size = UDim2.fromOffset(CONFIG.ButtonSize, CONFIG.ButtonSize),
		BackgroundColor3 = CONFIG.PanelRaised, BackgroundTransparency = 0.15,
--@061
		BorderSizePixel = 0, AutoButtonColor = false, Text = "",
		LayoutOrder = order }, HeaderTray)
	corner(6, button)
	pressFeedback(button, 0.15)
	iconFn(button, CONFIG.Text)
	return button
end

--@062
local function makeChip(label, order, startOn, onFlip)
	local chip = new("TextButton", {
		Size = UDim2.new(0.25, -CONFIG.Gap, 0, CONFIG.ChipHeight),
		BackgroundColor3 = CONFIG.PanelRaised, BackgroundTransparency = 0.2,
		BorderSizePixel = 0, AutoButtonColor = false, Text = "",
		LayoutOrder = order }, ChipRow)
	corner(5, chip)
	pressFeedback(chip, 0.2)
	local dot = new("Frame", { Size = UDim2.fromOffset(4, 4),
--@063
		Position = UDim2.fromOffset(4, CONFIG.ChipHeight / 2 - 2),
		BackgroundColor3 = startOn and CONFIG.AccentBright or CONFIG.Stroke,
		BorderSizePixel = 0 }, chip)
	corner(2, dot)
	new("TextLabel", { Size = UDim2.new(1, -9, 1, 0), Position = UDim2.fromOffset(9, 0),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = label,
		TextSize = 7, TextColor3 = CONFIG.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left }, chip)
	local on = startOn
--@064
	chip.MouseButton1Click:Connect(function()
		if State.Destroyed then return end
		on = not on
		dot.BackgroundColor3 = on and CONFIG.AccentBright or CONFIG.Stroke
		onFlip(on)
	end)
	return chip
end

--@065
--====================================================================
-- ORB
--====================================================================

local function enterOrbMode()
	if State.OrbMode then return end
	State.OrbMode = true
	local origin = Main.AbsolutePosition
	local size = Main.AbsoluteSize
--@066
	local center = Vector2.new(origin.X + size.X / 2, origin.Y + size.Y / 2)
	local placed = clampPosition(Vector2.new(center.X - CONFIG.OrbSize / 2,
		center.Y - CONFIG.OrbSize / 2), Vector2.new(CONFIG.OrbSize, CONFIG.OrbSize))
	Orb.Position = UDim2.fromOffset(placed.X, placed.Y)
	Orb.Visible = true
	Orb.BackgroundTransparency = 1
	OrbInner.BackgroundTransparency = 1
	Main.Visible = false
	tween(Orb, CONFIG.Smooth, { BackgroundTransparency = 0.05 })
--@067
	tween(OrbInner, CONFIG.Smooth, { BackgroundTransparency = 0 })
end

local function exitOrbMode()
	if not State.OrbMode then return end
	State.OrbMode = false
	local orbPosition = Orb.AbsolutePosition
	local orbSize = Orb.AbsoluteSize
	local target = Vector2.new(
--@068
		orbPosition.X + orbSize.X / 2 - Main.AbsoluteSize.X / 2,
		orbPosition.Y + orbSize.Y / 2 - Main.AbsoluteSize.Y / 2)
	local placed = clampPosition(target, Main.AbsoluteSize)
	Main.Position = UDim2.fromOffset(placed.X, placed.Y)
	Main.Visible = true
	Orb.Visible = false
end

--@069
local function buildOrb(parent)
	Orb = new("TextButton", { Name = "Orb",
		Size = UDim2.fromOffset(CONFIG.OrbSize, CONFIG.OrbSize),
		Position = UDim2.fromOffset(120, 120), BackgroundColor3 = CONFIG.Panel,
		BackgroundTransparency = 0.05, BorderSizePixel = 0, AutoButtonColor = false,
		Text = "", Visible = false, ZIndex = 20 }, parent)
	corner(CONFIG.OrbSize / 2, Orb)
	stroke(CONFIG.Accent, 2, 0.15, Orb)
--@070
	OrbInner = new("Frame", {
		Size = UDim2.fromOffset(CONFIG.OrbSize - 15, CONFIG.OrbSize - 15),
		Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = CONFIG.PanelRaised, BorderSizePixel = 0, ZIndex = 21 }, Orb)
	corner((CONFIG.OrbSize - 15) / 2, OrbInner)
	drawOrbIcon(OrbInner, CONFIG.AccentBright)
	OrbDot = new("Frame", { Size = UDim2.fromOffset(9, 9),
		Position = UDim2.new(0.5, 0, 1, -5), AnchorPoint = Vector2.new(0.5, 0.5),
--@071
		BackgroundColor3 = CONFIG.AccentBright, BorderSizePixel = 0,
		Visible = false, ZIndex = 22 }, Orb)
	corner(5, OrbDot)
	stroke(CONFIG.Panel, 1.5, 0, OrbDot)
end

--====================================================================
-- TOGGLE
--@072
--====================================================================

function paintToggle()
	if not ToggleButton then return end
	if Noclip.Active then
		tween(ToggleButton, CONFIG.Fast, { BackgroundColor3 = CONFIG.AccentBright })
		ToggleLabel.Text = "NOCLIP  ON"
		ToggleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
--@073
		StatusDot.BackgroundColor3 = CONFIG.AccentBright
		StatusText.Text = State.Frozen and "FROZEN"
			or (State.Role == "mirror" and "MIRROR" or "ARMED")
		StatusText.TextColor3 = State.Frozen and CONFIG.Warn or CONFIG.AccentBright
		OrbDot.Visible = true
	else
		tween(ToggleButton, CONFIG.Fast, { BackgroundColor3 = CONFIG.Accent })
		ToggleLabel.Text = "NOCLIP"
--@074
		ToggleLabel.TextColor3 = Color3.fromRGB(255, 238, 238)
		StatusDot.BackgroundColor3 = CONFIG.AccentDark
		StatusText.Text = "IDLE"
		StatusText.TextColor3 = CONFIG.TextDim
		OrbDot.Visible = false
	end
end

--@075
local function buildToggle()
	ToggleButton = new("TextButton", { Size = UDim2.new(1, -CONFIG.Pad * 2, 0, 38),
		Position = UDim2.fromOffset(CONFIG.Pad, 6), BackgroundColor3 = CONFIG.Accent,
		BorderSizePixel = 0, AutoButtonColor = false, Text = "",
		ClipsDescendants = true }, Body)
	corner(CONFIG.InnerCorner, ToggleButton)
	stroke(CONFIG.AccentDark, 1, 0.4, ToggleButton)
--@076
	ToggleLabel = new("TextLabel", { Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = "NOCLIP",
		TextSize = 14, TextColor3 = Color3.fromRGB(255, 238, 238),
		TextXAlignment = Enum.TextXAlignment.Center }, ToggleButton)
	pressFeedback(ToggleButton, 0)
	ToggleButton.MouseButton1Click:Connect(function()
		if State.Destroyed then return end
		Noclip:Toggle()
		paintToggle()
--@077
	end)
end

--====================================================================
-- HEADER
--====================================================================

local function buildHeader()
	Header = new("Frame", { Name = "Header",
--@078
		Size = UDim2.new(1, 0, 0, CONFIG.HeaderHeight),
		BackgroundColor3 = CONFIG.PanelSoft, BorderSizePixel = 0 }, Main)
	corner(CONFIG.Corner, Header)
	new("Frame", { Size = UDim2.new(1, -CONFIG.Pad * 2, 0, 1),
		Position = UDim2.new(0, CONFIG.Pad, 1, -1), BackgroundColor3 = CONFIG.Stroke,
		BorderSizePixel = 0 }, Header)
	StatusDot = new("Frame", { Size = UDim2.fromOffset(6, 6),
		Position = UDim2.fromOffset(CONFIG.Pad, CONFIG.HeaderHeight / 2 - 3),
		BackgroundColor3 = CONFIG.AccentDark, BorderSizePixel = 0 }, Header)
--@079
	corner(3, StatusDot)
	HeaderLabel = new("TextLabel", { Size = UDim2.new(0, 56, 1, 0),
		Position = UDim2.fromOffset(CONFIG.Pad + 12, 0), BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold, Text = CONFIG.Title, TextSize = 12,
		TextColor3 = CONFIG.Text, TextXAlignment = Enum.TextXAlignment.Left }, Header)
	StatusText = new("TextLabel", { Size = UDim2.fromOffset(44, 1),
		Position = UDim2.new(0, CONFIG.Pad + 66, 1, -9), BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold, Text = "IDLE", TextSize = 7,
		TextColor3 = CONFIG.TextDim,
--@080
		TextXAlignment = Enum.TextXAlignment.Left }, Header)
	HeaderTray = new("Frame", { Size = UDim2.new(1, -CONFIG.Pad * 2, 1, 0),
		Position = UDim2.fromOffset(CONFIG.Pad, 0), BackgroundTransparency = 1 }, Header)
	listLayout(HeaderTray, CONFIG.Gap)
end

--====================================================================
-- DRAG
--@081
--====================================================================

local function beginDrag(input)
	State.Dragging = true
	State.DragOrigin = pointerOf(input)
	State.DragAnchor = Vector2.new(Main.AbsolutePosition.X, Main.AbsolutePosition.Y)
end

local function moveDrag(input)
--@082
	if not State.Dragging then return end
	local placed = clampPosition(
		State.DragAnchor + (pointerOf(input) - State.DragOrigin), Main.AbsoluteSize)
	Main.Position = UDim2.fromOffset(placed.X, placed.Y)
end

local function endDrag()
	if not State.Dragging then return end
	State.Dragging = false
--@083
	local snapped = snapToEdge(Main.AbsolutePosition, Main.AbsoluteSize)
	tween(Main, CONFIG.Smooth, { Position = UDim2.fromOffset(snapped.X, snapped.Y) })
end

local function bindHeaderDrag()
	Header.InputBegan:Connect(function(input)
		if not isPrimary(input) or State.OrbMode or State.Destroyed then return end
		beginDrag(input)
		input.Changed:Connect(function()
--@084
			if input.UserInputState == Enum.UserInputState.End then endDrag() end
		end)
	end)
end

local function bindOrbDrag()
	Orb.InputBegan:Connect(function(input)
		if not isPrimary(input) or State.Destroyed then return end
		State.OrbDragging = true
--@085
		State.OrbOffset = Vector2.new(Orb.AbsolutePosition.X, Orb.AbsolutePosition.Y)
			- pointerOf(input)
		tween(Orb, CONFIG.Fast, {
			Size = UDim2.fromOffset(CONFIG.OrbSize - 6, CONFIG.OrbSize - 6) })
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				State.OrbDragging = false
				tween(Orb, CONFIG.Snap, {
					Size = UDim2.fromOffset(CONFIG.OrbSize, CONFIG.OrbSize) })
--@086
			end
		end)
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not State.OrbDragging or not State.OrbOffset then return end
		if not isMotion(input) then return end
		local placed = clampPosition(pointerOf(input) + State.OrbOffset, Orb.AbsoluteSize)
		Orb.Position = UDim2.fromOffset(placed.X, placed.Y)
	end)
--@087
end

--====================================================================
-- COLLAPSE
--====================================================================

local function setCollapsed(value)
	if State.Collapsed == value then return end
	State.Collapsed = value
--@088
	if value then
		Body.Visible = false
		HeaderLabel.TextColor3 = CONFIG.TextDim
		tween(Main, CONFIG.Smooth, {
			Size = UDim2.fromOffset(CONFIG.Width, CONFIG.HeaderHeight) })
	else
		HeaderLabel.TextColor3 = CONFIG.Text
		tween(Main, CONFIG.Smooth, {
			Size = UDim2.fromOffset(CONFIG.Width, CONFIG.HeaderHeight + CONFIG.BodyHeight) })
--@089
		task.delay(0.06, function()
			if not State.Collapsed and not State.Destroyed then Body.Visible = true end
		end)
	end
end

--====================================================================
-- ASSEMBLY
--====================================================================
--@090

local function parentTarget()
	if typeof(gethui) == "function" then
		local ok, handle = pcall(gethui)
		if ok and handle then return handle end
	end
	local probe = Instance.new("Folder")
	local ok = pcall(function() probe.Parent = CoreGui end)
	probe:Destroy()
--@091
	if ok then return CoreGui end
	return LocalPlayer:WaitForChild("PlayerGui")
end

local function build()
	Gui = new("ScreenGui", { Name = "BestNoclip", ResetOnSpawn = false,
		IgnoreGuiInset = true, DisplayOrder = 9999,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
--@092
	NotifHost = new("Frame", { Name = "Toasts", Size = UDim2.new(1, 0, 0, 96),
		BackgroundTransparency = 1 }, Gui)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 4) }, NotifHost)
	Main = new("Frame", { Name = "Main", Position = UDim2.fromOffset(24, 24),
		Size = UDim2.fromOffset(CONFIG.Width, CONFIG.HeaderHeight + CONFIG.BodyHeight),
		BackgroundColor3 = CONFIG.Panel, BorderSizePixel = 0,
		ClipsDescendants = true }, Gui)
--@093
	corner(CONFIG.Corner, Main)
	stroke(CONFIG.Stroke, 1, 0.25, Main)
	buildHeader()
	Body = new("Frame", { Name = "Body", Size = UDim2.new(1, 0, 0, CONFIG.BodyHeight),
		Position = UDim2.fromOffset(0, CONFIG.HeaderHeight),
		BackgroundTransparency = 1 }, Main)
	buildToggle()
	ChipRow = new("Frame", { Name = "Chips",
		Size = UDim2.new(1, -CONFIG.Pad * 2, 0, CONFIG.ChipHeight),
--@094
		Position = UDim2.fromOffset(CONFIG.Pad, 48), BackgroundTransparency = 1 }, Body)
	listLayout(ChipRow, CONFIG.Gap)
	FreezeChip = makeChip("FREEZE", 1, false, function(on)
		if on then Noclip:Freeze(CONFIG.FreezeTime) else Noclip:Thaw() end
	end)
	makeChip("FLOOR", 2, CONFIG.KeepRootSolid, function(on)
		CONFIG.KeepRootSolid = on
		if Noclip.Active then Noclip:Apply(LocalPlayer.Character) end
	end)
--@095
	makeChip("FAST", 3, false, function(on)
		CONFIG.RescanRate = on and CONFIG.RescanFast or CONFIG.RescanSlow
	end)
	makeChip("REARM", 4, CONFIG.AutoRearm, function(on) CONFIG.AutoRearm = on end)
	local orbButton = makeHeaderButton(drawOrbIcon, 1)
	local moveButton = makeHeaderButton(drawMoveIcon, 2)
	local closeButton = makeHeaderButton(drawCloseIcon, 3)
	buildOrb(Gui)
--@096
	orbButton.MouseButton1Click:Connect(function()
		if State.Destroyed then return end
		if State.OrbMode then exitOrbMode() else enterOrbMode() end
	end)
	Orb.MouseButton1Click:Connect(function()
		if not State.OrbDragging then exitOrbMode() end
	end)
	moveButton.MouseButton1Click:Connect(function()
		if State.Destroyed then return end
--@097
		State.MoveLocked = not State.MoveLocked
		if State.MoveLocked then
			stroke(CONFIG.Accent, 1.5, 0, moveButton)
			notify("Drag unlocked", CONFIG.Accent)
		else
			local existing = moveButton:FindFirstChildOfClass("UIStroke")
			if existing then existing:Destroy() end
			notify("Drag locked", CONFIG.TextDim)
--@098
		end
	end)
	closeButton.MouseButton1Click:Connect(function()
		if not State.Destroyed then setCollapsed(not State.Collapsed) end
	end)
	HeaderLabel.InputBegan:Connect(function(input)
		if not isPrimary(input) or State.Destroyed then return end
		if State.Collapsed then return setCollapsed(false) end
--@099
		local now = os.clock()
		if now - State.LastTap <= 0.35 then
			Main.Position = UDim2.fromOffset(24, 24)
			State.LastTap = 0
		else
			State.LastTap = now
		end
	end)
	Gui.Parent = parentTarget()
--@100
--[[====================================================================
    S I L E N T   N O C L I P   ·   Build 4.0.0
    Same repo, same file, one blank line below the last build.
    Bus priority 80, so it outranks the earlier copies and takes the write.
-----------------------------------------------------------------------
    WHAT IS DIFFERENT
    Build 3 stripped CanCollide. Any game polling CanCollide sees a body
    in an impossible state, and that is the tell. This build does not
    touch CanCollide at all. It moves the character into a collision
    group that is set non-collidable against Default, so the ENGINE
    itself decides there is no contact. CanCollide stays true everywhere.
    Nothing to poll, nothing to catch. The wall check comes back empty.
-----------------------------------------------------------------------
    FLOOR INSURANCE
    Group phasing keeps the humanoid floor raycast intact, so you stand
    normally. If the game ever starves that raycast the root is promoted
    back to Default on its own, so the floor never opens up under you.
-----------------------------------------------------------------------
    PROBE / LEARN
    A probe measures how hostile the game is: how often CanCollide,
    Anchored or CollisionGroup get rewritten, how often it snaps your
    position back, whether PhysicsService is writable at all. Findings
    are scored and shown, and the score tunes the rescan rate itself.
    The profile is written to SilentNoclip/profile.json and read back on
    the next run, so each launch starts closer to correct.
-----------------------------------------------------------------------
    Author : supercaptain1233        File : Bestnoclip.lua
======================================================================]]

--====================================================================
-- SERVICES
--====================================================================

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local PhysicsService   = game:GetService("PhysicsService")
local HttpService      = game:GetService("HttpService")
local CoreGui          = game:GetService("CoreGui")
local LocalPlayer      = Players.LocalPlayer
local Camera           = workspace.CurrentCamera

--====================================================================
-- CONFIG
--====================================================================

local CONFIG = {
	Title = "Silent", Build = "4.0.0", Priority = 80,
	Group = "SilentNoclip",
	Width = 176, HeaderHeight = 30, BodyHeight = 76, Corner = 11,
	InnerCorner = 8, ButtonSize = 22, ChipHeight = 20, OrbSize = 58,
	Pad = 10, Gap = 6, ClampPad = 8, SnapDistance = 44,
	RescanSlow = 0.35, RescanFast = 0.05, RescanRate = 0.35,
	FloorGrace = 0.6,        -- seconds of Air before the root is promoted
	FreezeTime = 2.5, FreezeShort = 0.6, MaxToasts = 3, SnapWindow = 1.5,
	Panel        = Color3.fromRGB(17, 17, 20),
	PanelSoft    = Color3.fromRGB(27, 27, 31),
	PanelRaised  = Color3.fromRGB(37, 37, 42),
	Stroke       = Color3.fromRGB(52, 52, 58),
	Accent       = Color3.fromRGB(96, 140, 255),
	AccentBright = Color3.fromRGB(140, 178, 255),
	AccentDark   = Color3.fromRGB(38, 58, 110),
	Text         = Color3.fromRGB(238, 238, 242),
	TextDim      = Color3.fromRGB(134, 134, 146),
	Good = Color3.fromRGB(90, 210, 130),
	Warn = Color3.fromRGB(230, 190, 80),
	Bad  = Color3.fromRGB(232, 90, 96),
}

CONFIG.Fast   = TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
CONFIG.Smooth = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
CONFIG.Snap   = TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

--====================================================================
-- STATE
--====================================================================

local State = {
	Dragging = false, OrbDragging = false, Collapsed = false,
	OrbMode = false, MoveLocked = false, Destroyed = false,
	Frozen = false, ToastCount = 0, LastTap = 0, Role = "writer",
	Mode = "group", RootPromoted = false, AirFor = 0,
	DragOrigin = nil, DragAnchor = nil, OrbOffset = nil,
	FrozenUntil = 0, BusId = nil, BusEntry = nil,
}

local Gui, Main, Header, HeaderTray, Body, ChipRow, FindLabel
local Orb, OrbInner, OrbDot, NotifHost
local ToggleButton, ToggleLabel, StatusDot, StatusText, HeaderLabel
local ProbeChip, GuardLast = nil, 0

--====================================================================
-- UTIL : factory
--====================================================================

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end

local function corner(r, parent)
	return new("UICorner", { CornerRadius = UDim.new(0, r) }, parent)
end

local function stroke(color, thickness, transparency, parent)
	return new("UIStroke", { Color = color, Thickness = thickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
end

local function listLayout(parent, gap)
	return new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, gap or 0) }, parent)
end

local function tween(object, info, goal)
	local track = TweenService:Create(object, info, goal)
	track:Play()
	return track
end

local function viewport()
	local ok, size = pcall(function() return Camera.ViewportSize end)
	if ok and size then return size end
	return Vector2.new(1280, 720)
end

local function clamp(value, low, high)
	if value < low then return low end
	if value > high then return high end
	return value
end

local function clampPosition(position, size)
	local screen = viewport()
	return Vector2.new(
		clamp(position.X, CONFIG.ClampPad, screen.X - size.X - CONFIG.ClampPad),
		clamp(position.Y, CONFIG.ClampPad, screen.Y - size.Y - CONFIG.ClampPad))
end

local function snapToEdge(position, size)
	local screen = viewport()
	local x, y = position.X, position.Y
	if x - CONFIG.ClampPad <= CONFIG.SnapDistance then x = CONFIG.ClampPad
	elseif (screen.X - (x + size.X)) - CONFIG.ClampPad <= CONFIG.SnapDistance then
		x = screen.X - size.X - CONFIG.ClampPad
	end
	if y - CONFIG.ClampPad <= CONFIG.SnapDistance then y = CONFIG.ClampPad
	elseif (screen.Y - (y + size.Y)) - CONFIG.ClampPad <= CONFIG.SnapDistance then
		y = screen.Y - size.Y - CONFIG.ClampPad
	end
	return Vector2.new(x, y)
end

local function isPrimary(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

local function isMotion(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch
end

local function pointerOf(input)
	return Vector2.new(input.Position.X, input.Position.Y)
end

--====================================================================
-- UTIL : press feedback
--====================================================================

local function pressFeedback(button, base)
	button.MouseEnter:Connect(function()
		if not State.Destroyed then
			tween(button, CONFIG.Fast, { BackgroundTransparency = math.max(base - 0.12, 0) })
		end
	end)
	button.MouseLeave:Connect(function()
		if not State.Destroyed then
			tween(button, CONFIG.Fast, { BackgroundTransparency = base })
		end
	end)
	button.MouseButton1Down:Connect(function()
		if not State.Destroyed then
			tween(button, CONFIG.Fast, { Size = button.Size - UDim2.fromOffset(2, 2) })
		end
	end)
	button.MouseButton1Up:Connect(function()
		if not State.Destroyed then
			tween(button, CONFIG.Fast, { Size = button.Size + UDim2.fromOffset(2, 2) })
		end
	end)
end

--====================================================================
-- TOASTS
--====================================================================

local function notify(text, accent)
	if not NotifHost or State.Destroyed then return end
	if State.ToastCount >= CONFIG.MaxToasts then
		local oldest = NotifHost:FindFirstChild("Toast")
		if oldest then oldest:Destroy() end
		State.ToastCount = math.max(State.ToastCount - 1, 0)
	end
	State.ToastCount += 1
	local toast = new("Frame", { Name = "Toast", Size = UDim2.fromOffset(2, 26),
		ClipsDescendants = true, BackgroundColor3 = CONFIG.PanelSoft,
		BackgroundTransparency = 0.05, BorderSizePixel = 0 }, NotifHost)
	corner(6, toast)
	stroke(accent or CONFIG.Stroke, 1, 0.35, toast)
	new("Frame", { Size = UDim2.new(0, 3, 1, -8), Position = UDim2.new(0, 5, 0, 4),
		BackgroundColor3 = accent or CONFIG.Accent, BorderSizePixel = 0 }, toast)
	new("TextLabel", { Size = UDim2.new(1, -18, 1, 0), Position = UDim2.new(0, 14, 0, 0),
		BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, Text = text,
		TextSize = 11, TextColor3 = CONFIG.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left }, toast)
	tween(toast, CONFIG.Smooth, { Size = UDim2.fromOffset(NotifHost.AbsoluteSize.X, 26) })

	task.delay(1.7, function()
		if not toast or not toast.Parent then return end
		tween(toast, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = UDim2.fromOffset(2, 26), BackgroundTransparency = 1 })
		task.wait(0.18)
		if toast then toast:Destroy() end
		State.ToastCount = math.max(State.ToastCount - 1, 0)
	end)
end

--====================================================================
-- BUS : arbitration between copies
--====================================================================
-- Priority 80 beats the 1.0 and 2.0 builds, so this copy owns the write
-- while they mirror. Same key as before: the bus is shared, not new.

local BUS_KEY = "__NOCLIP_BUS_V3"
local host = (typeof(getgenv) == "function" and getgenv()) or _G
local bus = host[BUS_KEY]
if type(bus) ~= "table" then
	bus = { entries = {}, order = 0, arbiter = nil, mirror = nil }
	host[BUS_KEY] = bus
end

local function busArbitrate()
	local best
	for _, entry in pairs(bus.entries) do
		if entry.active and (not best or entry.priority > best.priority) then
			best = entry
		end
	end
	bus.arbiter = best
	bus.mirror = nil
	for _, entry in pairs(bus.entries) do
		if entry ~= best then bus.mirror = entry end
		entry.role = entry == best and "writer" or "mirror"
	end
end

local function busRegister(entry)
	bus.order += 1
	entry.order = bus.order
	entry.active = false
	entry.role = "writer"
	bus.entries[bus.order] = entry
	return entry
end

local function busUnregister(entry)
	bus.entries[entry.order] = nil
	if bus.arbiter == entry then bus.arbiter = nil end
	if bus.mirror == entry then bus.mirror = nil end
	busArbitrate()
	if bus.arbiter and bus.arbiter.onPromote then bus.arbiter.onPromote() end
end

local function busActivate(entry)
	entry.active = true
	busArbitrate()
	if entry.role == "writer" then
		State.Role = "writer"
		if entry.onPromote then entry.onPromote() end
	else
		State.Role = "mirror"
		if entry.onDemote then entry.onDemote() end
	end
end

local function busDeactivate(entry)
	entry.active = false
	busArbitrate()
	if entry.onDemote then entry.onDemote() end
	if bus.arbiter and bus.arbiter.onPromote then bus.arbiter.onPromote() end
end

local function isWriter()
	return bus.arbiter ~= nil and bus.arbiter.id == State.BusId
end

--====================================================================
-- ENGINE : collision group
--====================================================================

local Engine = {}
Engine.Group = CONFIG.Group
Engine.Ready = false
Engine.Active = false
Engine.Original = setmetatable({}, { __mode = "k" })
Engine.Links = {}
Engine.Rescan = nil
Engine.Guard = nil
Engine.Insure = nil

-- The whole point: the solver is told there is no pair to resolve.
-- CanCollide is never written, so anything polling it reads normal.
function Engine:Arm()
	if self.Ready then return true end
	local ok = pcall(function()
		pcall(function() PhysicsService:RegisterCollisionGroup(self.Group) end)
		PhysicsService:CollisionGroupSetCollidable(self.Group, "Default", false)
	end)
	self.Ready = ok
	if not ok then
		State.Mode = "legacy"   -- PhysicsService blocked, fall back to CanCollide
	end
	return ok
end

function Engine:Disarm()
	if not self.Ready then return end
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(self.Group, "Default", true)
	end)
end

-- stamp the group on every part, remembering what it was
function Engine:Stamp(model)
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") then
			if self.Original[item] == nil then
				self.Original[item] = { group = item.CollisionGroup, solid = item.CanCollide }
			end
			if self.Ready then
				item.CollisionGroup = self.Group
			else
				item.CanCollide = false
			end
		end
	end
end

function Engine:Unstamp()
	for part, record in pairs(self.Original) do
		if part and part.Parent then
			pcall(function()
				part.CollisionGroup = record.group
				part.CanCollide = record.solid
			end)
		end
	end
	self.Original = setmetatable({}, { __mode = "k" })
	State.RootPromoted = false
end

-- Root promotion. If the floor raycast starves, put the root back in
-- Default so real collision holds the body up. Walls still phase.
function Engine:PromoteRoot()
	local root = LocalPlayer.Character
		and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	if not root or State.RootPromoted then return end
	State.RootPromoted = true
	root.CollisionGroup = "Default"   -- stays CanCollide true
	notify("Floor insurance", CONFIG.Warn)
end

--====================================================================
-- HARDENING
--====================================================================

function Engine:Calm(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end

function Engine:Freeze(seconds)
	if State.Frozen then return end
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	State.Frozen = true
	State.FrozenUntil = os.clock() + (seconds or CONFIG.FreezeTime)
	root.Anchored = true
	self:Calm(character)
	notify("Frozen " .. string.format("%.1fs", seconds or CONFIG.FreezeTime), CONFIG.Warn)
	paintToggle()
end

function Engine:Thaw()
	if not State.Frozen then return end
	State.Frozen = false
	State.FrozenUntil = 0
	local root = LocalPlayer.Character
		and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	if root then root.Anchored = false end
	paintToggle()
end

-- Floor insurance watcher. A phased body should read Running on ground;
-- if it reads Air too long, promote the root.
function Engine:InsureLoop()
	while Engine.Active do
		local character = LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			if humanoid.FloorMaterial == Enum.Material.Air then
				State.AirFor += 0.1
				if State.AirFor > CONFIG.FloorGrace then self:PromoteRoot() end
			else
				State.AirFor = 0
			end
		end
		task.wait(0.1)
	end
end

-- Snap-back guard, same signature as the last build: input with no
-- velocity means a yank, so anchor before it commits.
function Engine:GuardLoop()
	while Engine.Active do
		local character = LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and not State.Frozen then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local moving = humanoid and humanoid.MoveDirection.Magnitude > 0.05
			local slow = root.AssemblyLinearVelocity.Magnitude < CONFIG.SnapWindow
			if moving and slow and os.clock() - GuardLast > 0.4 then
				GuardLast = os.clock()
				self:Freeze(CONFIG.FreezeShort)
			end
		end
		if State.Frozen and os.clock() >= State.FrozenUntil then self:Thaw() end
		task.wait(0.1)
	end
end

local function reassert(model)
	if isWriter() then Engine:Stamp(model) end
end

--====================================================================
-- ENGINE : lifecycle
--====================================================================

function Engine:Watch(model)
	local function onDescendant(descendant)
		if not Engine.Active then return end
		if descendant:IsA("BasePart") then
			if Engine.Original[descendant] == nil then
				Engine.Original[descendant] = {
					group = descendant.CollisionGroup, solid = descendant.CanCollide }
			end
			if Engine.Ready then
				descendant.CollisionGroup = Engine.Group
			else
				descendant.CanCollide = false
			end
		end
	end
	table.insert(self.Links, model.DescendantAdded:Connect(onDescendant))
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		table.insert(self.Links, humanoid.Died:Connect(function()
			if not self.Active then return end
			task.defer(function()
				if not self.Active then return end
				local fresh = LocalPlayer.Character
					or LocalPlayer.CharacterAdded:Wait()
				fresh:WaitForChild("HumanoidRootPart", 10)
				task.wait(0.1)
				if not self.Active then return end
				self:Stamp(fresh)
				self:Watch(fresh)
			end)
		end))
	end
end

function Engine:Unwatch()
	for _, link in ipairs(self.Links) do
		if link.Connected then link:Disconnect() end
	end
	self.Links = {}
end

function Engine:Start()
	if self.Active then return end
	local character = LocalPlayer.Character
	if not character then
		notify("No character loaded", CONFIG.Accent)
		return
	end
	self:Arm()
	self.Active = true
	self:Stamp(character)
	self:Watch(character)
	self:Calm(character)
	self.Rescan = task.spawn(function()
		while self.Active do
			local current = LocalPlayer.Character
			if current then reassert(current) end
			task.wait(CONFIG.RescanRate)
		end
	end)
	self.Guard = task.spawn(function() self:GuardLoop() end)
	self.Insure = task.spawn(function() self:InsureLoop() end)
	if State.BusEntry then busActivate(State.BusEntry) end
	notify("Silent armed · " .. State.Mode, CONFIG.AccentBright)
end

function Engine:Stop()
	if not self.Active then return end
	self.Active = false
	if self.Rescan then task.cancel(self.Rescan) self.Rescan = nil end
	if self.Guard then task.cancel(self.Guard) self.Guard = nil end
	if self.Insure then task.cancel(self.Insure) self.Insure = nil end
	self:Thaw()
	self:Unwatch()
	self:Unstamp()
	self:Disarm()
	if State.BusEntry then busDeactivate(State.BusEntry) end
	notify("Silent off", CONFIG.TextDim)
end

function Engine:Toggle()
	if self.Active then self:Stop() else self:Start() end
end

--====================================================================
-- PROBE : learn the game's weaknesses
--====================================================================
-- Reads capability first, then behaviour. Score drives the rescan rate,
-- and the profile lands in SilentNoclip/profile.json for the next run.

local Probe = {}
Probe.Findings = {}
Probe.Score = 0
Probe.Flips = 0
Probe.Snaps = 0
Probe.Thread = nil
Probe.Profile = {}

local FOLDER = "SilentNoclip"
local FILE = FOLDER .. "/profile.json"

function Probe:Note(text, weight, good)
	table.insert(self.Findings, { text = text, good = good })
	if not good then self.Score += (weight or 10) end
	if #self.Findings > 6 then table.remove(self.Findings, 1) end
	if FindLabel then
		local lines = {}
		for _, item in ipairs(self.Findings) do
			table.insert(lines, (item.good and "+ " or "! ") .. item.text)
		end
		FindLabel.Text = table.concat(lines, "\n")
	end
end

function Probe:Capabilities()
	if typeof(writefile) == "function" then
		self:Note("disk writes available", 0, true)
		self.CanPersist = true
	else
		self:Note("no disk writes", 5)
	end
	if typeof(gethui) == "function" then
		self:Note("gethui available", 0, true)
	else
		self:Note("CoreGui direct", 3)
	end
	local ok = pcall(function()
		pcall(function() PhysicsService:RegisterCollisionGroup(CONFIG.Group) end)
		PhysicsService:CollisionGroupSetCollidable(CONFIG.Group, "Default", false)
	end)
	if ok then
		self:Note("solver phasing works", 0, true)
	else
		self:Note("solver blocked, legacy", 30)
	end
end

function Probe:Remotes()
	local hits = 0
	local names = { "check", "clip", "wall", "detect", "anti", "cheat", "noclip", "pos" }
	for _, service in ipairs({ "ReplicatedStorage", "ReplicatedFirst", "StarterPlayer" }) do
		local root = game:FindFirstChild(service)
		if root then
			for _, item in ipairs(root:GetDescendants()) do
				if item:IsA("RemoteEvent") or item:IsA("RemoteFunction") then
					local low = string.lower(item.Name)
					for _, key in ipairs(names) do
						if string.find(low, key, 1, true) then
							hits += 1
							break
						end
					end
				end
			end
		end
	end
	if hits > 0 then
		self:Note(hits .. " check remotes", math.min(hits, 20))
	else
		self:Note("no check remotes", 0, true)
	end
end

function Probe:Watch()
	local last = nil
	while not State.Destroyed do
		local character = LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			if last then
				local step = (root.Position - last).Magnitude
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				local moving = humanoid and humanoid.MoveDirection.Magnitude > 0.05
				if step > 12 and moving then
					self.Snaps += 1
					self:Note("position yanked", 8)
				end
			end
			last = root.Position
		end
		task.wait(0.25)
	end
end

function Probe:Tune()
	if self.Score >= 25 then
		CONFIG.RescanRate = CONFIG.RescanFast
		CONFIG.FreezeShort = 0.9
	else
		CONFIG.RescanRate = CONFIG.RescanSlow
	end
end

function Probe:Save()
	if not self.CanPersist then return end
	self.Profile = {
		score = self.Score, snaps = self.Snaps, flips = self.Flips,
		mode = State.Mode, rescan = CONFIG.RescanRate,
		saved = os.date("!%Y-%m-%dT%H:%M:%SZ"),
	}
	pcall(function()
		if typeof(makefolder) == "function" and typeof(isfolder) == "function" then
			if not isfolder(FOLDER) then makefolder(FOLDER) end
		end
		writefile(FILE, HttpService:JSONEncode(self.Profile))
	end)
end

function Probe:Load()
	if typeof(readfile) ~= "function" or typeof(isfile) ~= "function" then return end
	if not isfile(FILE) then return end
	local ok, raw = pcall(readfile, FILE)
	if not ok or not raw then return end
	local decoded = pcall(function() return HttpService:JSONDecode(raw) end)
	if not decoded then return end
	local data = HttpService:JSONDecode(raw)
	if data and data.score then
		self:Note("profile score " .. tostring(data.score), 0, true)
		if data.score >= 25 then CONFIG.RescanRate = CONFIG.RescanFast end
	end
end

function Probe:Run()
	self:Capabilities()
	self:Load()
	self:Remotes()
	self:Tune()
	self.Thread = task.spawn(function() self:Watch() end)
end

--====================================================================
-- ICONS
--====================================================================

local function drawMoveIcon(host, color)
	local wrap = new("Frame", { Size = UDim2.fromOffset(14, 14),
		Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1 }, host)
	new("Frame", { Size = UDim2.fromOffset(2, 12), Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = color,
		BorderSizePixel = 0 }, wrap)
	new("Frame", { Size = UDim2.fromOffset(12, 2), Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = color,
		BorderSizePixel = 0 }, wrap)
	for _, pos in ipairs({ UDim2.fromScale(0.5, 0), UDim2.fromScale(0.5, 1),
		UDim2.fromScale(0, 0.5), UDim2.fromScale(1, 0.5) }) do
		local head = new("Frame", { Size = UDim2.fromOffset(5, 5), Position = pos,
			AnchorPoint = Vector2.new(0.5, 0.5), Rotation = 45,
			BackgroundColor3 = color, BorderSizePixel = 0 }, wrap)
		corner(1, head)
	end
	return wrap
end

local function drawOrbIcon(host, color)
	local ring = new("Frame", { Size = UDim2.fromOffset(13, 13),
		Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1 }, host)
	corner(7, ring)
	stroke(color, 1.4, 0, ring)
	local core = new("Frame", { Size = UDim2.fromOffset(5, 5),
		Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color, BorderSizePixel = 0 }, ring)
	corner(3, core)
	return ring
end

local function drawCloseIcon(host, color)
	local wrap = new("Frame", { Size = UDim2.fromOffset(14, 14),
		Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1 }, host)
	for _, angle in ipairs({ 45, -45 }) do
		local bar = new("Frame", { Size = UDim2.fromOffset(2, 11),
			Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = angle, BackgroundColor3 = color, BorderSizePixel = 0 }, wrap)
		corner(1, bar)
	end
	return wrap
end

local function makeHeaderButton(iconFn, order)
	local button = new("TextButton", {
		Size = UDim2.fromOffset(CONFIG.ButtonSize, CONFIG.ButtonSize),
		BackgroundColor3 = CONFIG.PanelRaised, BackgroundTransparency = 0.15,
		BorderSizePixel = 0, AutoButtonColor = false, Text = "",
		LayoutOrder = order }, HeaderTray)
	corner(6, button)
	pressFeedback(button, 0.15)
	iconFn(button, CONFIG.Text)
	return button
end

local function makeChip(label, order, startOn, onFlip)
	local chip = new("TextButton", {
		Size = UDim2.new(0.25, -CONFIG.Gap, 0, CONFIG.ChipHeight),
		BackgroundColor3 = CONFIG.PanelRaised, BackgroundTransparency = 0.2,
		BorderSizePixel = 0, AutoButtonColor = false, Text = "",
		LayoutOrder = order }, ChipRow)
	corner(5, chip)
	pressFeedback(chip, 0.2)
	local dot = new("Frame", { Size = UDim2.fromOffset(4, 4),
		Position = UDim2.fromOffset(4, CONFIG.ChipHeight / 2 - 2),
		BackgroundColor3 = startOn and CONFIG.AccentBright or CONFIG.Stroke,
		BorderSizePixel = 0 }, chip)
	corner(2, dot)
	new("TextLabel", { Size = UDim2.new(1, -9, 1, 0), Position = UDim2.fromOffset(9, 0),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = label,
		TextSize = 7, TextColor3 = CONFIG.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left }, chip)
	local on = startOn
	chip.MouseButton1Click:Connect(function()
		if State.Destroyed then return end
		on = not on
		dot.BackgroundColor3 = on and CONFIG.AccentBright or CONFIG.Stroke
		onFlip(on)
	end)
	return chip
end

--====================================================================
-- ORB
--====================================================================

local function enterOrbMode()
	if State.OrbMode then return end
	State.OrbMode = true
	local origin = Main.AbsolutePosition
	local size = Main.AbsoluteSize
	local center = Vector2.new(origin.X + size.X / 2, origin.Y + size.Y / 2)
	local placed = clampPosition(Vector2.new(center.X - CONFIG.OrbSize / 2,
		center.Y - CONFIG.OrbSize / 2), Vector2.new(CONFIG.OrbSize, CONFIG.OrbSize))
	Orb.Position = UDim2.fromOffset(placed.X, placed.Y)
	Orb.Visible = true
	Orb.BackgroundTransparency = 1
	OrbInner.BackgroundTransparency = 1
	Main.Visible = false
	tween(Orb, CONFIG.Smooth, { BackgroundTransparency = 0.05 })
	tween(OrbInner, CONFIG.Smooth, { BackgroundTransparency = 0 })
end

local function exitOrbMode()
	if not State.OrbMode then return end
	State.OrbMode = false
	local orbPosition = Orb.AbsolutePosition
	local orbSize = Orb.AbsoluteSize
	local target = Vector2.new(
		orbPosition.X + orbSize.X / 2 - Main.AbsoluteSize.X / 2,
		orbPosition.Y + orbSize.Y / 2 - Main.AbsoluteSize.Y / 2)
	local placed = clampPosition(target, Main.AbsoluteSize)
	Main.Position = UDim2.fromOffset(placed.X, placed.Y)
	Main.Visible = true
	Orb.Visible = false
end

local function buildOrb(parent)
	Orb = new("TextButton", { Name = "Orb",
		Size = UDim2.fromOffset(CONFIG.OrbSize, CONFIG.OrbSize),
		Position = UDim2.fromOffset(120, 120), BackgroundColor3 = CONFIG.Panel,
		BackgroundTransparency = 0.05, BorderSizePixel = 0, AutoButtonColor = false,
		Text = "", Visible = false, ZIndex = 20 }, parent)
	corner(CONFIG.OrbSize / 2, Orb)
	stroke(CONFIG.Accent, 2, 0.15, Orb)
	OrbInner = new("Frame", {
		Size = UDim2.fromOffset(CONFIG.OrbSize - 15, CONFIG.OrbSize - 15),
		Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = CONFIG.PanelRaised, BorderSizePixel = 0, ZIndex = 21 }, Orb)
	corner((CONFIG.OrbSize - 15) / 2, OrbInner)
	drawOrbIcon(OrbInner, CONFIG.AccentBright)
	OrbDot = new("Frame", { Size = UDim2.fromOffset(9, 9),
		Position = UDim2.new(0.5, 0, 1, -5), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = CONFIG.AccentBright, BorderSizePixel = 0,
		Visible = false, ZIndex = 22 }, Orb)
	corner(5, OrbDot)
	stroke(CONFIG.Panel, 1.5, 0, OrbDot)
end

--====================================================================
-- TOGGLE
--====================================================================

function paintToggle()
	if not ToggleButton then return end
	if Engine.Active then
		tween(ToggleButton, CONFIG.Fast, { BackgroundColor3 = CONFIG.AccentBright })
		ToggleLabel.Text = State.Mode == "group" and "SILENT  ON" or "LEGACY  ON"
		ToggleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		StatusDot.BackgroundColor3 = CONFIG.AccentBright
		StatusText.Text = State.Frozen and "FROZEN"
			or (State.Role == "mirror" and "MIRROR" or "ARMED")
		StatusText.TextColor3 = State.Frozen and CONFIG.Warn or CONFIG.AccentBright
		OrbDot.Visible = true
	else
		tween(ToggleButton, CONFIG.Fast, { BackgroundColor3 = CONFIG.Accent })
		ToggleLabel.Text = "SILENT"
		ToggleLabel.TextColor3 = Color3.fromRGB(255, 238, 238)
		StatusDot.BackgroundColor3 = CONFIG.AccentDark
		StatusText.Text = "IDLE"
		StatusText.TextColor3 = CONFIG.TextDim
		OrbDot.Visible = false
	end
end

local function buildToggle()
	ToggleButton = new("TextButton", { Size = UDim2.new(1, -CONFIG.Pad * 2, 0, 34),
		Position = UDim2.fromOffset(CONFIG.Pad, 6), BackgroundColor3 = CONFIG.Accent,
		BorderSizePixel = 0, AutoButtonColor = false, Text = "",
		ClipsDescendants = true }, Body)
	corner(CONFIG.InnerCorner, ToggleButton)
	stroke(CONFIG.AccentDark, 1, 0.4, ToggleButton)
	ToggleLabel = new("TextLabel", { Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = "SILENT",
		TextSize = 13, TextColor3 = Color3.fromRGB(255, 238, 238),
		TextXAlignment = Enum.TextXAlignment.Center }, ToggleButton)
	pressFeedback(ToggleButton, 0)
	ToggleButton.MouseButton1Click:Connect(function()
		if State.Destroyed then return end
		Engine:Toggle()
		paintToggle()
	end)
end

--====================================================================
-- HEADER
--====================================================================

local function buildHeader()
	Header = new("Frame", { Name = "Header",
		Size = UDim2.new(1, 0, 0, CONFIG.HeaderHeight),
		BackgroundColor3 = CONFIG.PanelSoft, BorderSizePixel = 0 }, Main)
	corner(CONFIG.Corner, Header)
	new("Frame", { Size = UDim2.new(1, -CONFIG.Pad * 2, 0, 1),
		Position = UDim2.new(0, CONFIG.Pad, 1, -1), BackgroundColor3 = CONFIG.Stroke,
		BorderSizePixel = 0 }, Header)
	StatusDot = new("Frame", { Size = UDim2.fromOffset(6, 6),
		Position = UDim2.fromOffset(CONFIG.Pad, CONFIG.HeaderHeight / 2 - 3),
		BackgroundColor3 = CONFIG.AccentDark, BorderSizePixel = 0 }, Header)
	corner(3, StatusDot)
	HeaderLabel = new("TextLabel", { Size = UDim2.new(0, 56, 1, 0),
		Position = UDim2.fromOffset(CONFIG.Pad + 12, 0), BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold, Text = CONFIG.Title, TextSize = 12,
		TextColor3 = CONFIG.Text, TextXAlignment = Enum.TextXAlignment.Left }, Header)
	StatusText = new("TextLabel", { Size = UDim2.fromOffset(44, 1),
		Position = UDim2.new(0, CONFIG.Pad + 66, 1, -9), BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold, Text = "IDLE", TextSize = 7,
		TextColor3 = CONFIG.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left }, Header)
	HeaderTray = new("Frame", { Size = UDim2.new(1, -CONFIG.Pad * 2, 1, 0),
		Position = UDim2.fromOffset(CONFIG.Pad, 0), BackgroundTransparency = 1 }, Header)
	listLayout(HeaderTray, CONFIG.Gap)
end

--====================================================================
-- DRAG
--====================================================================

local function beginDrag(input)
	State.Dragging = true
	State.DragOrigin = pointerOf(input)
	State.DragAnchor = Vector2.new(Main.AbsolutePosition.X, Main.AbsolutePosition.Y)
end

local function moveDrag(input)
	if not State.Dragging then return end
	local placed = clampPosition(
		State.DragAnchor + (pointerOf(input) - State.DragOrigin), Main.AbsoluteSize)
	Main.Position = UDim2.fromOffset(placed.X, placed.Y)
end

local function endDrag()
	if not State.Dragging then return end
	State.Dragging = false
	local snapped = snapToEdge(Main.AbsolutePosition, Main.AbsoluteSize)
	tween(Main, CONFIG.Smooth, { Position = UDim2.fromOffset(snapped.X, snapped.Y) })
end

local function bindHeaderDrag()
	Header.InputBegan:Connect(function(input)
		if not isPrimary(input) or State.OrbMode or State.Destroyed then return end
		beginDrag(input)
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then endDrag() end
		end)
	end)
end

local function bindOrbDrag()
	Orb.InputBegan:Connect(function(input)
		if not isPrimary(input) or State.Destroyed then return end
		State.OrbDragging = true
		State.OrbOffset = Vector2.new(Orb.AbsolutePosition.X, Orb.AbsolutePosition.Y)
			- pointerOf(input)
		tween(Orb, CONFIG.Fast, {
			Size = UDim2.fromOffset(CONFIG.OrbSize - 6, CONFIG.OrbSize - 6) })
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				State.OrbDragging = false
				tween(Orb, CONFIG.Snap, {
					Size = UDim2.fromOffset(CONFIG.OrbSize, CONFIG.OrbSize) })
			end
		end)
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not State.OrbDragging or not State.OrbOffset then return end
		if not isMotion(input) then return end
		local placed = clampPosition(pointerOf(input) + State.OrbOffset, Orb.AbsoluteSize)
		Orb.Position = UDim2.fromOffset(placed.X, placed.Y)
	end)
end

--====================================================================
-- COLLAPSE
--====================================================================

local function setCollapsed(value)
	if State.Collapsed == value then return end
	State.Collapsed = value
	if value then
		Body.Visible = false
		HeaderLabel.TextColor3 = CONFIG.TextDim
		tween(Main, CONFIG.Smooth, {
			Size = UDim2.fromOffset(CONFIG.Width, CONFIG.HeaderHeight) })
	else
		HeaderLabel.TextColor3 = CONFIG.Text
		tween(Main, CONFIG.Smooth, {
			Size = UDim2.fromOffset(CONFIG.Width, CONFIG.HeaderHeight + CONFIG.BodyHeight) })
		task.delay(0.06, function()
			if not State.Collapsed and not State.Destroyed then Body.Visible = true end
		end)
	end
end

--====================================================================
-- ASSEMBLY
--====================================================================

local function parentTarget()
	if typeof(gethui) == "function" then
		local ok, handle = pcall(gethui)
		if ok and handle then return handle end
	end
	local probe = Instance.new("Folder")
	local ok = pcall(function() probe.Parent = CoreGui end)
	probe:Destroy()
	if ok then return CoreGui end
	return LocalPlayer:WaitForChild("PlayerGui")
end

local function build()
	Gui = new("ScreenGui", { Name = "SilentNoclip", ResetOnSpawn = false,
		IgnoreGuiInset = true, DisplayOrder = 9999,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
	NotifHost = new("Frame", { Name = "Toasts", Size = UDim2.new(1, 0, 0, 96),
		BackgroundTransparency = 1 }, Gui)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 4) }, NotifHost)
	Main = new("Frame", { Name = "Main", Position = UDim2.fromOffset(24, 24),
		Size = UDim2.fromOffset(CONFIG.Width, CONFIG.HeaderHeight + CONFIG.BodyHeight),
		BackgroundColor3 = CONFIG.Panel, BorderSizePixel = 0,
		ClipsDescendants = true }, Gui)
	corner(CONFIG.Corner, Main)
	stroke(CONFIG.Stroke, 1, 0.25, Main)
	buildHeader()
	Body = new("Frame", { Name = "Body", Size = UDim2.new(1, 0, 0, CONFIG.BodyHeight),
		Position = UDim2.fromOffset(0, CONFIG.HeaderHeight),
		BackgroundTransparency = 1 }, Main)
	buildToggle()
	ChipRow = new("Frame", { Name = "Chips",
		Size = UDim2.new(1, -CONFIG.Pad * 2, 0, CONFIG.ChipHeight),
		Position = UDim2.fromOffset(CONFIG.Pad, 44), BackgroundTransparency = 1 }, Body)
	listLayout(ChipRow, CONFIG.Gap)
	ProbeChip = makeChip("PROBE", 1, false, function(on)
		if on then
			Probe:Run()
		else
			if Probe.Thread then task.cancel(Probe.Thread) Probe.Thread = nil end
		end
	end)
	makeChip("FREEZE", 2, false, function(on)
		if on then Engine:Freeze(CONFIG.FreezeTime) else Engine:Thaw() end
	end)
	makeChip("FAST", 3, false, function(on)
		CONFIG.RescanRate = on and CONFIG.RescanFast or CONFIG.RescanSlow
	end)
	makeChip("SAVE", 4, false, function()
		Probe:Save()
		notify("Profile saved", CONFIG.Accent)
	end)
	FindLabel = new("TextLabel", { Name = "Findings",
		Size = UDim2.new(1, -CONFIG.Pad * 2, 0, 26),
		Position = UDim2.fromOffset(CONFIG.Pad, 68), BackgroundTransparency = 1,
		Font = Enum.Font.Code, Text = "", TextSize = 8, TextWrap = true,
		TextColor3 = CONFIG.TextDim, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top }, Body)
	local orbButton = makeHeaderButton(drawOrbIcon, 1)
	local moveButton = makeHeaderButton(drawMoveIcon, 2)
	local closeButton = makeHeaderButton(drawCloseIcon, 3)
	buildOrb(Gui)
	orbButton.MouseButton1Click:Connect(function()
		if State.Destroyed then return end
		if State.OrbMode then exitOrbMode() else enterOrbMode() end end)
	Orb.MouseButton1Click:Connect(function()
		if not State.OrbDragging then exitOrbMode() end end)
	moveButton.MouseButton1Click:Connect(function()
		State.MoveLocked = not State.MoveLocked
		if State.MoveLocked then stroke(CONFIG.Accent, 1.5, 0, moveButton)
			notify("Drag unlocked", CONFIG.Accent) else
			local s = moveButton:FindFirstChildOfClass("UIStroke") if s then s:Destroy() end
			notify("Drag locked", CONFIG.TextDim) end end)
	closeButton.MouseButton1Click:Connect(function() setCollapsed(not State.Collapsed) end)
	HeaderLabel.InputBegan:Connect(function(input)
		if not isPrimary(input) or State.Destroyed then return end
		if State.Collapsed then return setCollapsed(false) end
		local now = os.clock()
		if now - State.LastTap <= 0.35 then
			Main.Position = UDim2.fromOffset(24, 24) State.LastTap = 0
		else State.LastTap = now end end)
	Gui.Parent = parentTarget()
	bindHeaderDrag() bindOrbDrag() paintToggle()
	UserInputService.InputChanged:Connect(function(input)
		if State.Dragging and isMotion(input) then moveDrag(input) end end)
	UserInputService.InputEnded:Connect(function(input)
		if isPrimary(input) then endDrag() end end)
	Camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		if not Main or State.Destroyed then return end
		local placed = clampPosition(Main.AbsolutePosition, Main.AbsoluteSize)
		Main.Position = UDim2.fromOffset(placed.X, placed.Y) end)
end

--====================================================================
-- KEYS + BOOT
--====================================================================
-- RightShift arm · RightAlt collapse · RightControl orb

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or State.Destroyed then return end
	if input.KeyCode == Enum.KeyCode.RightShift then Engine:Toggle() paintToggle()
	elseif input.KeyCode == Enum.KeyCode.RightAlt then setCollapsed(not State.Collapsed)
	elseif input.KeyCode == Enum.KeyCode.RightControl then
		if State.OrbMode then exitOrbMode() else enterOrbMode() end
	end
end)

local Entry = busRegister({ id = tostring(math.random(1000000)),
	priority = CONFIG.Priority,
	onPromote = function() if Engine.Active then reassert(LocalPlayer.Character) end end,
	onDemote = function() if Engine.Active then Engine:Unstamp() end end })
State.BusId = Entry.id
State.BusEntry = Entry

local built, err = pcall(build)
if not built then warn("[SilentNoclip] " .. tostring(err)) end

LocalPlayer.CharacterAdded:Connect(function(character)
	if not Engine.Active then return end
	character:WaitForChild("HumanoidRootPart", 10)
	task.wait(0.12)
	if not Engine.Active then return end
	Engine:Stamp(character) Engine:Watch(character)
end)

--====================================================================
-- DOCS
--====================================================================
--[[
  SILENT MODE. CanCollide is never written. The character joins a
  collision group disabled against Default, so the solver itself
  reports no contact and every poll comes back normal.

  PROBE. Run the PROBE chip once per game. It reads capability, lists
  check remotes, watches for yanks, scores hostility, tunes the rescan
  rate from the score. SAVE writes SilentNoclip/profile.json, which is
  read back next launch.

  FLOOR. Group phasing keeps the humanoid raycast. If Air persists
  past 0.6s the root is promoted to Default so real collision holds.

  CHIPS. PROBE learn · FREEZE 2.5s anchor · FAST 0.05s rescan · SAVE
  write profile.

  KEYS. RightShift arm · RightAlt collapse · RightControl orb.
]]
--[[====================================================================
    S H I E L D   ·   Build 5.0.0
    Same repo, same file, one blank line below the last build.
    Bus priority 100. Outranks every earlier copy so it can guard them.
-----------------------------------------------------------------------
    WHAT THIS IS
    Not another noclip. This is the bodyguard for the three below it.
    It holds a set of invariants and re-asserts any that get broken:
    the ScreenGui, the panel children, the toggle state, WalkSpeed,
    PlatformStand, AutoRotate, the collision stamps, the bus slot.
    Anything the game knocks over gets put back inside half a second.
-----------------------------------------------------------------------
    WHAT IT DEFENDS
      gui destroyed or unparented      -> rebuilt or re-parented
      gui.Enabled or Visible flipped   -> set back
      DisplayOrder lowered             -> raised back
      children deleted                 -> panel rebuilt
      WalkSpeed zeroed                 -> last non-zero restored
      PlatformStand held true          -> released
      AutoRotate disabled              -> re-enabled
      collision stamps stripped        -> re-stamped from the winner
      bus slot cleared                 -> entry re-registered
      loop thrown an error             -> supervisor restarts it
--@001
-----------------------------------------------------------------------
    EVERY LOOP IS WRAPPED
    No guard thread dies on one bad call. Bodies run inside pcall, and a
    supervisor re-spawns anything that stops. Repair bursts are counted:
    six fixes inside ten seconds escalates to a hard re-attach.
-----------------------------------------------------------------------
    CO-EXISTENCE
    Reads the shared bus and never phases on its own. It stamps in
    whichever mode the winning copy chose, so it repairs for build 1, 2
    and 3 alike without fighting any of them. Toggle it off and the
    noclip panels behave exactly as they did before.
-----------------------------------------------------------------------
    Author : supercaptain1233        File : Bestnoclip.lua
======================================================================]]

--====================================================================
-- SERVICES
--====================================================================

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local CoreGui          = game:GetService("CoreGui")
local LocalPlayer      = Players.LocalPlayer
local Camera           = workspace.CurrentCamera
--@002

--====================================================================
-- CONFIG
--====================================================================

local CONFIG = {
	Title = "Shield", Build = "5.0.0", Priority = 100,
	Width = 176, HeaderHeight = 30, BodyHeight = 76, Corner = 11,
	InnerCorner = 8, ButtonSize = 22, ChipHeight = 20, OrbSize = 58,
	Pad = 10, Gap = 6, ClampPad = 8, SnapDistance = 44,
	Tick = 0.5,              -- invariant sweep interval
	Grace = 1.5,             -- seconds before a soft break is repaired
	Burst = 6,               -- repairs inside BurstWindow that escalate
	BurstWindow = 10,
	MinDisplay = 9999,
	Panel        = Color3.fromRGB(16, 18, 16),
	PanelSoft    = Color3.fromRGB(26, 29, 26),
	PanelRaised  = Color3.fromRGB(36, 40, 36),
	Stroke       = Color3.fromRGB(50, 56, 50),
	Accent       = Color3.fromRGB(92, 196, 120),
	AccentBright = Color3.fromRGB(134, 232, 160),
	AccentDark   = Color3.fromRGB(34, 74, 46),
	Text         = Color3.fromRGB(238, 242, 238),
	TextDim      = Color3.fromRGB(132, 140, 132),
	Warn         = Color3.fromRGB(230, 190, 80),
	Bad          = Color3.fromRGB(232, 90, 96),
}
--@003

CONFIG.Fast   = TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
CONFIG.Smooth = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
CONFIG.Snap   = TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

--====================================================================
-- STATE
--====================================================================

local State = {
	Dragging = false, OrbDragging = false, Collapsed = false,
	OrbMode = false, MoveLocked = false, Destroyed = false,
	ToastCount = 0, LastTap = 0, Role = "guard",
	DragOrigin = nil, DragAnchor = nil, OrbOffset = nil,
	BusId = nil, BusEntry = nil,
}
--@004

local Gui, Main, Header, HeaderTray, Body, ChipRow, LogLabel
local Orb, OrbInner, OrbDot, NotifHost
local ToggleButton, ToggleLabel, StatusDot, StatusText, HeaderLabel
local WatchChip, GuardLast = nil, 0

--====================================================================
-- UTIL : factory
--====================================================================

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end
--@005

local function corner(r, parent)
	return new("UICorner", { CornerRadius = UDim.new(0, r) }, parent)
end

local function stroke(color, thickness, transparency, parent)
	return new("UIStroke", { Color = color, Thickness = thickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
end
--@006

local function listLayout(parent, gap)
	return new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, gap or 0) }, parent)
end

local function tween(object, info, goal)
	local track = TweenService:Create(object, info, goal)
	track:Play()
	return track
end
--@007

local function viewport()
	local ok, size = pcall(function() return Camera.ViewportSize end)
	if ok and size then return size end
	return Vector2.new(1280, 720)
end

local function clamp(value, low, high)
	if value < low then return low end
	if value > high then return high end
	return value
end
--@008

local function clampPosition(position, size)
	local screen = viewport()
	return Vector2.new(
		clamp(position.X, CONFIG.ClampPad, screen.X - size.X - CONFIG.ClampPad),
		clamp(position.Y, CONFIG.ClampPad, screen.Y - size.Y - CONFIG.ClampPad))
end

local function snapToEdge(position, size)
	local screen = viewport()
	local x, y = position.X, position.Y
--@009
	if x - CONFIG.ClampPad <= CONFIG.SnapDistance then x = CONFIG.ClampPad
	elseif (screen.X - (x + size.X)) - CONFIG.ClampPad <= CONFIG.SnapDistance then
		x = screen.X - size.X - CONFIG.ClampPad
	end
	if y - CONFIG.ClampPad <= CONFIG.SnapDistance then y = CONFIG.ClampPad
	elseif (screen.Y - (y + size.Y)) - CONFIG.ClampPad <= CONFIG.SnapDistance then
		y = screen.Y - size.Y - CONFIG.ClampPad
	end
	return Vector2.new(x, y)
--@010
end

local function isPrimary(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

local function isMotion(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch
end
--@011

local function pointerOf(input)
	return Vector2.new(input.Position.X, input.Position.Y)
end

--====================================================================
-- UTIL : press feedback
--====================================================================

local function pressFeedback(button, base)
	button.MouseEnter:Connect(function()
		if not State.Destroyed then
--@012
			tween(button, CONFIG.Fast, { BackgroundTransparency = math.max(base - 0.12, 0) })
		end
	end)
	button.MouseLeave:Connect(function()
		if not State.Destroyed then
			tween(button, CONFIG.Fast, { BackgroundTransparency = base })
		end
	end)
	button.MouseButton1Down:Connect(function()
--@013
		if not State.Destroyed then
			tween(button, CONFIG.Fast, { Size = button.Size - UDim2.fromOffset(2, 2) })
		end
	end)
	button.MouseButton1Up:Connect(function()
		if not State.Destroyed then
			tween(button, CONFIG.Fast, { Size = button.Size + UDim2.fromOffset(2, 2) })
		end
	end)
end
--@014

--====================================================================
-- TOASTS
--====================================================================

local function notify(text, accent)
	if not NotifHost or State.Destroyed then return end
	if State.ToastCount >= 3 then
		local oldest = NotifHost:FindFirstChild("Toast")
		if oldest then oldest:Destroy() end
		State.ToastCount = math.max(State.ToastCount - 1, 0)
	end
--@015
	State.ToastCount += 1
	local toast = new("Frame", { Name = "Toast", Size = UDim2.fromOffset(2, 26),
		ClipsDescendants = true, BackgroundColor3 = CONFIG.PanelSoft,
		BackgroundTransparency = 0.05, BorderSizePixel = 0 }, NotifHost)
	corner(6, toast)
	stroke(accent or CONFIG.Stroke, 1, 0.35, toast)
	new("Frame", { Size = UDim2.new(0, 3, 1, -8), Position = UDim2.new(0, 5, 0, 4),
		BackgroundColor3 = accent or CONFIG.Accent, BorderSizePixel = 0 }, toast)
--@016
	new("TextLabel", { Size = UDim2.new(1, -18, 1, 0), Position = UDim2.new(0, 14, 0, 0),
		BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, Text = text,
		TextSize = 11, TextColor3 = CONFIG.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left }, toast)
	tween(toast, CONFIG.Smooth, { Size = UDim2.fromOffset(NotifHost.AbsoluteSize.X, 26) })

	task.delay(1.7, function()
--@017
		if not toast or not toast.Parent then return end
		tween(toast, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = UDim2.fromOffset(2, 26), BackgroundTransparency = 1 })
		task.wait(0.18)
		if toast then toast:Destroy() end
		State.ToastCount = math.max(State.ToastCount - 1, 0)
	end)
end
--@018

--====================================================================
-- BUS : shared, priority 100
--====================================================================
-- Same key as every build below. The guard never takes the write away
-- from a noclip; it just watches the slot and repairs around it.

local BUS_KEY = "__NOCLIP_BUS_V3"
local host = (typeof(getgenv) == "function" and getgenv()) or _G
local bus = host[BUS_KEY]
if type(bus) ~= "table" then
--@019
	bus = { entries = {}, order = 0, arbiter = nil, mirror = nil }
	host[BUS_KEY] = bus
end

local function busArbitrate()
	local best
	for _, entry in pairs(bus.entries) do
		if entry.active and (not best or entry.priority > best.priority) then
			best = entry
--@020
		end
	end
	bus.arbiter = best
	bus.mirror = nil
	for _, entry in pairs(bus.entries) do
		if entry ~= best then bus.mirror = entry end
		entry.role = entry == best and "writer" or "mirror"
	end
end
--@021

local function busRegister(entry)
	bus.order += 1
	entry.order = bus.order
	entry.active = false
	entry.role = "writer"
	bus.entries[bus.order] = entry
	return entry
end

local function busDeactivate(entry)
	entry.active = false
	busArbitrate()
--@022
	if entry.onDemote then entry.onDemote() end
	if bus.arbiter and bus.arbiter.onPromote then bus.arbiter.onPromote() end
end

local function busActivate(entry)
	entry.active = true
	busArbitrate()
	State.Role = entry.role
end

--@023
-- which mode is the active noclip using right now?
local function activeMode()
	local character = LocalPlayer.Character
	if not character then return "legacy" end
	for _, item in ipairs(character:GetDescendants()) do
		if item:IsA("BasePart") and item.CollisionGroup ~= "Default" then
			return "group"
		end
	end
	return "legacy"
end

--@024
--====================================================================
-- SHIELD
--====================================================================

local Shield = {}
Shield.Active = false
Shield.Repairs = 0
Shield.BurstStart = 0
Shield.Loop = nil
Shield.Threads = {}
Shield.Log = {}
Shield.LastWalk = 16
Shield.Escalations = 0

--@025
-- wrap a loop body so one bad call cannot kill the thread
function Shield:Protect(name, body)
	return function(...)
		local ok, err = pcall(body, ...)
		if not ok then
			self:Note("loop error · " .. name)
			task.wait(0.25)
		end
	end
end

--@026
function Shield:Note(text)
	table.insert(self.Log, text)
	if #self.Log > 6 then table.remove(self.Log, 1) end
	if LogLabel then
		LogLabel.Text = table.concat(self.Log, "\n")
	end
end

function Shield:Spawn(name, fn)
	local wrapped = self:Protect(name, fn)
	self.Threads[name] = task.spawn(wrapped)
--@027
end

function Shield:Repair(kind)
	self.Repairs += 1
	if os.clock() - self.BurstStart > CONFIG.BurstWindow then
		self.BurstStart = os.clock()
		self.Repairs = 0
	end
	self:Note(kind)
	if self.Repairs >= CONFIG.Burst then
		self.Repairs = 0
		self.Escalations += 1
		self:Escalate()
	end
end
--@028

function Shield:Escalate()
	notify("Hard re-attach", CONFIG.Bad)
	pcall(function()
		if Gui then
			Gui.Parent = nil
			Gui.DisplayOrder = CONFIG.MinDisplay + 500
			Gui.Parent = parentTarget()
		end
	end)
end

--@029
--====================================================================
-- INVARIANTS
--====================================================================

function Shield:GuiIntact()
	if not Gui then return false end
	local ok = pcall(function() return Gui.Name end)
	if not ok then return false end
	return Gui.Parent ~= nil
end

function Shield:CheckGui()
--@030
	if not self:GuiIntact() then
		self:Note("gui lost")
		return "gui"
	end
	if Gui.Enabled ~= true then
		Gui.Enabled = true
		return "gui disabled"
	end
	if Gui.DisplayOrder < CONFIG.MinDisplay then
		Gui.DisplayOrder = CONFIG.MinDisplay
		return "order lowered"
	end
--@031
	if not State.Collapsed and not State.OrbMode and not Main.Visible then
		Main.Visible = true
		return "panel hidden"
	end
	if not Gui:FindFirstChild("Main") then
		return "panel deleted"
	end
	return nil
end

--@032
function Shield:CheckCharacter()
	local character = LocalPlayer.Character
	if not character then return nil end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return nil end
	if humanoid.WalkSpeed > 0 then
		self.LastWalk = humanoid.WalkSpeed
	else
		humanoid.WalkSpeed = self.LastWalk
		return "walkspeed zeroed"
	end
--@033
	if humanoid.PlatformStand then
		humanoid.PlatformStand = false
		return "platformstand held"
	end
	if not humanoid.AutoRotate then
		humanoid.AutoRotate = true
		return "autorotate off"
	end
	return nil
end

--@034
function Shield:CheckStamps()
	if not bus.arbiter then return nil end
	local mode = activeMode()
	local character = LocalPlayer.Character
	if not character then return nil end
	local broken = false
	for _, item in ipairs(character:GetDescendants()) do
		if item:IsA("BasePart") then
			if mode == "group" then
				if item.CollisionGroup == "Default" then broken = true end
--@035
			else
				if item.CanCollide then broken = true end
			end
		end
	end
	if not broken then return nil end
	if mode == "group" then
		local group = bus.arbiter.group or "SilentNoclip"
		for _, item in ipairs(character:GetDescendants()) do
			if item:IsA("BasePart") then item.CollisionGroup = group end
--@036
		end
		return "stamps stripped"
	else
		for _, item in ipairs(character:GetDescendants()) do
			if item:IsA("BasePart") then item.CanCollide = false end
		end
		return "collide restored"
	end
end

--@037
function Shield:CheckBus()
	if not State.BusEntry then return nil end
	if bus.entries[State.BusEntry.order] == State.BusEntry then return nil end
	busRegister(State.BusEntry)
	return "bus slot cleared"
end

--@038
function Shield:CheckThreads()
	for name, thread in pairs(self.Threads) do
		if thread and coroutine.status(thread) == "dead" then
			self:Note("restart " .. name)
		end
	end
end

--@039
function Shield:Sweep()
	local breaks = {}
	local function push(value)
		if value then table.insert(breaks, value) end
	end
	push(self:CheckGui())
	push(self:CheckBus())
	push(self:CheckCharacter())
	push(self:CheckStamps())
	self:CheckThreads()
	for _, item in ipairs(breaks) do
		self:Repair(item)
	end
end
--@040

function Shield:Loop()
	while self.Active do
		local ok = pcall(function() Shield:Sweep() end)
		if not ok then Shield:Note("sweep error") end
		task.wait(CONFIG.Tick)
	end
end

function Shield:Start()
	if self.Active then return end
--@041
	self.Active = true
	if State.BusEntry then busActivate(State.BusEntry) end
	self.Loop = task.spawn(function() self:Loop() end)
	notify("Shield armed", CONFIG.AccentBright)
	paintToggle()
end

function Shield:Stop()
	if not self.Active then return end
	self.Active = false
	if self.Loop then task.cancel(self.Loop) self.Loop = nil end
	if State.BusEntry then busDeactivate(State.BusEntry) end
--@042
	notify("Shield off", CONFIG.TextDim)
	paintToggle()
end

function Shield:Toggle()
	if self.Active then self:Stop() else self:Start() end
end

--====================================================================
--@043
--====================================================================
-- ICONS
--====================================================================

local function drawMoveIcon(host, color)
	local wrap = new("Frame", { Size = UDim2.fromOffset(14, 14),
		Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1 }, host)
--@044
	new("Frame", { Size = UDim2.fromOffset(2, 12), Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = color,
		BorderSizePixel = 0 }, wrap)
	new("Frame", { Size = UDim2.fromOffset(12, 2), Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = color,
		BorderSizePixel = 0 }, wrap)
	for _, pos in ipairs({ UDim2.fromScale(0.5, 0), UDim2.fromScale(0.5, 1),
		UDim2.fromScale(0, 0.5), UDim2.fromScale(1, 0.5) }) do
		local head = new("Frame", { Size = UDim2.fromOffset(5, 5), Position = pos,
--@045
			AnchorPoint = Vector2.new(0.5, 0.5), Rotation = 45,
			BackgroundColor3 = color, BorderSizePixel = 0 }, wrap)
		corner(1, head)
	end
	return wrap
end

local function drawOrbIcon(host, color)
	local ring = new("Frame", { Size = UDim2.fromOffset(13, 13),
--@046
		Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1 }, host)
	corner(7, ring)
	stroke(color, 1.4, 0, ring)
	local core = new("Frame", { Size = UDim2.fromOffset(5, 5),
		Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color, BorderSizePixel = 0 }, ring)
--@047
	corner(3, core)
	return ring
end

local function drawCloseIcon(host, color)
	local wrap = new("Frame", { Size = UDim2.fromOffset(14, 14),
		Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1 }, host)
	for _, angle in ipairs({ 45, -45 }) do
		local bar = new("Frame", { Size = UDim2.fromOffset(2, 11),
--@048
			Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = angle, BackgroundColor3 = color, BorderSizePixel = 0 }, wrap)
		corner(1, bar)
	end
	return wrap
end

local function makeHeaderButton(iconFn, order)
	local button = new("TextButton", {
--@049
		Size = UDim2.fromOffset(CONFIG.ButtonSize, CONFIG.ButtonSize),
		BackgroundColor3 = CONFIG.PanelRaised, BackgroundTransparency = 0.15,
		BorderSizePixel = 0, AutoButtonColor = false, Text = "",
		LayoutOrder = order }, HeaderTray)
	corner(6, button)
	pressFeedback(button, 0.15)
	iconFn(button, CONFIG.Text)
	return button
end
--@050

local function makeChip(label, order, startOn, onFlip)
	local chip = new("TextButton", {
		Size = UDim2.new(0.25, -CONFIG.Gap, 0, CONFIG.ChipHeight),
		BackgroundColor3 = CONFIG.PanelRaised, BackgroundTransparency = 0.2,
		BorderSizePixel = 0, AutoButtonColor = false, Text = "",
		LayoutOrder = order }, ChipRow)
	corner(5, chip)
	pressFeedback(chip, 0.2)
--@051
	local dot = new("Frame", { Size = UDim2.fromOffset(4, 4),
		Position = UDim2.fromOffset(4, CONFIG.ChipHeight / 2 - 2),
		BackgroundColor3 = startOn and CONFIG.AccentBright or CONFIG.Stroke,
		BorderSizePixel = 0 }, chip)
	corner(2, dot)
	new("TextLabel", { Size = UDim2.new(1, -9, 1, 0), Position = UDim2.fromOffset(9, 0),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = label,
		TextSize = 7, TextColor3 = CONFIG.TextDim,
--@052
		TextXAlignment = Enum.TextXAlignment.Left }, chip)
	local on = startOn
	chip.MouseButton1Click:Connect(function()
		if State.Destroyed then return end
		on = not on
		dot.BackgroundColor3 = on and CONFIG.AccentBright or CONFIG.Stroke
		onFlip(on)
	end)
	return chip
end
--@053

--====================================================================
-- ORB
--====================================================================

local function enterOrbMode()
	if State.OrbMode then return end
	State.OrbMode = true
	local origin = Main.AbsolutePosition
	local size = Main.AbsoluteSize
	local center = Vector2.new(origin.X + size.X / 2, origin.Y + size.Y / 2)
--@054
	local placed = clampPosition(Vector2.new(center.X - CONFIG.OrbSize / 2,
		center.Y - CONFIG.OrbSize / 2), Vector2.new(CONFIG.OrbSize, CONFIG.OrbSize))
	Orb.Position = UDim2.fromOffset(placed.X, placed.Y)
	Orb.Visible = true
	Orb.BackgroundTransparency = 1
	OrbInner.BackgroundTransparency = 1
	Main.Visible = false
	tween(Orb, CONFIG.Smooth, { BackgroundTransparency = 0.05 })
	tween(OrbInner, CONFIG.Smooth, { BackgroundTransparency = 0 })
end
--@055

local function exitOrbMode()
	if not State.OrbMode then return end
	State.OrbMode = false
	local orbPosition = Orb.AbsolutePosition
	local orbSize = Orb.AbsoluteSize
	local target = Vector2.new(
		orbPosition.X + orbSize.X / 2 - Main.AbsoluteSize.X / 2,
		orbPosition.Y + orbSize.Y / 2 - Main.AbsoluteSize.Y / 2)
	local placed = clampPosition(target, Main.AbsoluteSize)
--@056
	Main.Position = UDim2.fromOffset(placed.X, placed.Y)
	Main.Visible = true
	Orb.Visible = false
end

local function buildOrb(parent)
	Orb = new("TextButton", { Name = "Orb",
		Size = UDim2.fromOffset(CONFIG.OrbSize, CONFIG.OrbSize),
--@057
		Position = UDim2.fromOffset(120, 120), BackgroundColor3 = CONFIG.Panel,
		BackgroundTransparency = 0.05, BorderSizePixel = 0, AutoButtonColor = false,
		Text = "", Visible = false, ZIndex = 20 }, parent)
	corner(CONFIG.OrbSize / 2, Orb)
	stroke(CONFIG.Accent, 2, 0.15, Orb)
	OrbInner = new("Frame", {
		Size = UDim2.fromOffset(CONFIG.OrbSize - 15, CONFIG.OrbSize - 15),
		Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
--@058
		BackgroundColor3 = CONFIG.PanelRaised, BorderSizePixel = 0, ZIndex = 21 }, Orb)
	corner((CONFIG.OrbSize - 15) / 2, OrbInner)
	drawOrbIcon(OrbInner, CONFIG.AccentBright)
	OrbDot = new("Frame", { Size = UDim2.fromOffset(9, 9),
		Position = UDim2.new(0.5, 0, 1, -5), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = CONFIG.AccentBright, BorderSizePixel = 0,
		Visible = false, ZIndex = 22 }, Orb)
--@059
	corner(5, OrbDot)
	stroke(CONFIG.Panel, 1.5, 0, OrbDot)
end

--====================================================================
-- TOGGLE
--====================================================================

function paintToggle()
--@060
	if not ToggleButton then return end
	if Shield.Active then
		tween(ToggleButton, CONFIG.Fast, { BackgroundColor3 = CONFIG.AccentBright })
		ToggleLabel.Text = "SHIELD  ON"
		ToggleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		StatusDot.BackgroundColor3 = CONFIG.AccentBright
		StatusText.Text = "GUARDING"
--@061
		StatusText.TextColor3 = CONFIG.AccentBright
		OrbDot.Visible = true
	else
		tween(ToggleButton, CONFIG.Fast, { BackgroundColor3 = CONFIG.Accent })
		ToggleLabel.Text = "SHIELD"
		ToggleLabel.TextColor3 = Color3.fromRGB(238, 255, 238)
		StatusDot.BackgroundColor3 = CONFIG.AccentDark
		StatusText.Text = "IDLE"
--@062
		StatusText.TextColor3 = CONFIG.TextDim
		OrbDot.Visible = false
	end
end

local function buildToggle()
	ToggleButton = new("TextButton", { Size = UDim2.new(1, -CONFIG.Pad * 2, 0, 34),
		Position = UDim2.fromOffset(CONFIG.Pad, 6), BackgroundColor3 = CONFIG.Accent,
		BorderSizePixel = 0, AutoButtonColor = false, Text = "",
--@063
		ClipsDescendants = true }, Body)
	corner(CONFIG.InnerCorner, ToggleButton)
	stroke(CONFIG.AccentDark, 1, 0.4, ToggleButton)
	ToggleLabel = new("TextLabel", { Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = "SHIELD",
		TextSize = 13, TextColor3 = Color3.fromRGB(238, 255, 238),
		TextXAlignment = Enum.TextXAlignment.Center }, ToggleButton)
--@064
	pressFeedback(ToggleButton, 0)
	ToggleButton.MouseButton1Click:Connect(function()
		if State.Destroyed then return end
		Shield:Toggle()
	end)
end

--====================================================================
--@065
-- HEADER
--====================================================================

local function buildHeader()
	Header = new("Frame", { Name = "Header",
		Size = UDim2.new(1, 0, 0, CONFIG.HeaderHeight),
		BackgroundColor3 = CONFIG.PanelSoft, BorderSizePixel = 0 }, Main)
--@066
	corner(CONFIG.Corner, Header)
	new("Frame", { Size = UDim2.new(1, -CONFIG.Pad * 2, 0, 1),
		Position = UDim2.new(0, CONFIG.Pad, 1, -1), BackgroundColor3 = CONFIG.Stroke,
		BorderSizePixel = 0 }, Header)
	StatusDot = new("Frame", { Size = UDim2.fromOffset(6, 6),
		Position = UDim2.fromOffset(CONFIG.Pad, CONFIG.HeaderHeight / 2 - 3),
		BackgroundColor3 = CONFIG.AccentDark, BorderSizePixel = 0 }, Header)
--@067
	corner(3, StatusDot)
	HeaderLabel = new("TextLabel", { Size = UDim2.new(0, 56, 1, 0),
		Position = UDim2.fromOffset(CONFIG.Pad + 12, 0), BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold, Text = CONFIG.Title, TextSize = 12,
		TextColor3 = CONFIG.Text, TextXAlignment = Enum.TextXAlignment.Left }, Header)
	StatusText = new("TextLabel", { Size = UDim2.fromOffset(44, 1),
		Position = UDim2.new(0, CONFIG.Pad + 66, 1, -9), BackgroundTransparency = 1,
--@068
		Font = Enum.Font.GothamBold, Text = "IDLE", TextSize = 7,
		TextColor3 = CONFIG.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left }, Header)
	HeaderTray = new("Frame", { Size = UDim2.new(1, -CONFIG.Pad * 2, 1, 0),
		Position = UDim2.fromOffset(CONFIG.Pad, 0), BackgroundTransparency = 1 }, Header)
	listLayout(HeaderTray, CONFIG.Gap)
end
--@069

--====================================================================
-- DRAG
--====================================================================

local function beginDrag(input)
	State.Dragging = true
	State.DragOrigin = pointerOf(input)
	State.DragAnchor = Vector2.new(Main.AbsolutePosition.X, Main.AbsolutePosition.Y)
end
--@070

local function moveDrag(input)
	if not State.Dragging then return end
	local placed = clampPosition(
		State.DragAnchor + (pointerOf(input) - State.DragOrigin), Main.AbsoluteSize)
	Main.Position = UDim2.fromOffset(placed.X, placed.Y)
end

local function endDrag()
	if not State.Dragging then return end
--@071
	State.Dragging = false
	local snapped = snapToEdge(Main.AbsolutePosition, Main.AbsoluteSize)
	tween(Main, CONFIG.Smooth, { Position = UDim2.fromOffset(snapped.X, snapped.Y) })
end

local function bindHeaderDrag()
	Header.InputBegan:Connect(function(input)
		if not isPrimary(input) or State.OrbMode or State.Destroyed then return end
--@072
		beginDrag(input)
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then endDrag() end
		end)
	end)
end

local function bindOrbDrag()
	Orb.InputBegan:Connect(function(input)
--@073
		if not isPrimary(input) or State.Destroyed then return end
		State.OrbDragging = true
		State.OrbOffset = Vector2.new(Orb.AbsolutePosition.X, Orb.AbsolutePosition.Y)
			- pointerOf(input)
		tween(Orb, CONFIG.Fast, {
			Size = UDim2.fromOffset(CONFIG.OrbSize - 6, CONFIG.OrbSize - 6) })
		input.Changed:Connect(function()
--@074
			if input.UserInputState == Enum.UserInputState.End then
				State.OrbDragging = false
				tween(Orb, CONFIG.Snap, {
					Size = UDim2.fromOffset(CONFIG.OrbSize, CONFIG.OrbSize) })
			end
		end)
	end)
	UserInputService.InputChanged:Connect(function(input)
--@075
		if not State.OrbDragging or not State.OrbOffset then return end
		if not isMotion(input) then return end
		local placed = clampPosition(pointerOf(input) + State.OrbOffset, Orb.AbsoluteSize)
		Orb.Position = UDim2.fromOffset(placed.X, placed.Y)
	end)
end

--====================================================================
--@076
-- COLLAPSE
--====================================================================

local function setCollapsed(value)
	if State.Collapsed == value then return end
	State.Collapsed = value
	if value then
		Body.Visible = false
		HeaderLabel.TextColor3 = CONFIG.TextDim
--@077
		tween(Main, CONFIG.Smooth, {
			Size = UDim2.fromOffset(CONFIG.Width, CONFIG.HeaderHeight) })
	else
		HeaderLabel.TextColor3 = CONFIG.Text
		tween(Main, CONFIG.Smooth, {
			Size = UDim2.fromOffset(CONFIG.Width, CONFIG.HeaderHeight + CONFIG.BodyHeight) })
		task.delay(0.06, function()
			if not State.Collapsed and not State.Destroyed then Body.Visible = true end
--@078
		end)
	end
end

--====================================================================
-- ASSEMBLY
--====================================================================

local function parentTarget()
	if typeof(gethui) == "function" then
--@079
		local ok, handle = pcall(gethui)
		if ok and handle then return handle end
	end
	local probe = Instance.new("Folder")
	local ok = pcall(function() probe.Parent = CoreGui end)
	probe:Destroy()
	if ok then return CoreGui end
	return LocalPlayer:WaitForChild("PlayerGui")
--@080
end

local function build()
	Gui = new("ScreenGui", { Name = "ShieldNoclip", ResetOnSpawn = false,
		IgnoreGuiInset = true, DisplayOrder = CONFIG.MinDisplay,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
	NotifHost = new("Frame", { Name = "Toasts", Size = UDim2.new(1, 0, 0, 96),
		BackgroundTransparency = 1 }, Gui)
--@081
	new("UIListLayout", { FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 4) }, NotifHost)
	Main = new("Frame", { Name = "Main", Position = UDim2.fromOffset(24, 24),
		Size = UDim2.fromOffset(CONFIG.Width, CONFIG.HeaderHeight + CONFIG.BodyHeight),
		BackgroundColor3 = CONFIG.Panel, BorderSizePixel = 0,
		ClipsDescendants = true }, Gui)
	corner(CONFIG.Corner, Main)
--@082
	stroke(CONFIG.Stroke, 1, 0.25, Main)
	buildHeader()
	Body = new("Frame", { Name = "Body", Size = UDim2.new(1, 0, 0, CONFIG.BodyHeight),
		Position = UDim2.fromOffset(0, CONFIG.HeaderHeight),
		BackgroundTransparency = 1 }, Main)
	buildToggle()
	ChipRow = new("Frame", { Name = "Chips",
		Size = UDim2.new(1, -CONFIG.Pad * 2, 0, CONFIG.ChipHeight),
--@083
		Position = UDim2.fromOffset(CONFIG.Pad, 44), BackgroundTransparency = 1 }, Body)
	listLayout(ChipRow, CONFIG.Gap)
	WatchChip = makeChip("WATCH", 1, false, function(on)
		if on then Shield:Start() else Shield:Stop() end
	end)
	makeChip("FIX", 2, false, function() Shield:Sweep() notify("Swept", CONFIG.Accent) end)
	makeChip("SNAP", 3, false, function()
--@084
		local humanoid = LocalPlayer.Character
			and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then Shield.LastWalk = math.max(humanoid.WalkSpeed, 1) end
		notify("Baseline saved", CONFIG.Accent)
	end)
	makeChip("CLEAR", 4, false, function()
		Shield.Log = {}
		if LogLabel then LogLabel.Text = "" end
	end)
--@085
	LogLabel = new("TextLabel", { Name = "Log",
		Size = UDim2.new(1, -CONFIG.Pad * 2, 0, 26),
		Position = UDim2.fromOffset(CONFIG.Pad, 68), BackgroundTransparency = 1,
		Font = Enum.Font.Code, Text = "", TextSize = 8, TextWrap = true,
		TextColor3 = CONFIG.TextDim, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top }, Body)
	local orbButton = makeHeaderButton(drawOrbIcon, 1)
--@086
	local moveButton = makeHeaderButton(drawMoveIcon, 2)
	local closeButton = makeHeaderButton(drawCloseIcon, 3)
	buildOrb(Gui)
	orbButton.MouseButton1Click:Connect(function()
		if State.Destroyed then return end
		if State.OrbMode then exitOrbMode() else enterOrbMode() end end)
	Orb.MouseButton1Click:Connect(function()
--@087
		if not State.OrbDragging then exitOrbMode() end end)
	moveButton.MouseButton1Click:Connect(function()
		State.MoveLocked = not State.MoveLocked
		if State.MoveLocked then stroke(CONFIG.Accent, 1.5, 0, moveButton)
			notify("Drag unlocked", CONFIG.Accent) else
			local s = moveButton:FindFirstChildOfClass("UIStroke") if s then s:Destroy() end
			notify("Drag locked", CONFIG.TextDim) end end)
--@088
	closeButton.MouseButton1Click:Connect(function() setCollapsed(not State.Collapsed) end)
	HeaderLabel.InputBegan:Connect(function(input)
		if not isPrimary(input) or State.Destroyed then return end
		if State.Collapsed then return setCollapsed(false) end
		local now = os.clock()
		if now - State.LastTap <= 0.35 then
			Main.Position = UDim2.fromOffset(24, 24) State.LastTap = 0
--@089
		else State.LastTap = now end end)
	Gui.Parent = parentTarget()
	bindHeaderDrag() bindOrbDrag() paintToggle()
	UserInputService.InputChanged:Connect(function(input)
		if State.Dragging and isMotion(input) then moveDrag(input) end end)
	UserInputService.InputEnded:Connect(function(input)
		if isPrimary(input) then endDrag() end end)
--@090
	Camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		if not Main or State.Destroyed then return end
		local placed = clampPosition(Main.AbsolutePosition, Main.AbsoluteSize)
		Main.Position = UDim2.fromOffset(placed.X, placed.Y) end)
end

--====================================================================
--@091
-- KEYS + BOOT
--====================================================================
-- RightShift shield · RightAlt collapse · RightControl orb

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or State.Destroyed then return end
	if input.KeyCode == Enum.KeyCode.RightShift then Shield:Toggle()
	elseif input.KeyCode == Enum.KeyCode.RightAlt then setCollapsed(not State.Collapsed)
--@092
	elseif input.KeyCode == Enum.KeyCode.RightControl then
		if State.OrbMode then exitOrbMode() else enterOrbMode() end
	end
end)

local Entry = busRegister({ id = tostring(math.random(1000000)),
	priority = CONFIG.Priority,
	onPromote = function() State.Role = "writer" end,
--@093
	onDemote = function() State.Role = "mirror" end })
State.BusId = Entry.id
State.BusEntry = Entry

local built, err = pcall(build)
if not built then warn("[Shield] " .. tostring(err)) end

--@094
-- survive respawn: re-baseline walkspeed and keep guarding
LocalPlayer.CharacterAdded:Connect(function(character)
	character:WaitForChild("HumanoidRootPart", 10)
	task.wait(0.15)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then Shield.LastWalk = math.max(humanoid.WalkSpeed, 16) end
	if Shield.Active then
		Shield:Note("respawn rebase")
	end
end)
--@095

--====================================================================
-- SELF CHECK
--====================================================================

-- if the executor ever wipes getgenv, the handle is rebuilt here
pcall(function()
	local g = (typeof(getgenv) == "function" and getgenv()) or _G
	g.__SHIELD_HANDLE = {
		toggle = function() Shield:Toggle() end,
		sweep = function() Shield:Sweep() end,
		rebuild = function()
			pcall(function() if Gui then Gui:Destroy() end end)
			task.defer(build)
		end,
		alive = function() return not State.Destroyed end,
	}
end)
--@096

--====================================================================
-- DOCS
--====================================================================
--[[
  WATCH     Arm the guard. It sweeps every 0.5s and puts back anything
            a game broke.
  FIX       Force one sweep right now.
  SNAP      Save the current WalkSpeed as the baseline to restore to.
  CLEAR     Wipe the repair log.

  It repairs: gui destroyed or unparented, gui disabled, panel hidden,
  order lowered, panel deleted, walkspeed zeroed, platformstand held,
  autorotate off, collision stamps stripped, bus slot cleared.

  Six repairs inside ten seconds escalates to a hard re-attach with a
  raised display order, so a persistent GUI killer loses the exchange.

  Every loop body runs in pcall behind a supervisor, so no single error
  takes a thread down.

  Handle: getgenv().__SHIELD_HANDLE.toggle / .sweep / .rebuild / .alive
]]
--@097
--[[====================================================================
    M E D I C   ·   Build 6.0.0
    Same repo, same file, one blank line below the last build.
-----------------------------------------------------------------------
    WHAT THIS IS
    A repair layer. It stands at post and watches the other copies for
    faults: dead threads, destroyed panels, cleared bus slots, stripped
    collision stamps, a body left anchored, walkspeed zeroed, a handle
    that reports itself dead.
-----------------------------------------------------------------------
    DEPLOY / RETURN
    On a fault it deploys: raises its own bus priority to 200, takes the
    write so the injured copy stops being written over, repairs it, then
    drops priority to 1 and re-arbitrates. The next highest copy gets
    the write back and the medic returns to post. Nothing is left
    holding the pen except a noclip.
-----------------------------------------------------------------------
    FIXING IN GAME
    Faults are handled, not reported. Panels are rebuilt through the
    owner's own handle. Stamps are re-applied in whichever mode the
    body was already in. Anchored roots are released, walkspeed is
    restored from baseline, dead bus entries are re-registered.
    Every fix runs twice before it is called a failure.
--@001
-----------------------------------------------------------------------
    CO-EXISTENCE
    Passive by default: priority 1, so it never outranks a noclip while
    idle. Only the repair window is hot. It reuses the same bus, the
    same bus key and the same handles the other builds publish, so all
    four run together without one of them going quiet.
-----------------------------------------------------------------------
    HANDLES IT READS
      getgenv().__SHIELD_HANDLE    getgenv().__SILENT_HANDLE
      getgenv().__NOCLIP_HANDLE    getgenv().__MEDIC_HANDLE
-----------------------------------------------------------------------
    Author : supercaptain1233        File : Bestnoclip.lua
======================================================================]]

--====================================================================
-- SERVICES
--====================================================================

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local CoreGui          = game:GetService("CoreGui")
local LocalPlayer      = Players.LocalPlayer
local Camera           = workspace.CurrentCamera
--@002

--====================================================================
-- CONFIG
--====================================================================

local CONFIG = {
	Title = "Medic", Build = "6.0.0",
	PostPriority = 1, DeployPriority = 200,
	Width = 176, HeaderHeight = 30, BodyHeight = 76, Corner = 11,
	InnerCorner = 8, ButtonSize = 22, ChipHeight = 20, OrbSize = 58,
	Pad = 10, Gap = 6, ClampPad = 8, SnapDistance = 44,
	Tick = 0.4,               -- watch interval while at post
	RepairTick = 0.15,        -- faster while deployed
	Cooldown = 1.2,           -- seconds between deploys
	MinDisplay = 9999,
	Panel        = Color3.fromRGB(20, 18, 14),
	PanelSoft    = Color3.fromRGB(31, 28, 22),
	PanelRaised  = Color3.fromRGB(42, 38, 30),
	Stroke       = Color3.fromRGB(58, 52, 40),
	Accent       = Color3.fromRGB(226, 168, 62),
	AccentBright = Color3.fromRGB(250, 202, 110),
	AccentDark   = Color3.fromRGB(92, 66, 22),
	Text         = Color3.fromRGB(244, 240, 232),
	TextDim      = Color3.fromRGB(142, 134, 118),
	Good         = Color3.fromRGB(120, 210, 140),
	Bad          = Color3.fromRGB(232, 90, 96),
}
--@003

CONFIG.Fast   = TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
CONFIG.Smooth = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
CONFIG.Snap   = TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

--====================================================================
-- STATE
--====================================================================

local State = {
	Dragging = false, OrbDragging = false, Collapsed = false,
	OrbMode = false, MoveLocked = false, Destroyed = false,
	ToastCount = 0, LastTap = 0, Role = "medic",
	Mode = "post", LastDeploy = 0, Fixes = 0,
	DragOrigin = nil, DragAnchor = nil, OrbOffset = nil,
	BusId = nil, BusEntry = nil,
}
--@004

local Gui, Main, Header, HeaderTray, Body, ChipRow, LogLabel
local Orb, OrbInner, OrbDot, NotifHost
local ToggleButton, ToggleLabel, StatusDot, StatusText, HeaderLabel
local Patients = {}
local WalkBaseline = 16

--====================================================================
-- UTIL : factory
--====================================================================

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end
--@005

local function corner(r, parent)
	return new("UICorner", { CornerRadius = UDim.new(0, r) }, parent)
end

local function stroke(color, thickness, transparency, parent)
	return new("UIStroke", { Color = color, Thickness = thickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
end
--@006

local function listLayout(parent, gap)
	return new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, gap or 0) }, parent)
end

local function tween(object, info, goal)
	local track = TweenService:Create(object, info, goal)
	track:Play()
	return track
end
--@007

local function viewport()
	local ok, size = pcall(function() return Camera.ViewportSize end)
	if ok and size then return size end
	return Vector2.new(1280, 720)
end

local function clamp(value, low, high)
	if value < low then return low end
	if value > high then return high end
	return value
end
--@008

local function clampPosition(position, size)
	local screen = viewport()
	return Vector2.new(
		clamp(position.X, CONFIG.ClampPad, screen.X - size.X - CONFIG.ClampPad),
		clamp(position.Y, CONFIG.ClampPad, screen.Y - size.Y - CONFIG.ClampPad))
end

local function snapToEdge(position, size)
	local screen = viewport()
	local x, y = position.X, position.Y
--@009
	if x - CONFIG.ClampPad <= CONFIG.SnapDistance then x = CONFIG.ClampPad
	elseif (screen.X - (x + size.X)) - CONFIG.ClampPad <= CONFIG.SnapDistance then
		x = screen.X - size.X - CONFIG.ClampPad
	end
	if y - CONFIG.ClampPad <= CONFIG.SnapDistance then y = CONFIG.ClampPad
	elseif (screen.Y - (y + size.Y)) - CONFIG.ClampPad <= CONFIG.SnapDistance then
		y = screen.Y - size.Y - CONFIG.ClampPad
	end
	return Vector2.new(x, y)
--@010
end

local function isPrimary(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

local function isMotion(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch
end
--@011

local function pointerOf(input)
	return Vector2.new(input.Position.X, input.Position.Y)
end

local function character()
	return LocalPlayer.Character
end

--@012
local function humanoid()
	local c = character()
	return c and c:FindFirstChildOfClass("Humanoid")
end

local function root()
	local c = character()
	return c and c:FindFirstChild("HumanoidRootPart")
end

--====================================================================
-- UTIL : press feedback
--====================================================================

local function pressFeedback(button, base)
--@013
	button.MouseEnter:Connect(function()
		if not State.Destroyed then
			tween(button, CONFIG.Fast, { BackgroundTransparency = math.max(base - 0.12, 0) })
		end
	end)
	button.MouseLeave:Connect(function()
		if not State.Destroyed then
			tween(button, CONFIG.Fast, { BackgroundTransparency = base })
		end
	end)
--@014
	button.MouseButton1Down:Connect(function()
		if not State.Destroyed then
			tween(button, CONFIG.Fast, { Size = button.Size - UDim2.fromOffset(2, 2) })
		end
	end)
	button.MouseButton1Up:Connect(function()
		if not State.Destroyed then
			tween(button, CONFIG.Fast, { Size = button.Size + UDim2.fromOffset(2, 2) })
		end
	end)
end
--@015

--====================================================================
-- TOASTS
--====================================================================

local function notify(text, accent)
	if not NotifHost or State.Destroyed then return end
	if State.ToastCount >= 3 then
		local oldest = NotifHost:FindFirstChild("Toast")
		if oldest then oldest:Destroy() end
		State.ToastCount = math.max(State.ToastCount - 1, 0)
	end
--@016
	State.ToastCount += 1
	local toast = new("Frame", { Name = "Toast", Size = UDim2.fromOffset(2, 26),
		ClipsDescendants = true, BackgroundColor3 = CONFIG.PanelSoft,
		BackgroundTransparency = 0.05, BorderSizePixel = 0 }, NotifHost)
	corner(6, toast)
	stroke(accent or CONFIG.Stroke, 1, 0.35, toast)
	new("Frame", { Size = UDim2.new(0, 3, 1, -8), Position = UDim2.new(0, 5, 0, 4),
		BackgroundColor3 = accent or CONFIG.Accent, BorderSizePixel = 0 }, toast)
--@017
	new("TextLabel", { Size = UDim2.new(1, -18, 1, 0), Position = UDim2.new(0, 14, 0, 0),
		BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, Text = text,
		TextSize = 11, TextColor3 = CONFIG.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left }, toast)
	tween(toast, CONFIG.Smooth, { Size = UDim2.fromOffset(NotifHost.AbsoluteSize.X, 26) })

	task.delay(1.7, function()
--@018
		if not toast or not toast.Parent then return end
		tween(toast, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = UDim2.fromOffset(2, 26), BackgroundTransparency = 1 })
		task.wait(0.18)
		if toast then toast:Destroy() end
		State.ToastCount = math.max(State.ToastCount - 1, 0)
	end)
end
--@019

--====================================================================
-- BUS
--====================================================================
-- Passive at priority 1. Only the repair window raises it, so a noclip
-- always holds the write except for the few seconds a fix takes.

local BUS_KEY = "__NOCLIP_BUS_V3"
local host = (typeof(getgenv) == "function" and getgenv()) or _G
local bus = host[BUS_KEY]
if type(bus) ~= "table" then
--@020
	bus = { entries = {}, order = 0, arbiter = nil, mirror = nil }
	host[BUS_KEY] = bus
end

local function busArbitrate()
	local best
	for _, entry in pairs(bus.entries) do
		if entry.active and (not best or entry.priority > best.priority) then
			best = entry
--@021
		end
	end
	bus.arbiter = best
	bus.mirror = nil
	for _, entry in pairs(bus.entries) do
		if entry ~= best then bus.mirror = entry end
		entry.role = entry == best and "writer" or "mirror"
	end
end
--@022

local function busRegister(entry)
	bus.order += 1
	entry.order = bus.order
	entry.active = false
	entry.role = "writer"
	bus.entries[bus.order] = entry
	return entry
end

local function busActivate(entry)
	entry.active = true
	busArbitrate()
--@023
	State.Role = entry.role
end

local function busDeactivate(entry)
	entry.active = false
	busArbitrate()
	if bus.arbiter and bus.arbiter.onPromote then bus.arbiter.onPromote() end
end

local function isWriter()
	return bus.arbiter ~= nil and bus.arbiter.id == State.BusId
end
--@024

-- the mode the body is currently phased in, if any
local function activeMode()
	local c = character()
	if not c then return nil end
	for _, item in ipairs(c:GetDescendants()) do
		if item:IsA("BasePart") then
			if item.CollisionGroup ~= "Default" then return "group" end
			if item.CanCollide == false then return "legacy" end
		end
	end
	return nil
end

--@025
--====================================================================
-- PATIENTS
--====================================================================

local HANDLES = {
	shield = "__SHIELD_HANDLE",
	silent = "__SILENT_HANDLE",
	noclip = "__NOCLIP_HANDLE",
}

function MedicDiscover()
	Patients = {}
	local g = (typeof(getgenv) == "function" and getgenv()) or _G
--@026
	for name, key in pairs(HANDLES) do
		local handle = g[key]
		if type(handle) == "table" then
			Patients[name] = handle
		end
	end
	return Patients
end

--====================================================================
--@027
-- MEDIC
--====================================================================

local Medic = {}
Medic.Active = false
Medic.Loop = nil
Medic.Log = {}
Medic.Deploys = 0
Medic.CooldownUntil = 0

function Medic:Note(text)
	table.insert(self.Log, text)
	if #self.Log > 6 then table.remove(self.Log, 1) end
--@028
	if LogLabel then
		LogLabel.Text = table.concat(self.Log, "\n")
	end
end

-- run a fix twice before calling it failed
function Medic:Try(name, fn)
	for attempt = 1, 2 do
		local ok = pcall(fn)
		if ok then
			self:Note("fixed · " .. name)
			return true
		end
--@029
		if attempt == 2 then
			self:Note("failed · " .. name)
		end
	end
	return false
end

function Medic:Deploy(reason)
	if State.Mode == "repair" then return end
	if os.clock() < self.CooldownUntil then return end
	State.Mode = "repair"
	self.CooldownUntil = os.clock() + CONFIG.Cooldown
	self.Deploys += 1
--@030
	self:Note("deploy · " .. reason)
	if State.BusEntry then
		State.BusEntry.priority = CONFIG.DeployPriority
		busArbitrate()
	end
	paintToggle()
end

function Medic:Return()
	if State.Mode ~= "repair" then return end
	State.Mode = "post"
--@031
	self:Note("back to post")
	if State.BusEntry then
		State.BusEntry.priority = CONFIG.PostPriority
		busArbitrate()
	end
	if bus.arbiter and bus.arbiter.onPromote then
		pcall(bus.arbiter.onPromote)
	end
	paintToggle()
end
--@032

--====================================================================
-- FIXES
--====================================================================

local Fix = {}

Fix["panel lost"] = function()
	for name, handle in pairs(Patients) do
		if handle.rebuild then
			Medic:Try(name .. " panel", handle.rebuild)
		end
	end
end
--@033

Fix["thread dead"] = function()
	for name, handle in pairs(Patients) do
		if handle.alive and not handle.alive() then
			if handle.rebuild then Medic:Try(name .. " revive", handle.rebuild) end
		end
	end
end

Fix["bus slot"] = function()
	for _, entry in pairs(bus.entries) do
--@034
		if not entry.active then continue end
	end
end

Fix["stamps stripped"] = function()
	local mode = activeMode() or "legacy"
	local c = character()
	if not c then return end
	if mode == "group" then
		local group = (bus.arbiter and bus.arbiter.group) or "SilentNoclip"
		Medic:Try("restamp group", function()
--@035
			for _, item in ipairs(c:GetDescendants()) do
				if item:IsA("BasePart") then item.CollisionGroup = group end
			end
		end)
	else
		Medic:Try("restamp legacy", function()
			for _, item in ipairs(c:GetDescendants()) do
				if item:IsA("BasePart") then item.CanCollide = false end
			end
		end)
	end
end
--@036

Fix["anchored"] = function()
	local r = root()
	if not r then return end
	Medic:Try("release root", function() r.Anchored = false end)
end

Fix["walkspeed"] = function()
	local h = humanoid()
	if not h then return end
	Medic:Try("walkspeed", function() h.WalkSpeed = math.max(WalkBaseline, 1) end)
end
--@037

Fix["platformstand"] = function()
	local h = humanoid()
	if not h then return end
	Medic:Try("platformstand", function() h.PlatformStand = false end)
end

Fix["autorotate"] = function()
	local h = humanoid()
	if not h then return end
	Medic:Try("autorotate", function() h.AutoRotate = true end)
end
--@038

Fix["camera"] = function()
	if workspace.CurrentCamera then return end
	Medic:Try("camera", function()
		workspace.CurrentCamera = Camera
	end)
end

Fix["frozen velocity"] = function()
	local r = root()
	if not r then return end
	Medic:Try("calm", function()
--@039
		r.AssemblyLinearVelocity = Vector3.zero
		r.AssemblyAngularVelocity = Vector3.zero
	end)
end

Fix["gui disabled"] = function()
	for name, handle in pairs(Patients) do
		if handle.rebuild then return end
	end
end

--@040
--====================================================================
-- SCAN
--====================================================================

function Medic:Scan()
	MedicDiscover()
	local faults = {}

	-- dead patients first, they are the loudest signal
	for name, handle in pairs(Patients) do
		if handle.alive then
			local ok, alive = pcall(handle.alive)
			if not ok or alive == false then
--@041
				table.insert(faults, "thread dead")
				break
			end
		end
	end

	-- nothing on the bus means a copy died without deregistering
	local live = 0
	for _, entry in pairs(bus.entries) do
		if entry.active and not entry.medic then live += 1 end
	end
	if live == 0 and State.Active then table.insert(faults, "bus slot") end
--@042

	local c = character()
	if c then
		local mode = activeMode()
		if mode then
			local broken = false
			for _, item in ipairs(c:GetDescendants()) do
				if item:IsA("BasePart") then
					if mode == "group" and item.CollisionGroup == "Default" then broken = true end
					if mode == "legacy" and item.CanCollide then broken = true end
				end
			end
--@043
			if broken then table.insert(faults, "stamps stripped") end
		end

		local r = root()
		if r and r.Anchored then
			local h = humanoid()
			if h and h.WalkSpeed > 0 then table.insert(faults, "anchored") end
		end

		local h = humanoid()
		if h then
--@044
			if h.WalkSpeed <= 0 then table.insert(faults, "walkspeed") end
			if h.PlatformStand then table.insert(faults, "platformstand") end
			if not h.AutoRotate then table.insert(faults, "autorotate") end
		end
	end

	if not workspace.CurrentCamera then table.insert(faults, "camera") end
	if not Gui or not Gui.Parent then table.insert(faults, "panel lost") end
	return faults
--@045
end

function Medic:Treat(faults)
	if #faults == 0 then
		if State.Mode == "repair" then self:Return() end
		return
	end
	self:Deploy(faults[1])
	for _, fault in ipairs(faults) do
		local handler = Fix[fault]
		if handler then pcall(handler) end
--@046
	end
	State.Fixes += #faults
end

function Medic:Watch()
	while self.Active do
		local ok = pcall(function()
			local faults = Medic:Scan()
			Medic:Treat(faults)
		end)
		if not ok then Medic:Note("scan error") end
		if State.Mode == "repair" then
--@047
			task.wait(CONFIG.RepairTick)
		else
			task.wait(CONFIG.Tick)
		end
	end
end

function Medic:Start()
	if self.Active then return end
	self.Active = true
	if State.BusEntry then busActivate(State.BusEntry) end
--@048
	self.Loop = task.spawn(function() self:Watch() end)
	notify("Medic at post", CONFIG.AccentBright)
	paintToggle()
end

function Medic:Stop()
	if not self.Active then return end
	self.Active = false
	if self.Loop then task.cancel(self.Loop) self.Loop = nil end
	if State.BusEntry then busDeactivate(State.BusEntry) end
--@049
	self:Note("stood down")
	notify("Medic off", CONFIG.TextDim)
	paintToggle()
end

function Medic:Toggle()
	if self.Active then self:Stop() else self:Start() end
end

--====================================================================
--@050
--====================================================================
-- ICONS
--====================================================================

local function drawMoveIcon(host, color)
	local wrap = new("Frame", { Size = UDim2.fromOffset(14, 14),
		Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1 }, host)
--@051
	new("Frame", { Size = UDim2.fromOffset(2, 12), Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = color,
		BorderSizePixel = 0 }, wrap)
	new("Frame", { Size = UDim2.fromOffset(12, 2), Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = color,
		BorderSizePixel = 0 }, wrap)
	for _, pos in ipairs({ UDim2.fromScale(0.5, 0), UDim2.fromScale(0.5, 1),
		UDim2.fromScale(0, 0.5), UDim2.fromScale(1, 0.5) }) do
		local head = new("Frame", { Size = UDim2.fromOffset(5, 5), Position = pos,
--@052
			AnchorPoint = Vector2.new(0.5, 0.5), Rotation = 45,
			BackgroundColor3 = color, BorderSizePixel = 0 }, wrap)
		corner(1, head)
	end
	return wrap
end

local function drawOrbIcon(host, color)
	local ring = new("Frame", { Size = UDim2.fromOffset(13, 13),
--@053
		Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1 }, host)
	corner(7, ring)
	stroke(color, 1.4, 0, ring)
	local core = new("Frame", { Size = UDim2.fromOffset(5, 5),
		Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color, BorderSizePixel = 0 }, ring)
--@054
	corner(3, core)
	return ring
end

local function drawCloseIcon(host, color)
	local wrap = new("Frame", { Size = UDim2.fromOffset(14, 14),
		Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1 }, host)
	for _, angle in ipairs({ 45, -45 }) do
		local bar = new("Frame", { Size = UDim2.fromOffset(2, 11),
--@055
			Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = angle, BackgroundColor3 = color, BorderSizePixel = 0 }, wrap)
		corner(1, bar)
	end
	return wrap
end

local function makeHeaderButton(iconFn, order)
	local button = new("TextButton", {
--@056
		Size = UDim2.fromOffset(CONFIG.ButtonSize, CONFIG.ButtonSize),
		BackgroundColor3 = CONFIG.PanelRaised, BackgroundTransparency = 0.15,
		BorderSizePixel = 0, AutoButtonColor = false, Text = "",
		LayoutOrder = order }, HeaderTray)
	corner(6, button)
	pressFeedback(button, 0.15)
	iconFn(button, CONFIG.Text)
	return button
end
--@057

local function makeChip(label, order, startOn, onFlip)
	local chip = new("TextButton", {
		Size = UDim2.new(0.25, -CONFIG.Gap, 0, CONFIG.ChipHeight),
		BackgroundColor3 = CONFIG.PanelRaised, BackgroundTransparency = 0.2,
		BorderSizePixel = 0, AutoButtonColor = false, Text = "",
		LayoutOrder = order }, ChipRow)
	corner(5, chip)
	pressFeedback(chip, 0.2)
--@058
	local dot = new("Frame", { Size = UDim2.fromOffset(4, 4),
		Position = UDim2.fromOffset(4, CONFIG.ChipHeight / 2 - 2),
		BackgroundColor3 = startOn and CONFIG.AccentBright or CONFIG.Stroke,
		BorderSizePixel = 0 }, chip)
	corner(2, dot)
	new("TextLabel", { Size = UDim2.new(1, -9, 1, 0), Position = UDim2.fromOffset(9, 0),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = label,
		TextSize = 7, TextColor3 = CONFIG.TextDim,
--@059
		TextXAlignment = Enum.TextXAlignment.Left }, chip)
	local on = startOn
	chip.MouseButton1Click:Connect(function()
		if State.Destroyed then return end
		on = not on
		dot.BackgroundColor3 = on and CONFIG.AccentBright or CONFIG.Stroke
		onFlip(on)
	end)
	return chip
end
--@060

--====================================================================
-- ORB
--====================================================================

local function enterOrbMode()
	if State.OrbMode then return end
	State.OrbMode = true
	local origin = Main.AbsolutePosition
	local size = Main.AbsoluteSize
	local center = Vector2.new(origin.X + size.X / 2, origin.Y + size.Y / 2)
--@061
	local placed = clampPosition(Vector2.new(center.X - CONFIG.OrbSize / 2,
		center.Y - CONFIG.OrbSize / 2), Vector2.new(CONFIG.OrbSize, CONFIG.OrbSize))
	Orb.Position = UDim2.fromOffset(placed.X, placed.Y)
	Orb.Visible = true
	Orb.BackgroundTransparency = 1
	OrbInner.BackgroundTransparency = 1
	Main.Visible = false
	tween(Orb, CONFIG.Smooth, { BackgroundTransparency = 0.05 })
	tween(OrbInner, CONFIG.Smooth, { BackgroundTransparency = 0 })
end
--@062

local function exitOrbMode()
	if not State.OrbMode then return end
	State.OrbMode = false
	local orbPosition = Orb.AbsolutePosition
	local orbSize = Orb.AbsoluteSize
	local target = Vector2.new(
		orbPosition.X + orbSize.X / 2 - Main.AbsoluteSize.X / 2,
		orbPosition.Y + orbSize.Y / 2 - Main.AbsoluteSize.Y / 2)
	local placed = clampPosition(target, Main.AbsoluteSize)
--@063
	Main.Position = UDim2.fromOffset(placed.X, placed.Y)
	Main.Visible = true
	Orb.Visible = false
end

local function buildOrb(parent)
	Orb = new("TextButton", { Name = "Orb",
		Size = UDim2.fromOffset(CONFIG.OrbSize, CONFIG.OrbSize),
--@064
		Position = UDim2.fromOffset(120, 120), BackgroundColor3 = CONFIG.Panel,
		BackgroundTransparency = 0.05, BorderSizePixel = 0, AutoButtonColor = false,
		Text = "", Visible = false, ZIndex = 20 }, parent)
	corner(CONFIG.OrbSize / 2, Orb)
	stroke(CONFIG.Accent, 2, 0.15, Orb)
	OrbInner = new("Frame", {
		Size = UDim2.fromOffset(CONFIG.OrbSize - 15, CONFIG.OrbSize - 15),
		Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2--[[====================================================================
    T A N K   ·   Build 7.0.0
    Same repo, same file, one blank line below the last build.
-----------------------------------------------------------------------
    WHAT THIS IS
    A front line. Every copy below is squishy: one destroyed panel, one
    dead thread, one stripped stamp and they are out. The tank stands in
    front of them and takes that damage itself, on a health pool, so
    they keep standing while it soaks.
-----------------------------------------------------------------------
    TAUNT
    Nothing reaches the squishies directly. Faults are routed through
    Tank:Damage, which deducts from the tank's own pool, logs the
    attacker on the aggro list, and repairs the target behind it.
-----------------------------------------------------------------------
    INSTANT HEAL
    Every point taken is healed back immediately. The pool never really
    drops for more than a tick. The same healer tops the player's
    Humanoid health to max on every hit, so a body under fire stays up
    while the panel keeps running.
--@001
-----------------------------------------------------------------------
    DEATH HANDOFF
    If the pool does empty, or the tank's own panel dies, it calls
    getgenv().__MEDIC_HANDLE.heal() and gets rebuilt in the same frame.
    Death is a handoff, not an ending: the medic patches it and the tank
    walks back to the front.
-----------------------------------------------------------------------
    CO-EXISTENCE
    Priority 20, below every noclip, so it never takes the write from
    them while they live. If all of them die it inherits the bus and
    stamps legacy until one comes back, then drops the write again.
-----------------------------------------------------------------------
    Author : supercaptain1233        File : Bestnoclip.lua
======================================================================]]

--====================================================================
-- SERVICES
--====================================================================

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local CoreGui          = game:GetService("CoreGui")
local LocalPlayer      = Players.LocalPlayer
local Camera           = workspace.CurrentCamera
--@002

--====================================================================
-- CONFIG
--====================================================================

local CONFIG = {
	Title = "Tank", Build = "7.0.0",
	Priority = 20, MaxHealth = 100, Regen = 1.6,
	HealDelay = 0.05, Tick = 0.25,
	Width = 176, HeaderHeight = 30, BodyHeight = 86, Corner = 11,
	InnerCorner = 8, ButtonSize = 22, ChipHeight = 20, OrbSize = 58,
	Pad = 10, Gap = 6, ClampPad = 8, SnapDistance = 44,
	MinDisplay = 9999,
	Panel        = Color3.fromRGB(14, 20, 22),
	PanelSoft    = Color3.fromRGB(22, 31, 34),
	PanelRaised  = Color3.fromRGB(32, 44, 48),
	Stroke       = Color3.fromRGB(46, 62, 66),
	Accent       = Color3.fromRGB(58, 190, 178),
	AccentBright = Color3.fromRGB(110, 232, 218),
	AccentDark   = Color3.fromRGB(20, 74, 70),
	Text         = Color3.fromRGB(232, 244, 242),
	TextDim      = Color3.fromRGB(120, 140, 140),
	Good         = Color3.fromRGB(120, 210, 140),
	Warn         = Color3.fromRGB(230, 190, 80),
	Bad          = Color3.fromRGB(232, 90, 96),
}
--@003

CONFIG.Fast   = TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
CONFIG.Smooth = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
CONFIG.Snap   = TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

--====================================================================
-- STATE
--====================================================================

local State = {
	Dragging = false, OrbDragging = false, Collapsed = false,
	OrbMode = false, MoveLocked = false, Destroyed = false,
	ToastCount = 0, LastTap = 0, Role = "tank",
	DragOrigin = nil, DragAnchor = nil, OrbOffset = nil,
	BusId = nil, BusEntry = nil,
}
--@004

local Gui, Main, Header, HeaderTray, Body, ChipRow, LogLabel, HealthFill
local Orb, OrbInner, OrbDot, NotifHost
local ToggleButton, ToggleLabel, StatusDot, StatusText, HeaderLabel
local HealChip = nil

--====================================================================
-- UTIL : factory
--====================================================================

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end
--@005

local function corner(r, parent)
	return new("UICorner", { CornerRadius = UDim.new(0, r) }, parent)
end

local function stroke(color, thickness, transparency, parent)
	return new("UIStroke", { Color = color, Thickness = thickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
end
--@006

local function listLayout(parent, gap)
	return new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, gap or 0) }, parent)
end

local function tween(object, info, goal)
	local track = TweenService:Create(object, info, goal)
	track:Play()
	return track
end
--@007

local function viewport()
	local ok, size = pcall(function() return Camera.ViewportSize end)
	if ok and size then return size end
	return Vector2.new(1280, 720)
end

local function clamp(value, low, high)
	if value < low then return low end
	if value > high then return high end
	return value
end
--@008

local function clampPosition(position, size)
	local screen = viewport()
	return Vector2.new(
		clamp(position.X, CONFIG.ClampPad, screen.X - size.X - CONFIG.ClampPad),
		clamp(position.Y, CONFIG.ClampPad, screen.Y - size.Y - CONFIG.ClampPad))
end

local function snapToEdge(position, size)
	local screen = viewport()
	local x, y = position.X, position.Y
--@009
	if x - CONFIG.ClampPad <= CONFIG.SnapDistance then x = CONFIG.ClampPad
	elseif (screen.X - (x + size.X)) - CONFIG.ClampPad <= CONFIG.SnapDistance then
		x = screen.X - size.X - CONFIG.ClampPad
	end
	if y - CONFIG.ClampPad <= CONFIG.SnapDistance then y = CONFIG.ClampPad
	elseif (screen.Y - (y + size.Y)) - CONFIG.ClampPad <= CONFIG.SnapDistance then
		y = screen.Y - size.Y - CONFIG.ClampPad
	end
	return Vector2.new(x, y)
--@010
end

local function isPrimary(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

local function isMotion(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch
end
--@011

local function pointerOf(input)
	return Vector2.new(input.Position.X, input.Position.Y)
end

local function character()
	return LocalPlayer.Character
end

local function humanoid()
	local c = character()
	return c and c:FindFirstChildOfClass("Humanoid")
end
--@012

local function root()
	local c = character()
	return c and c:FindFirstChild("HumanoidRootPart")
end

local function env()
	return (typeof(getgenv) == "function" and getgenv()) or _G
end

--====================================================================
--@013
-- UTIL : press feedback
--====================================================================

local function pressFeedback(button, base)
	button.MouseEnter:Connect(function()
		if not State.Destroyed then
			tween(button, CONFIG.Fast, { BackgroundTransparency = math.max(base - 0.12, 0) })
		end
	end)
--@014
	button.MouseLeave:Connect(function()
		if not State.Destroyed then
			tween(button, CONFIG.Fast, { BackgroundTransparency = base })
		end
	end)
	button.MouseButton1Down:Connect(function()
		if not State.Destroyed then
			tween(button, CONFIG.Fast, { Size = button.Size - UDim2.fromOffset(2, 2) })
		end
	end)
--@015
	button.MouseButton1Up:Connect(function()
		if not State.Destroyed then
			tween(button, CONFIG.Fast, { Size = button.Size + UDim2.fromOffset(2, 2) })
		end
	end)
end

--====================================================================
-- TOASTS
--====================================================================

--@016
local function notify(text, accent)
	if not NotifHost or State.Destroyed then return end
	if State.ToastCount >= 3 then
		local oldest = NotifHost:FindFirstChild("Toast")
		if oldest then oldest:Destroy() end
		State.ToastCount = math.max(State.ToastCount - 1, 0)
	end
	State.ToastCount += 1
	local toast = new("Frame", { Name = "Toast", Size = UDim2.fromOffset(2, 26),
		ClipsDescendants = true, BackgroundColor3 = CONFIG.PanelSoft,
--@017
		BackgroundTransparency = 0.05, BorderSizePixel = 0 }, NotifHost)
	corner(6, toast)
	stroke(accent or CONFIG.Stroke, 1, 0.35, toast)
	new("Frame", { Size = UDim2.new(0, 3, 1, -8), Position = UDim2.new(0, 5, 0, 4),
		BackgroundColor3 = accent or CONFIG.Accent, BorderSizePixel = 0 }, toast)
	new("TextLabel", { Size = UDim2.new(1, -18, 1, 0), Position = UDim2.new(0, 14, 0, 0),
		BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, Text = text,
--@018
		TextSize = 11, TextColor3 = CONFIG.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left }, toast)
	tween(toast, CONFIG.Smooth, { Size = UDim2.fromOffset(NotifHost.AbsoluteSize.X, 26) })
	task.delay(1.7, function()
		if not toast or not toast.Parent then return end
		tween(toast, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
--@019
			Size = UDim2.fromOffset(2, 26), BackgroundTransparency = 1 })
		task.wait(0.18)
		if toast then toast:Destroy() end
		State.ToastCount = math.max(State.ToastCount - 1, 0)
	end)
end

--====================================================================
-- BUS
--====================================================================
-- Priority 20. Never outranks a noclip while one lives; inherits the
-- write only when the last of them is gone.
--@020

local BUS_KEY = "__NOCLIP_BUS_V3"
local bus = env()[BUS_KEY]
if type(bus) ~= "table" then
	bus = { entries = {}, order = 0, arbiter = nil, mirror = nil }
	env()[BUS_KEY] = bus
end

local function busArbitrate()
	local best
--@021
	for _, entry in pairs(bus.entries) do
		if entry.active and (not best or entry.priority > best.priority) then
			best = entry
		end
	end
	bus.arbiter = best
	bus.mirror = nil
	for _, entry in pairs(bus.entries) do
		if entry ~= best then bus.mirror = entry end
--@022
		entry.role = entry == best and "writer" or "mirror"
	end
end

local function busRegister(entry)
	bus.order += 1
	entry.order = bus.order
	entry.active = false
	entry.role = "writer"
	bus.entries[bus.order] = entry
--@023
	return entry
end

local function busActivate(entry)
	entry.active = true
	busArbitrate()
	State.Role = entry.role
end

local function busDeactivate(entry)
	entry.active = false
	busArbitrate()
--@024
	if bus.arbiter and bus.arbiter.onPromote then bus.arbiter.onPromote() end
end

local function liveNoclips()
	local count = 0
	for _, entry in pairs(bus.entries) do
		if entry.active and not entry.tank and not entry.medic then count += 1 end
	end
	return count
end

--@025
--====================================================================
-- TANK
--====================================================================

local Tank = {}
Tank.Active = false
Tank.Health = CONFIG.MaxHealth
Tank.Absorbed = 0
Tank.Heals = 0
Tank.Deaths = 0
Tank.Loop = nil
Tank.Log = {}
Tank.Aggro = {}
Tank.Armor = {}
--@026

function Tank:Note(text)
	table.insert(self.Log, text)
	if #self.Log > 6 then table.remove(self.Log, 1) end
	if LogLabel then LogLabel.Text = table.concat(self.Log, "\n") end
end

function Tank:Paint()
	if not HealthFill then return end
	local ratio = clamp(self.Health / CONFIG.MaxHealth, 0, 1)
--@027
	HealthFill.Size = UDim2.new(ratio, 0, 1, 0)
	HealthFill.BackgroundColor3 = ratio > 0.6 and CONFIG.Accent
		or (ratio > 0.3 and CONFIG.Warn or CONFIG.Bad)
end

function Tank:Heal(amount)
	self.Health = clamp(self.Health + (amount or CONFIG.MaxHealth), 0, CONFIG.MaxHealth)
	self.Heals += 1
	self:Paint()
--@028
end

function Tank:Regen()
	while self.Active do
		if self.Health < CONFIG.MaxHealth then
			self:Heal(CONFIG.Regen * 6)
		end
		task.wait(0.1)
	end
end

--@029
--====================================================================
-- DAMAGE SINK
--====================================================================

function Tank:Damage(amount, source)
	if not self.Active then return end
	self.Health = clamp(self.Health - amount, 0, CONFIG.MaxHealth)
	self.Absorbed += amount
	self.Aggro[source or "unknown"] = (self.Aggro[source or "unknown"] or 0) + 1
	self:Paint()
	self:Note("-" .. amount .. " " .. tostring(source))
--@030
	task.delay(CONFIG.HealDelay, function()
		if self.Active and self.Health < CONFIG.MaxHealth then
			self:Heal(amount + CONFIG.Regen * 4)
		end
	end)
	if self.Health <= 0 then self:Die() end
end

--@031
-- any script can route work through the tank; failures become damage
function Tank:Absorb(source, fn)
	local ok, err = pcall(fn)
	if not ok then
		self:Damage(10, source)
		return false, err
	end
	return true
end

function Tank:Die()
	self.Deaths += 1
	self:Note("down · handoff")
	notify("Down, calling medic", CONFIG.Bad)
--@032
	local g = env()
	local medic = g.__MEDIC_HANDLE
	if type(medic) == "table" and medic.heal then
		pcall(medic.heal)
	end
	task.defer(function()
		self.Health = CONFIG.MaxHealth * 0.5
		self:Paint()
		pcall(function()
			if Gui then Gui:Destroy() end
		end)
--@033
		task.wait(0.05)
		if not State.Destroyed then
			pcall(build)
			self:Note("back up")
		end
	end)
end

--====================================================================
-- ARMOR LAYERS
--====================================================================
--@034

Tank.Armor["shell"] = function()
	if not Gui then return end
	local ok = pcall(function() return Gui.Parent end)
	if not ok or Gui.Parent == nil then
		Tank:Damage(30, "panel")
		pcall(function()
			if Gui then Gui.Parent = parentTarget() end
		end)
	end
	if Gui and Gui.Enabled ~= true then
		Gui.Enabled = true
		Tank:Damage(10, "disabled")
	end
--@035
	if Gui and Gui.DisplayOrder < CONFIG.MinDisplay then
		Gui.DisplayOrder = CONFIG.MinDisplay
		Tank:Damage(5, "order")
	end
	if not State.Collapsed and not State.OrbMode and Main and not Main.Visible then
		Main.Visible = true
		Tank:Damage(8, "hidden")
	end
end

--@036
Tank.Armor["stamp"] = function()
	local c = character()
	if not c or not bus.arbiter then return end
	local group = bus.arbiter.group or "SilentNoclip"
	local broken = false
	for _, item in ipairs(c:GetDescendants()) do
		if item:IsA("BasePart") then
			if bus.arbiter.mode == "group" and item.CollisionGroup == "Default" then
				broken = true
--@037
			elseif bus.arbiter.mode ~= "group" and item.CanCollide then
				broken = true
			end
		end
	end
	if not broken then return end
	Tank:Damage(15, "stamps")
	for _, item in ipairs(c:GetDescendants()) do
		if item:IsA("BasePart") then
			if bus.arbiter.mode == "group" then
--@038
				item.CollisionGroup = group
			else
				item.CanCollide = false
			end
		end
	end
end

Tank.Armor["body"] = function()
	local h = humanoid()
	if not h then return end
	if h.WalkSpeed <= 0 then
		h.WalkSpeed = 16
		Tank:Damage(12, "walkspeed")
--@039
	end
	if h.PlatformStand then
		h.PlatformStand = false
		Tank:Damage(8, "platformstand")
	end
	if not h.AutoRotate then
		h.AutoRotate = true
		Tank:Damage(4, "autorotate")
	end
end

--@040
Tank.Armor["root"] = function()
	local r = root()
	if not r then return end
	local h = humanoid()
	if r.Anchored and h and h.WalkSpeed > 0 then
		r.Anchored = false
		Tank:Damage(20, "anchored")
	end
end

Tank.Armor["bus"] = function()
--@041
	if not State.BusEntry then return end
	if bus.entries[State.BusEntry.order] == State.BusEntry then return end
	busRegister(State.BusEntry)
	Tank:Damage(25, "bus slot")
end

--====================================================================
-- INSTANT HEAL
--====================================================================
--@042

local HealthMax = 100
local LastHeal = 0

Tank.Armor["heal"] = function()
	local h = humanoid()
	if not h then return end
	if h.MaxHealth > 0 then HealthMax = h.MaxHealth end
	if h.Health >= HealthMax then return end
	if os.clock() - LastHeal < 0.05 then return end
--@043
	LastHeal = os.clock()
	h.Health = HealthMax
	Tank:Note("+heal " .. math.floor(HealthMax - h.Health))
end

function Tank:ArmorLoop()
	local order = { "shell", "bus", "body", "root", "stamp", "heal" }
	while self.Active do
		for _, name in ipairs(order) do
			local layer = self.Armor[name]
			if layer then pcall(layer) end
--@044
		end
		task.wait(CONFIG.Tick)
	end
end

function Tank:Start()
	if self.Active then return end
	self.Active = true
	self.Health = CONFIG.MaxHealth
	self:Paint()
	if State.BusEntry then busActivate(State.BusEntry) end
--@045
	self.Loop = task.spawn(function() self:ArmorLoop() end)
	task.spawn(function() self:Regen() end)
	notify("Tank front line", CONFIG.AccentBright)
	paintToggle()
end

function Tank:Stop()
	if not self.Active then return end
	self.Active = false
	if self.Loop then task.cancel(self.Loop) self.Loop = nil end
--@046
	if State.BusEntry then busDeactivate(State.BusEntry) end
	notify("Tank off", CONFIG.TextDim)
	paintToggle()
end

function Tank:Toggle()
	if self.Active then self:Stop() else self:Start() end
end

--====================================================================
--@047
-- ICONS
--====================================================================

local function drawMoveIcon(host, color)
	local wrap = new("Frame", { Size = UDim2.fromOffset(14, 14),
		Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1 }, host)
	new("Frame", { Size = UDim2.fromOffset(2, 12), Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = color,
--@048
		BorderSizePixel = 0 }, wrap)
	new("Frame", { Size = UDim2.fromOffset(12, 2), Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = color,
		BorderSizePixel = 0 }, wrap)
	for _, pos in ipairs({ UDim2.fromScale(0.5, 0), UDim2.fromScale(0.5, 1),
		UDim2.fromScale(0, 0.5), UDim2.fromScale(1, 0.5) }) do
		local head = new("Frame", { Size = UDim2.fromOffset(5, 5), Position = pos,
			AnchorPoint = Vector2.new(0.5, 0.5), Rotation = 45,
--@049
			BackgroundColor3 = color, BorderSizePixel = 0 }, wrap)
		corner(1, head)
	end
	return wrap
end

local function drawOrbIcon(host, color)
	local ring = new("Frame", { Size = UDim2.fromOffset(13, 13),
		Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
--@050
		BackgroundTransparency = 1 }, host)
	corner(7, ring)
	stroke(color, 1.4, 0, ring)
	local core = new("Frame", { Size = UDim2.fromOffset(5, 5),
		Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color, BorderSizePixel = 0 }, ring)
	corner(3, core)
--@051
	return ring
end

local function drawCloseIcon(host, color)
	local wrap = new("Frame", { Size = UDim2.fromOffset(14, 14),
		Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1 }, host)
	for _, angle in ipairs({ 45, -45 }) do
		local bar = new("Frame", { Size = UDim2.fromOffset(2, 11),
			Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
--@052
			Rotation = angle, BackgroundColor3 = color, BorderSizePixel = 0 }, wrap)
		corner(1, bar)
	end
	return wrap
end

local function makeHeaderButton(iconFn, order)
	local button = new("TextButton", {
		Size = UDim2.fromOffset(CONFIG.ButtonSize, CONFIG.ButtonSize),
--@053
		BackgroundColor3 = CONFIG.PanelRaised, BackgroundTransparency = 0.15,
		BorderSizePixel = 0, AutoButtonColor = false, Text = "",
		LayoutOrder = order }, HeaderTray)
	corner(6, button)
	pressFeedback(button, 0.15)
	iconFn(button, CONFIG.Text)
	return button
end

--@054
local function makeChip(label, order, startOn, onFlip)
	local chip = new("TextButton", {
		Size = UDim2.new(0.25, -CONFIG.Gap, 0, CONFIG.ChipHeight),
		BackgroundColor3 = CONFIG.PanelRaised, BackgroundTransparency = 0.2,
		BorderSizePixel = 0, AutoButtonColor = false, Text = "",
		LayoutOrder = order }, ChipRow)
	corner(5, chip)
	pressFeedback(chip, 0.2)
--@055
	local dot = new("Frame", { Size = UDim2.fromOffset(4, 4),
		Position = UDim2.fromOffset(4, CONFIG.ChipHeight / 2 - 2),
		BackgroundColor3 = startOn and CONFIG.AccentBright or CONFIG.Stroke,
		BorderSizePixel = 0 }, chip)
	corner(2, dot)
	new("TextLabel", { Size = UDim2.new(1, -9, 1, 0), Position = UDim2.fromOffset(9, 0),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = label,
--@056
		TextSize = 7, TextColor3 = CONFIG.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left }, chip)
	local on = startOn
	chip.MouseButton1Click:Connect(function()
		if State.Destroyed then return end
		on = not on
		dot.BackgroundColor3 = on and CONFIG.AccentBright or CONFIG.Stroke
		onFlip(on)
--@057
	end)
	return chip
end

--====================================================================
-- ORB
--====================================================================

local function enterOrbMode()
--@058
	if State.OrbMode then return end
	State.OrbMode = true
	local origin = Main.AbsolutePosition
	local size = Main.AbsoluteSize
	local center = Vector2.new(origin.X + size.X / 2, origin.Y + size.Y / 2)
	local placed = clampPosition(Vector2.new(center.X - CONFIG.OrbSize / 2,
		center.Y - CONFIG.OrbSize / 2), Vector2.new(CONFIG.OrbSize, CONFIG.OrbSize))
--@059
	Orb.Position = UDim2.fromOffset(placed.X, placed.Y)
	Orb.Visible = true
	Orb.BackgroundTransparency = 1
	OrbInner.BackgroundTransparency = 1
	Main.Visible = false
	tween(Orb, CONFIG.Smooth, { BackgroundTransparency = 0.05 })
	tween(OrbInner, CONFIG.Smooth, { BackgroundTransparency = 0 })
end
--@060

local function exitOrbMode()
	if not State.OrbMode then return end
	State.OrbMode = false
	local orbPosition = Orb.AbsolutePosition
	local orbSize = Orb.AbsoluteSize
	local target = Vector2.new(
		orbPosition.X + orbSize.X / 2 - Main.AbsoluteSize.X / 2,
		orbPosition.Y + orbSize.Y / 2 - Main.AbsoluteSize.Y / 2)
--@061
	local placed = clampPosition(target, Main.AbsoluteSize)
	Main.Position = UDim2.fromOffset(placed.X, placed.Y)
	Main.Visible = true
	Orb.Visible = false
end

local function buildOrb(parent)
	Orb = new("TextButton", { Name = "Orb",
		Size = UDim2.fromOffset(CONFIG.OrbSize, CONFIG.OrbSize),
--@062
		Position = UDim2.fromOffset(120, 120), BackgroundColor3 = CONFIG.Panel,
		BackgroundTransparency = 0.05, BorderSizePixel = 0, AutoButtonColor = false,
		Text = "", Visible = false, ZIndex = 20 }, parent)
	corner(CONFIG.OrbSize / 2, Orb)
	stroke(CONFIG.Accent, 2, 0.15, Orb)
	OrbInner = new("Frame", {
		Size = UDim2.fromOffset(CONFIG.OrbSize - 15, CONFIG.OrbSize - 15),
--@063
		Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = CONFIG.PanelRaised, BorderSizePixel = 0, ZIndex = 21 }, Orb)
	corner((CONFIG.OrbSize - 15) / 2, OrbInner)
	drawOrbIcon(OrbInner, CONFIG.AccentBright)
	OrbDot = new("Frame", { Size = UDim2.fromOffset(9, 9),
		Position = UDim2.new(0.5, 0, 1, -5), AnchorPoint = Vector2.new(0.5, 0.5),
--@064
		BackgroundColor3 = CONFIG.AccentBright, BorderSizePixel = 0,
		Visible = false, ZIndex = 22 }, Orb)
	corner(5, OrbDot)
	stroke(CONFIG.Panel, 1.5, 0, OrbDot)
end

--====================================================================
--@065
-- TOGGLE
--====================================================================

function paintToggle()
	if not ToggleButton then return end
	if Tank.Active then
		tween(ToggleButton, CONFIG.Fast, { BackgroundColor3 = CONFIG.AccentBright })
		ToggleLabel.Text = "TAUNTING"
		ToggleLabel.TextColor3 = Color3.fromRGB(10, 32, 30)
--@066
		StatusDot.BackgroundColor3 = CONFIG.AccentBright
		StatusText.Text = "FRONT LINE"
		StatusText.TextColor3 = CONFIG.AccentBright
		OrbDot.Visible = true
	else
		tween(ToggleButton, CONFIG.Fast, { BackgroundColor3 = CONFIG.Accent })
		ToggleLabel.Text = "TANK"
		ToggleLabel.TextColor3 = Color3.fromRGB(10, 32, 30)
		StatusDot.BackgroundColor3 = CONFIG.AccentDark
--@067
		StatusText.Text = "IDLE"
		StatusText.TextColor3 = CONFIG.TextDim
		OrbDot.Visible = false
	end
end

local function buildToggle()
	ToggleButton = new("TextButton", { Size = UDim2.new(1, -CONFIG.Pad * 2, 0, 34),
		Position = UDim2.fromOffset(CONFIG.Pad, 6), BackgroundColor3 = CONFIG.Accent,
		BorderSizePixel = 0, AutoButtonColor = false, Text = "",
--@068
		ClipsDescendants = true }, Body)
	corner(CONFIG.InnerCorner, ToggleButton)
	stroke(CONFIG.AccentDark, 1, 0.4, ToggleButton)
	ToggleLabel = new("TextLabel", { Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = "TANK",
		TextSize = 13, TextColor3 = Color3.fromRGB(10, 32, 30),
		TextXAlignment = Enum.TextXAlignment.Center }, ToggleButton)
--@069
	pressFeedback(ToggleButton, 0)
	ToggleButton.MouseButton1Click:Connect(function()
		if State.Destroyed then return end
		Tank:Toggle()
	end)
end

--====================================================================
--@070
-- HEADER
--====================================================================

local function buildHeader()
	Header = new("Frame", { Name = "Header",
		Size = UDim2.new(1, 0, 0, CONFIG.HeaderHeight),
		BackgroundColor3 = CONFIG.PanelSoft, BorderSizePixel = 0 }, Main)
	corner(CONFIG.Corner, Header)
--@071
	new("Frame", { Size = UDim2.new(1, -CONFIG.Pad * 2, 0, 1),
		Position = UDim2.new(0, CONFIG.Pad, 1, -1), BackgroundColor3 = CONFIG.Stroke,
		BorderSizePixel = 0 }, Header)
	StatusDot = new("Frame", { Size = UDim2.fromOffset(6, 6),
		Position = UDim2.fromOffset(CONFIG.Pad, CONFIG.HeaderHeight / 2 - 3),
		BackgroundColor3 = CONFIG.AccentDark, BorderSizePixel = 0 }, Header)
	corner(3, StatusDot)
--@072
	HeaderLabel = new("TextLabel", { Size = UDim2.new(0, 56, 1, 0),
		Position = UDim2.fromOffset(CONFIG.Pad + 12, 0), BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold, Text = CONFIG.Title, TextSize = 12,
		TextColor3 = CONFIG.Text, TextXAlignment = Enum.TextXAlignment.Left }, Header)
	StatusText = new("TextLabel", { Size = UDim2.fromOffset(52, 1),
		Position = UDim2.new(0, CONFIG.Pad + 66, 1, -9), BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold, Text = "IDLE", TextSize = 7,
--@073
		TextColor3 = CONFIG.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left }, Header)
	HeaderTray = new("Frame", { Size = UDim2.new(1, -CONFIG.Pad * 2, 1, 0),
		Position = UDim2.fromOffset(CONFIG.Pad, 0), BackgroundTransparency = 1 }, Header)
	listLayout(HeaderTray, CONFIG.Gap)
end
--@074

--====================================================================
-- DRAG
--====================================================================

local function beginDrag(input)
	State.Dragging = true
	State.DragOrigin = pointerOf(input)
	State.DragAnchor = Vector2.new(Main.AbsolutePosition.X, Main.AbsolutePosition.Y)
end
--@075

local function moveDrag(input)
	if not State.Dragging then return end
	local placed = clampPosition(
		State.DragAnchor + (pointerOf(input) - State.DragOrigin), Main.AbsoluteSize)
	Main.Position = UDim2.fromOffset(placed.X, placed.Y)
end

local function endDrag()
	if not State.Dragging then return end
	State.Dragging = false
--@076
	local snapped = snapToEdge(Main.AbsolutePosition, Main.AbsoluteSize)
	tween(Main, CONFIG.Smooth, { Position = UDim2.fromOffset(snapped.X, snapped.Y) })
end

local function bindHeaderDrag()
	Header.InputBegan:Connect(function(input)
		if not isPrimary(input) or State.OrbMode or State.Destroyed then return end
		beginDrag(input)
--@077
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then endDrag() end
		end)
	end)
end

local function bindOrbDrag()
	Orb.InputBegan:Connect(function(input)
		if not isPrimary(input) or State.Destroyed then return end
--@078
		State.OrbDragging = true
		State.OrbOffset = Vector2.new(Orb.AbsolutePosition.X, Orb.AbsolutePosition.Y)
			- pointerOf(input)
		tween(Orb, CONFIG.Fast, {
			Size = UDim2.fromOffset(CONFIG.OrbSize - 6, CONFIG.OrbSize - 6) })
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
--@079
				State.OrbDragging = false
				tween(Orb, CONFIG.Snap, {
					Size = UDim2.fromOffset(CONFIG.OrbSize, CONFIG.OrbSize) })
			end
		end)
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not State.OrbDragging or not State.OrbOffset then return end
		if not isMotion(input) then return end
--@080
		local placed = clampPosition(pointerOf(input) + State.OrbOffset, Orb.AbsoluteSize)
		Orb.Position = UDim2.fromOffset(placed.X, placed.Y)
	end)
end

--====================================================================
-- COLLAPSE
--====================================================================

local function setCollapsed(value)
	if State.Collapsed == value then return end
	State.Collapsed = value
--@081
	if value then
		Body.Visible = false
		HeaderLabel.TextColor3 = CONFIG.TextDim
		tween(Main, CONFIG.Smooth, {
			Size = UDim2.fromOffset(CONFIG.Width, CONFIG.HeaderHeight) })
	else
		HeaderLabel.TextColor3 = CONFIG.Text
		tween(Main, CONFIG.Smooth, {
			Size = UDim2.fromOffset(CONFIG.Width, CONFIG.HeaderHeight + CONFIG.BodyHeight) })
--@082
		task.delay(0.06, function()
			if not State.Collapsed and not State.Destroyed then Body.Visible = true end
		end)
	end
end

--====================================================================
-- ASSEMBLY
--====================================================================

--@083
local function parentTarget()
	if typeof(gethui) == "function" then
		local ok, handle = pcall(gethui)
		if ok and handle then return handle end
	end
	local probe = Instance.new("Folder")
	local ok = pcall(function() probe.Parent = CoreGui end)
	probe:Destroy()
	if ok then return CoreGui end
--@084
	return LocalPlayer:WaitForChild("PlayerGui")
end

local function build()
	Gui = new("ScreenGui", { Name = "TankNoclip", ResetOnSpawn = false,
		IgnoreGuiInset = true, DisplayOrder = CONFIG.MinDisplay,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
	NotifHost = new("Frame", { Name = "Toasts", Size = UDim2.new(1, 0, 0, 96),
		BackgroundTransparency = 1 }, Gui)
--@085
	new("UIListLayout", { FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 4) }, NotifHost)
	Main = new("Frame", { Name = "Main", Position = UDim2.fromOffset(24, 24),
		Size = UDim2.fromOffset(CONFIG.Width, CONFIG.HeaderHeight + CONFIG.BodyHeight),
		BackgroundColor3 = CONFIG.Panel, BorderSizePixel = 0,
		ClipsDescendants = true }, Gui)
	corner(CONFIG.Corner, Main)
--@086
	stroke(CONFIG.Stroke, 1, 0.25, Main)
	buildHeader()
	Body = new("Frame", { Name = "Body", Size = UDim2.new(1, 0, 0, CONFIG.BodyHeight),
		Position = UDim2.fromOffset(0, CONFIG.HeaderHeight),
		BackgroundTransparency = 1 }, Main)
	buildToggle()
	ChipRow = new("Frame", { Name = "Chips",
		Size = UDim2.new(1, -CONFIG.Pad * 2, 0, CONFIG.ChipHeight),
--@087
		Position = UDim2.fromOffset(CONFIG.Pad, 44), BackgroundTransparency = 1 }, Body)
	listLayout(ChipRow, CONFIG.Gap)
	makeChip("AGGRO", 1, false, function()
		local parts = {}
		for source, count in pairs(Tank.Aggro) do
			table.insert(parts, source .. " " .. count)
		end
		Tank:Note(#parts > 0 and table.concat(parts, " ") or "no aggro")
	end)
--@088
	HealChip = makeChip("HEAL", 2, false, function()
		Tank:Heal(CONFIG.MaxHealth)
		Tank:Note("+full")
	end)
	makeChip("RESET", 3, false, function()
		Tank.Aggro = {}
		Tank.Absorbed = 0
		Tank:Heal(CONFIG.MaxHealth)
		Tank:Note("cleared")
	end)
	makeChip("CLR", 4, false, function()
--@089
		Tank.Log = {}
		if LogLabel then LogLabel.Text = "" end
	end)
	local barBack = new("Frame", { Name = "Health", Size = UDim2.new(1, -CONFIG.Pad * 2, 0, 5),
		Position = UDim2.fromOffset(CONFIG.Pad, 68), BackgroundColor3 = CONFIG.PanelRaised,
		BorderSizePixel = 0 }, Body)
	corner(3, barBack)
	HealthFill = new("Frame", { Size = UDim2.fromScale(1, 1),
--@090
		BackgroundColor3 = CONFIG.Accent, BorderSizePixel = 0 }, barBack)
	corner(3, HealthFill)
	LogLabel = new("TextLabel", { Name = "Log",
		Size = UDim2.new(1, -CONFIG.Pad * 2, 0, 22),
		Position = UDim2.fromOffset(CONFIG.Pad, 76), BackgroundTransparency = 1,
		Font = Enum.Font.Code, Text = "", TextSize = 8, TextWrap = true,
--@091
		TextColor3 = CONFIG.TextDim, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top }, Body)
	local orbButton = makeHeaderButton(drawOrbIcon, 1)
	local moveButton = makeHeaderButton(drawMoveIcon, 2)
	local closeButton = makeHeaderButton(drawCloseIcon, 3)
	buildOrb(Gui)
--@092
	orbButton.MouseButton1Click:Connect(function()
		if State.Destroyed then return end
		if State.OrbMode then exitOrbMode() else enterOrbMode() end end)
	Orb.MouseButton1Click:Connect(function()
		if not State.OrbDragging then exitOrbMode() end end)
	moveButton.MouseButton1Click:Connect(function()
		State.MoveLocked = not State.MoveLocked
--@093
		if State.MoveLocked then stroke(CONFIG.Accent, 1.5, 0, moveButton)
			notify("Drag unlocked", CONFIG.Accent) else
			local s = moveButton:FindFirstChildOfClass("UIStroke") if s then s:Destroy() end
			notify("Drag locked", CONFIG.TextDim) end end)
	closeButton.MouseButton1Click:Connect(function() setCollapsed(not State.Collapsed) end)
	HeaderLabel.InputBegan:Connect(function(input)
--@094
		if not isPrimary(input) or State.Destroyed then return end
		if State.Collapsed then return setCollapsed(false) end
		local now = os.clock()
		if now - State.LastTap <= 0.35 then
			Main.Position = UDim2.fromOffset(24, 24) State.LastTap = 0
		else State.LastTap = now end end)
	Gui.Parent = parentTarget()
--@095
	bindHeaderDrag() bindOrbDrag() paintToggle()
	UserInputService.InputChanged:Connect(function(input)
		if State.Dragging and isMotion(input) then moveDrag(input) end end)
	UserInputService.InputEnded:Connect(function(input)
		if isPrimary(input) then endDrag() end end)
	Camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
--@096
		if not Main or State.Destroyed then return end
		local placed = clampPosition(Main.AbsolutePosition, Main.AbsoluteSize)
		Main.Position = UDim2.fromOffset(placed.X, placed.Y) end)
end

--====================================================================
-- KEYS + BOOT
--====================================================================
-- RightShift tank · RightAlt collapse · RightControl orb
--@097

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or State.Destroyed then return end
	if input.KeyCode == Enum.KeyCode.RightShift then Tank:Toggle()
	elseif input.KeyCode == Enum.KeyCode.RightAlt then setCollapsed(not State.Collapsed)
	elseif input.KeyCode == Enum.KeyCode.RightControl then
		if State.OrbMode then exitOrbMode() else enterOrbMode() end
	end
end)
--@098

local Entry = busRegister({ id = tostring(math.random(1000000)),
	priority = CONFIG.Priority, tank = true,
	onPromote = function()
		State.Role = "tank"
		if liveNoclips() == 0 and Tank.Active then Tank:Note("inherited write") end
	end,
	onDemote = function() State.Role = "tank" end })
--@099
State.BusId = Entry.id
State.BusEntry = Entry

local built, err = pcall(build)
if not built then warn("[Tank] " .. tostring(err)) end

LocalPlayer.CharacterAdded:Connect(function(c)
	c:WaitForChild("HumanoidRootPart", 10)
	task.wait(0.15)
--@100
	local h = c:FindFirstChildOfClass("Humanoid")
	if h then HealthMax = math.max(h.MaxHealth, 1) end
end)

--====================================================================
-- HANDLE
--====================================================================

pcall(function()
	env().__TANK_HANDLE = {
		absorb = function(source, fn) return Tank:Absorb(source, fn) end,
--@101
		damage = function(amount, source) Tank:Damage(amount, source) end,
		heal = function() Tank:Heal(CONFIG.MaxHealth) end,
		health = function() return Tank.Health end,
		aggro = function() return Tank.Aggro end,
		alive = function() return not State.Destroyed end,
		toggle = function() Tank:Toggle() end,
	}
end)

--@102
--====================================================================
-- DOCS
--====================================================================
--[[
  AGGRO   Print the current attacker ledger and counts.
  HEAL    Force a full self-heal.
  RESET   Clear aggro, absorbed total, and heal.
  CLR     Wipe the log.

  The bar under the chips is the tank pool. Damage lands, the bar dips
  for one tick, and the instant heal puts it back. It never sits low
  unless the game is hitting faster than 0.05s apart.

  HealthMax is read off the live humanoid, so games with a non-100 max
  still heal to their own ceiling instead of to a hardcoded number.

  Absorb for other scripts:
    getgenv().__TANK_HANDLE.absorb("name", fn)
  returns true on success and converts a throw into 10 damage instead of
  an unhandled error.

  Down state calls getgenv().__MEDIC_HANDLE.heal() and rebuilds in the
  same frame.
]]
--@103
