-- In case the user runs this using lua_openscript instead of lua_openscript_cl
if SERVER then
	AddCSLuaFile()

	return
end

local PLAYER = FindMetaTable("Player")
local ENTITY = FindMetaTable("Entity")

local color_white = Color(255, 255, 255, 255)
local color_black = Color(0, 0, 0, 255)

-- Convars
local vars = {
	enabled = CreateClientConVar("_demo_esp_enabled", "1", true, false),
	alive_only = CreateClientConVar("_demo_esp_alive_only", "0", true, false),
	vehicles = CreateClientConVar("_demo_esp_vehicle_info", "1", true, false),
	hover = CreateClientConVar("_demo_esp_hover", "0", true, false),

	time = CreateClientConVar("_demo_show_time", "1", true, false),
	show_steamid = CreateClientConVar("_demo_esp_show_steamid", "1", true, false),
	show_rpname = CreateClientConVar("_demo_esp_show_rpname", "1", true, false),
	show_rank = CreateClientConVar("_demo_esp_show_rank", "1", true, false),
	show_weapon = CreateClientConVar("_demo_esp_show_weapon", "1", true, false),
	show_health = CreateClientConVar("_demo_esp_show_health", "1", true, false),
	show_warrant = CreateClientConVar("_demo_esp_show_warrant", "0", true, false),
	show_status = CreateClientConVar("_demo_esp_show_status", "0", true, false),
	show_jobs = CreateClientConVar("_demo_esp_show_jobs", "0", true, false),

	outline = CreateClientConVar("_demo_esp_draw_outline", "0", true, false),
	range = CreateClientConVar("_demo_esp_range", "1000", true, false),

	fov = CreateClientConVar("_demo_fov", "100", true, false),
	logs = CreateClientConVar("_demo_kill_logs", "1", true, false),
	disable_uis = CreateClientConVar("_demo_disable_uis", "1", true, false),
	crosshair = CreateClientConVar("_demo_crosshair", "0", true, false),
	zoom = CreateClientConVar("_demo_zoom", "0", true, false),

	-- No point in saving these to the config
	window = false,
	focuslock = jit.os ~= "Windows",
	spectate = false,
	noclip = false,
	thirdperson = false,
}

local target = {
	idx = nil,
	ent = nil,
	voice = nil,
}

-- Very roughly mimic CInput::MouseMove, with disregard for mouse filtering, accel settings, hud sensitivity, and +strafe
local mouse = {
	lost_focus = false,
	-- Pixel/cursor delta. NOT raw mouse deltas like the engine interally uses
	dx = 0,
	dy = 0,

	ang = Angle(0, 0, 0),
	cam = Vector(0, 0, 0),
	velocity = Vector(0, 0 ,0),

	yaw = GetConVar("m_yaw"),
	pitch = GetConVar("m_pitch"),
	sens = GetConVar("sensitivity"),
	fov = GetConVar("fov_desired"),
}

-- Allows the gamemode to show the player's RP name above their head normally
function PLAYER:GetRPName()
	local first = self:GetNWString("rp_fname", -1)
	local surname = self:GetNWString("rp_lname", -1)

	if first == -1 or surname == -1 then
		return "John Doe"
	end

	return first .. " " .. surname
end

-- TinySlayer's demo ESP provided a similar solution that seemed wrong. This unlocks all permissions within the gamemode
function PLAYER:HasPermission(x)
	return x ~= "rankcolor"
end


-- utils
local drawing_window = false
local is_playing_demo = engine.IsPlayingDemo()

local function ScaleSize(size)
	return size * (ScrW() / 2560)
end

-- In hindsight, this should've been called GetLocal instead
local function GetTarget()
	if vars.spectate and not vars.window and IsValid(target.ent) then
		return target.ent
	end

	return LocalPlayer()
end

local function GetEyePos()
	if vars.noclip then
		return mouse.cam
	end

	return GetTarget():EyePos()
end

local function GetEyeAngles()
	if vars.noclip then
		return mouse.ang
	end

	return GetTarget():EyeAngles()
end

local function GetFOV()
	local fov = mouse.fov:GetFloat()
	if vars.zoom:GetBool() and vars.spectate and IsValid(target.ent) then
		local swep = GetTarget():GetActiveWeapon()

		-- dumping LocalPlayer():GetActiveweapon():GetTable() nets these and more functions
		if IsValid(swep) and swep.IsIronSighting and swep:IsIronSighting() then
			local zoom = swep.GetScopeMagnification and swep:GetScopeMagnification() or 1
			return fov / zoom
		end
	end

	return fov
end

local function ResetMouseData()
	mouse.ang = GetEyeAngles()
	mouse.cam = GetEyePos()
	mouse.dx = 0
	mouse.dy = 0
	mouse.velocity:Zero()
end

local function ResetUI()
	RunConsoleCommand("resetui")
end

local function SpectatePlayer(ply)
	if ply == LocalPlayer() then return end

	target.ent = ply
	if target.ent then
		target.idx = ply:EntIndex()
		vars.spectate = true

		if not vars.window then
			vars.noclip = false
		end

		ResetMouseData()
	end

	ResetUI()
end

local function StopSpectating()
	vars.spectate = false
	target.ent = nil
	target.idx = nil
end

local function ToggleDemoNoclip()
	local state = not vars.noclip

	if state then
		-- We wish to start from whatever POV we were in previously.
		ResetMouseData()

		if not vars.window then
			StopSpectating()
		end
	end

	vars.noclip = state
	ResetUI()
end
concommand.Add("_demo_toggle_noclip", ToggleDemoNoclip)

local function ToggleWindow()
	vars.window = not vars.window

	if vars.spectate then
		vars.noclip = false
	end
end

local function FormatPlayerName(ply)
	return string.format("%s (%s, %s)", ply:GetRPName(), ply:Nick(), ply:SteamID())
end

-- A function is only provided when a DMenu sub menu wishes to be populated
local function PopulateCombobox(combo, func)
	if not func then combo:Clear() end

	local localplayer = LocalPlayer()
	local t = player.GetAll()

	local pos = GetEyePos()
	table.sort(t, function(a, b)
		return pos:DistToSqr(a:GetPos()) < pos:DistToSqr(b:GetPos())
	end)

	for i, ply in ipairs(t) do
		if ply == LocalPlayer() then continue end
		local str = ply:IsDormant() and " (dormant)" or ""

		if func then
			if not ply:IsDormant() then
				combo:AddOption(FormatPlayerName(ply) .. str, function() func(ply) end)
			end
		else
			combo:AddChoice(FormatPlayerName(ply) .. str, ply:EntIndex())
		end
	end
end

local _gui_data = {
	{ type = "checkbox", label = "Enable ESP", var = vars.enabled },
	{ type = "checkbox", label = "Draw vehicle info", var = vars.vehicles },
	{ type = "checkbox", label = "Only draw alive players", var = vars.alive_only },
	{ type = "checkbox", label = "ESP on hover", var = vars.hover },
	{ type = "checkbox", label = "ESP outline", var = vars.outline },
	{ type = "slider",	 label = "ESP range", var = vars.range },
	{ type = "slider",	 label = "Thirdperson distance", var = vars.fov, min = 10, max = 150 },
	{ type = "checkbox", label = "Show RP name", var = vars.show_rpname },
	{ type = "checkbox", label = "Show job rank", var = vars.show_jobs },
	{ type = "checkbox", label = "Show Steam ID", var = vars.show_steamid },
	{ type = "checkbox", label = "Show health info", var = vars.show_health },
	{ type = "checkbox", label = "Show weapon", var = vars.show_weapon },
	{ type = "checkbox", label = "Show status", var = vars.show_status },
	{ type = "checkbox", label = "Show warrant", var = vars.show_warrant },
	{ type = "checkbox", label = "Draw time", var = vars.time },
	{ type = "checkbox", label = "Replicate scope zoom when spectating", var = vars.zoom },
	{ type = "checkbox", label = "Draw crosshair", var = vars.crosshair },
	{ type = "checkbox", label = "Show console kill logs", var = vars.logs },
	{ type = "checkbox", label = "Disable UIs", var = vars.disable_uis },
}

local _demo_gui
local function ToggleDemoGUI()
	if IsValid(_demo_gui) then
		_demo_gui:Close()
		_demo_gui = nil
		return
	end

	_demo_gui = vgui.Create("DFrame")
	_demo_gui:SetTitle("Demo tool GUI")
	_demo_gui:SetSize(ScaleSize(550), ScaleSize(700)) -- Should be ScaleSizeH but I don't think it matters
	_demo_gui:Center()
	_demo_gui:MakePopup()

	local yoffset = 0
	local sp = vgui.Create("DScrollPanel", _demo_gui)
	sp:Dock(FILL)
	sp:DockMargin(0,30,0,0)

	for i, data in ipairs(_gui_data) do
		if data.type == "button" and data.click then
			local button = vgui.Create("DButton", sp)
			button:SetText(data.label)
			button:SetPos(0, yoffset)
			button:SizeToContents()
			button.DoClick = data.click

			local x, y = button:GetSize()
			yoffset = yoffset + y

		elseif data.type == "checkbox" and data.var then
			local checkbox = vgui.Create("DCheckBoxLabel", sp)
			checkbox:SetText(data.label)
			checkbox:SetPos(0, yoffset)
			checkbox:SetConVar(data.var:GetName())
			checkbox:SizeToContents()

			local x, y = checkbox:GetSize()
			yoffset = yoffset + y

		elseif data.type == "slider" and data.var then
			local slider = vgui.Create("DNumSlider", sp)
			slider:SetText(data.label)
			slider:SetPos(0, yoffset)
			slider:SetConVar(data.var:GetName())
			slider:SetMin(data.min or 0)
			slider:SetMax(data.max or 7000)
			slider:SetDecimals(0)
			slider:SetWidth(300)

			local x, y = slider:GetSize()
			yoffset = yoffset + y
		end
	end

	yoffset = yoffset + 15

	local specl = vgui.Create("DLabel", sp)
	specl:SetText("Spectate target:")
	specl:SetPos(0, yoffset)
	specl:SizeToContents()

	yoffset = yoffset + 18

	local combo = vgui.Create("DComboBox", sp)
	combo:SetSortItems(false)
	combo:SetPos(0, yoffset)
	combo:SetSize(ScaleSize(400), ScaleSize(35))

	PopulateCombobox(combo)
	combo.OnSelect = function(self, index, value, data)
		SpectatePlayer(Entity(data))
	end

	local refresh = vgui.Create("DButton", sp)
	refresh:SetText("Refresh")
	refresh:SetPos(ScaleSize(405), yoffset)
	refresh:SetSize(ScaleSize(100), ScaleSize(35))
	refresh.DoClick = function()
		PopulateCombobox(combo)
	end

	yoffset = yoffset + ScaleSize(40)

	local stop = vgui.Create("DButton", sp)
	stop:SetText("Stop spectating")
	stop:SetPos(0, yoffset)
	stop:SetSize(ScaleSize(175), ScaleSize(35))
	stop.DoClick = function()
		StopSpectating()
	end
end
concommand.Add("_demo_gui", ToggleDemoGUI)

local m
local function SpectateSearch()
	local menu = vgui.Create("DFrame")
	menu:SetTitle("Search player")
	menu:SetSize(ScaleSize(500), ScaleSize(650))
	menu:Center()
	menu:MakePopup()

	menu.text = vgui.Create("DTextEntry", menu)
	menu.text:Dock(TOP)
	menu.text:SetUpdateOnType(true)
	menu.text.OnValueChange = function(_, value)
		for i, button in ipairs(menu.buttons) do
			button:Remove()
		end

		menu.buttons = {}

		local needle = value:lower()
		if needle == "" then
			return
		end

		for i, ply in player.Iterator() do
			if ply == LocalPlayer() then continue end
			local name = FormatPlayerName(ply)
			if string.find(name:lower(), needle, 1, true) == nil then continue end

			local str = ""
			local color = color_white
			if not ply:Alive() then
				str = " (dead)"
				color = Color(200, 200, 200, 255)
			elseif ply:IsDormant() then
				str = " (dormant)"
				color = Color(150, 150, 150, 255)
			end

			local j = table.insert(menu.buttons, vgui.Create("DButton", menu.scroll))
			local button = menu.buttons[j]
			button:SetText(name .. str)
			button:SetSize(ScaleSize(475), ScaleSize(25))
			button:SetContentAlignment(4)
			button:SetPos(10, (25 * #menu.buttons) - 20)

			button:SetTextColor(color)
			button:SetPaintBorderEnabled(false)
			button:SetPaintBackground(false)
			button.DoClick = function()
				SpectatePlayer(ply)
				menu:Remove()
			end
		end
	end

	menu.text.OnEnter = function()
		if #menu.buttons > 0 then
			menu.buttons[1]:DoClick()
		end
	end

	menu.scroll = vgui.Create("DScrollPanel", menu)
	menu.scroll:Dock(FILL)
	menu.buttons = {}
end

local function OpenModal(prompt, action)
	local menu = vgui.Create("DFrame")
	menu:SetTitle(prompt)
	menu:SetSize(ScaleSize(250), ScaleSize(100))
	menu:Center()
	menu:MakePopup()

	-- @type DTextEntry
	local text = vgui.Create("DTextEntry", menu)
	text:Dock(TOP)

	text.OnEnter = function(_, value)
		action(value)
		menu:Close()
	end
end

local function ToggleThirdPerson()
	vars.thirdperson = not vars.thirdperson
	ResetUI()
end

local function InitDemoPanel(_, bind, pressed, code)
	if not pressed or code ~= MOUSE_RIGHT then return end

	m = DermaMenu()
	m:AddOption("None")
	m:AddOption("Options", ToggleDemoGUI)
	m:AddOption("Toggle noclip", ToggleDemoNoclip)
	m:AddOption("Toggle thirdperson", ToggleThirdPerson)

	-- Spectate
	local spec = m:AddSubMenu("Spectate")
	spec:AddOption("Stop", StopSpectating)

	local list = spec:AddSubMenu("Nearby")
	PopulateCombobox(list, function(ply) SpectatePlayer(ply) end)
	spec:AddOption("Search", SpectateSearch)

	--[[
	spec:AddOption("By Steam ID", function()
		OpenModal("Enter Steam ID:", function(value)
			local ply = player.GetBySteamID(value)
			if ply then
				SpectatePlayer(ply)
			end
		end)
	end)
	]]

	spec:AddOption("Toggle window", ToggleWindow)

	-- Demo
	if is_playing_demo then
		local demo = m:AddSubMenu("Demo")
		demo:AddOption("Pause/resume", function() RunConsoleCommand("demo_togglepause") end)

		local timescale = demo:AddSubMenu("Timescale")
		demo:AddOption("Open demoui", function() RunConsoleCommand("demoui") end)
		demo:AddOption("stopsound", function() RunConsoleCommand("stopsound") end)
		demo:AddOption("Seek to time", function()
			OpenModal("Enter time MM:SS", function(value)
				local min, sec = string.match(value, "(%d+):(%d+)")
				if min ~= nil and sec ~= nil then
					local total_seconds = min * 60 + sec
					local tps = 1 / engine.TickInterval()
					local tick = total_seconds * tps
					RunConsoleCommand("demo_gototick", tostring(math.floor(tick)))
				end
			end)
		end)

		timescale:AddOption("0.1x", function() RunConsoleCommand("demo_timescale", "0.1") end)
		timescale:AddOption("0.25x", function() RunConsoleCommand("demo_timescale", "0.25") end)
		timescale:AddOption("0.5x", function() RunConsoleCommand("demo_timescale", "0.5") end)
		timescale:AddOption("0.75x", function() RunConsoleCommand("demo_timescale", "0.75") end)
		timescale:AddOption("1x / reset", function() RunConsoleCommand("demo_timescale", "1") end)
		timescale:AddOption("2x", function() RunConsoleCommand("demo_timescale", "2") end)
		timescale:AddOption("3x", function() RunConsoleCommand("demo_timescale", "3") end)
		timescale:AddOption("4x", function() RunConsoleCommand("demo_timescale", "4") end)
		timescale:AddOption("5x", function() RunConsoleCommand("demo_timescale", "5") end)
		timescale:AddOption("7.5x", function() RunConsoleCommand("demo_timescale", "7.5") end)
		timescale:AddOption("10x", function() RunConsoleCommand("demo_timescale", "10") end)
	end

	-- Voice
	local voice = m:AddSubMenu("Voice")
	voice:AddOption("Default / reset", function() target.voice = nil end)
	local players = voice:AddSubMenu("Isolate voice of")
	PopulateCombobox(players, function(ply) target.voice = ply:EntIndex() end)

	-- Quick Actions
	if vars.noclip or not vars.spectate then
		local actions = m:AddSubMenu("Quick Actions")

		local tr = util.TraceLine({
			start = GetEyePos(),
			endpos = GetEyePos() + (GetEyeAngles():Forward() * 8192),
			filter = LocalPlayer()
		})

		local ply = tr.Entity
		if IsValid(tr.Entity) and not tr.Entity:IsPlayer() then
			if tr.Entity:IsRagdoll() then
				-- I don't know how to get the owner of a ragdoll, soz
			elseif tr.Entity:IsVehicle() then
				ply = tr.Entity:GetNWEntity("owner", nil)
			end
		end

		if IsValid(ply) and ply:IsPlayer() and ply ~= LocalPlayer() then
			actions:AddOption("Spectate", function() SpectatePlayer(ply) end)
			actions:AddOption("Copy SteamID", function() SetClipboardText(ply:SteamID()) end)
			actions:AddOption("Isolate voice", function() target.voice = ply:EntIndex() end)
		else
			actions:AddOption("Aim at a player")
		end
	end

	input.SetCursorPos(ScrW() / 2, ScrH() / 2)
	m:SetPos(ScrW() / 2, ScrH() / 2)
	m:MakePopup()
end
hook.Add("PlayerBindPress", "demo_godstick", InitDemoPanel)

-- hook stuff
surface.CreateFont("demo_stext", {
	font = "Roboto",
	size = ScaleSize(15),
	weight = 400,
	antialias = true
})

surface.CreateFont("demo_mtext", {
	font = "Roboto",
	size = ScaleSize(18),
	weight = 400,
	antialias = true
})

surface.CreateFont("demo_text", {
	font = "Roboto",
	size = ScaleSize(20),
	weight = 400,
	antialias = true
})

surface.CreateFont("demo_info", {
	font = "Roboto",
	size = ScaleSize(25),
	weight = 400,
	antialias = true
})

surface.CreateFont("demo_info_big", {
	font = "Roboto",
	size = ScaleSize(30),
	weight = 700,
	antialias = true
})


local function DrawText(font, x, y, text, color)
	draw.SimpleTextOutlined(text, font, x, y, color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, color.a))
end

player_GetBloodLevel = player_GetBloodLevel or PLAYER.GetBloodLevel
player_GetBleedingAmount = player_GetBleedingAmount or PLAYER.GetBleedingAmount

local function DrawClientESP(ply)
	local font = "demo_mtext"
	local color = team.GetColor(ply:Team())
	local c = ply:WorldSpaceCenter():ToScreen()

	if not player_Alive(ply) then
		if vars.alive_only:GetBool() then return end

		local ragdoll = ply:GetNWEntity("ragdoll", nil)
		if IsValid(ragdoll) then
			c = ragdoll:WorldSpaceCenter():ToScreen()
		end
	end

	local base = ScaleSize(20)
	local yoffset = -base
	if vars.show_rpname:GetBool()  then
		DrawText(font, c.x, c.y + yoffset, ply:GetRPName(), color)
		yoffset = yoffset + base
	end

	local player_name = ply:Nick()
	local job = ply:GetShortJobTitle()
	if vars.show_jobs:GetBool() and job ~= "Citizen" then
		player_name = job .. " | " .. player_name
	end

	DrawText(font, c.x, c.y + yoffset, player_name, color)
	yoffset = yoffset + base

	if vars.show_steamid:GetBool()	then
		DrawText(font, c.x, c.y + yoffset, ply:SteamID(), color)
		yoffset = yoffset + base
	end

	if vars.show_health:GetBool() then
		local str = ""

		if player_Alive(ply) then
			if ply:Health() > 0 and ply:Health() ~= ply:GetMaxHealth() then
				str = ply:Health() .. " HP"
			end

			if ply:Armor() > 0 and ply:Armor() ~= ply:GetMaxArmor() then
				str = str ..  " " .. ply:Armor() .. " AP"
			end
		else
			if ply:CanBeRevived() then
				str = "Time left: " .. string.ToMinutesSeconds(ply:GetReviveTime() - CurTime())
			else
				str = "Dead"
			end
		end

		if str ~= "" then
			DrawText(font, c.x, c.y + yoffset, str, color)
			yoffset = yoffset + base
		end
	end

	if vars.show_status:GetBool() then
		local alive = player_Alive(ply)
		local crippled = ply:GetNWBool("crippled")
		local splint = ply:GetNWBool("hasSplint")

		local text = {}
		if (crippled or splint) and alive then
			table.insert(text, crippled and "Crippled" or "Splinted")
		end

		local last_shot = ply:GetNWFloat("LastShot", nil)
		if last_shot and CurTime() - last_shot < 75 then
			table.insert(text, "shot")
		end

		if player_GetBleedingAmount(ply) > 0 and alive then
			table.insert(text, "bleeding")
		end

		if #text > 0 then
			DrawText(font, c.x, c.y + yoffset, table.concat(text, ", "), Color(255, 50, 50, 255))
			yoffset = yoffset + base
		end
	end

	local search = ply:HasSearchWarrant()
	local warranted = ply:IsWarranted()
	local bolo = ply:HasBolo()
	local robber = ply:GetNWBool("robber", false)
	if vars.show_warrant:GetBool() and (search or warranted or bolo or robber) then
		local str = robber and "Bank Robber" or "Warranted"
		if search or bolo then
			str = search and "Search warrant" or "BOLO"
		end

		DrawText(font, c.x, c.y + yoffset, str, Color(255, 50, 50, 255))
		yoffset = yoffset + base
	end

	-- Untested, not sure if this works correctly
	if ply:GetNWBool("InEvent", false) then
		DrawText(font, c.x, c.y + yoffset, "Event player", Color(200, 200, 100, 255))
		yoffset = yoffset + base
	end

	if vars.show_weapon:GetBool() then
		local str = nil

		local swep = ply:GetActiveWeapon()
		local restrained = ply:GetNWInt("restrained", 0)
		if restrained == 1 then
			str = "Cuffed"
		elseif restrained == 2 then
			str = "Ziptied"
		elseif IsValid(swep) and swep:GetClass() ~= "roleplay_keys" then
			str = swep.PrintName or swep:GetClass()
		end

		if str then
			DrawText(font, c.x, c.y + yoffset, str, restrained and Color(255, 175, 100, 255) or color)
			yoffset = yoffset + base
		end
	end
end

local function DrawVehicleESP(ent, hovered)
	if not vars.vehicles:GetBool() then return end

	local font = "demo_mtext"
	local c = ent:WorldSpaceCenter():ToScreen()
	local color = color_white

	local base = ScaleSize(20)
	local yoffset = -base

	local owner = ent:GetNWEntity("owner", nil)
	if hovered and IsValid(owner) and owner:IsPlayer() then
		DrawText("demo_text", c.x, c.y + yoffset, "Owned by " .. FormatPlayerName(owner), color)
		yoffset = yoffset + base
	end

	local health = ent:Health()
	if vars.show_health:GetBool() and health > 0 and health ~= ent:GetMaxHealth() then
		DrawText(font, c.x, c.y + yoffset, health .. " HP", color)
		yoffset = yoffset + base
	end

	local velocity = ent:GetVelocity():Length()
	if velocity > 5 then
		local speed = math.Round(velocity / 17.6)

		DrawText(font, c.x, c.y + yoffset, tostring(speed) .. " MPH", color)
		yoffset = yoffset + base
	end
end

local function GetKeyCode(str, default)
	local bind = input.LookupBinding(str)
	if bind then
		local key = input.GetKeyCode(bind)

		if key then
			return key
		end
	end

	return default
end

local allow_keyboard = true
hook.Add("OnTextEntryGetFocus", "demo_get_focus", function()
	allow_keyboard = false
end)

hook.Add("OnTextEntryLoseFocus", "demo_lose_focus", function()
	allow_keyboard = true
end)

player_Alive = player_Alive or PLAYER.Alive
local function HUDPaintESP()
	local scrw = ScrW()
	local scrh = ScrH()

	-- Preserve audio when the local player is dead:
	-- Due to "demo_recordcommands" always being set to 1, "soundfade" is being executed constantly to prevent players from hearing stuff when dead.
	-- Making this one of the only viable ways to go about it.
	if not player_Alive(LocalPlayer()) then
		RunConsoleCommand("soundfade", "0", "0")
	end

	if is_playing_demo and vars.time:GetBool() then
		local time = string.ToMinutesSeconds(engine.GetDemoPlaybackTick() * engine.TickInterval())
		local total = string.ToMinutesSeconds(engine.GetDemoPlaybackTotalTicks() * engine.TickInterval())
		DrawText("demo_info_big", scrw * .92, scrw * .05, time .. " / " .. total, color_white)
	end

	if vars.crosshair:GetBool() then
		surface.DrawCircle(scrw / 2, scrh / 2, 3, color_white)
	end

	-- Being in noclip and tabbing out sometimes makes the camera spin out like crazy. This is mainly for Linux. The fix for Windows is much simpler.
	local in_focus = system.HasFocus()
	if vars.focuslock then
		if not in_focus and not mouse.lost_focus then
			mouse.lost_focus = true
		elseif in_focus and mouse.lost_focus then
			DrawText("demo_info_big", scrw / 2, scrh * 0.2, "Press mouse1 to regain focus", Color(255, 0, 0, 255))

			if input.IsMouseDown(MOUSE_LEFT) then
				mouse.lost_focus = false
				input.SetCursorPos(scrw / 2, scrh / 2)
			end
		end
	end

	if vars.noclip or vars.spectate or vars.thirdperson then
		local allow = in_focus
		if vars.focuslock then
			allow = (mouse.lost_focus == false)
		end

		if not IsValid(_demo_gui) and not IsValid(m) and allow and not vgui.CursorVisible() then
			local cx, cy = scrw / 2, scrh / 2
			local x, y = input.GetCursorPos()
			mouse.dx = mouse.dx + (x - cx)
			mouse.dy = mouse.dy + (y - cy)
			input.SetCursorPos(cx, cy)
		end

		-- Don't move in noclip when we're typing something
		if allow_keyboard then
			local speed = 450
			if input.IsKeyDown(GetKeyCode("+speed", KEY_LSHIFT)) then speed = speed * 2 end
			if input.IsKeyDown(GetKeyCode("+walk", KEY_LSHIFT)) then speed = speed / 2 end

			-- Perhaps a version of this using GetKeyCode for everything would've been better.
			-- Although, it won't be ideal for people that use nulls or similar aliases
			local forward = mouse.ang:Forward()
			if input.IsKeyDown(KEY_W) then mouse.velocity = mouse.velocity + forward * speed end
			if input.IsKeyDown(KEY_S) then mouse.velocity = mouse.velocity - forward * speed end

			local right = mouse.ang:Right()
			if input.IsKeyDown(KEY_D) then mouse.velocity = mouse.velocity + right * speed end
			if input.IsKeyDown(KEY_A) then mouse.velocity = mouse.velocity - right * speed end

			local up = Vector(0, 0, 1.25) -- Allow going up when holding space, looking straight down, and moving forward
			if input.IsKeyDown(KEY_SPACE) then mouse.velocity = mouse.velocity + up * speed end
			if input.IsKeyDown(GetKeyCode("+duck", KEY_LCONTROL)) then mouse.velocity = mouse.velocity - up * speed end
		end
	end

	-- Print spectator info
	if vars.spectate and IsValid(target.ent) then
		local y = scrh * 0.03
		DrawText("demo_info_big", scrw / 2, y, string.format("Spectating %s", FormatPlayerName(target.ent)), color_white)
		y = y + draw.GetFontHeight("demo_info_big")

		local color = color_white
		local str = "<no item>"
		if target.ent:IsDormant() then
			-- For some reason, PrintName isn't always valid when the weapon and/or its owner are dormant
			str = "Dormant"
			color = Color(255, 0, 0, 255)
		else
			local swep = target.ent:GetActiveWeapon()
			if IsValid(swep) then
				str = swep.PrintName or (swep.GetPrintName and swep:GetPrintName()) or swep:GetClass()
			end
		end

		DrawText("demo_info_big", scrw / 2, y, str, color)

		if vars.window then
			drawing_window = true
			local x = scrw * .02
			local y = scrh * .25

			local w = scrw * .3
			local h = scrh * .3

			render.RenderView({
				origin = target.ent:EyePos(),
				angles = target.ent:EyeAngles(),
				x = x, y = y,
				w = w, h = h,
				fov = GetFOV(),
				drawviewmodel = false,
				drawviewer = true,
			})
			drawing_window = false
		end
	end

	local tr = util.TraceLine({
		start = GetEyePos(),
		endpos = GetEyePos() + (GetEyeAngles():Forward() * 8192),
		filter = GetTarget(),
	})

	if vars.enabled:GetBool() then
		local target = GetTarget()
		local range = vars.range:GetInt() ^ 2

		for i, ent in ents.Iterator() do
			local ply = ent
			if ent:IsPlayer() and not ply:IsDormant() and (vars.noclip or vars.thirdperson or ply ~= target) and GetEyePos():DistToSqr(ply:GetPos()) <= range then
				DrawClientESP(ply)
			elseif ent:IsVehicle() and not ent:IsDormant() and GetEyePos():DistToSqr(ent:GetPos()) <= range then
				DrawVehicleESP(ent, tr.Entity == ent)
			end
		end
	elseif vars.hover:GetBool() and vars.noclip then -- we only really care about hover ESP if we're in noclip
		if IsValid(tr.Entity) and tr.Entity:IsPlayer() then
			DrawClientESP(tr.Entity)
		end
	end
end
hook.Add("HUDPaint", "demo_draw_esp", HUDPaintESP)

local function UpdateMouseData()
	local scale = 1 / math.max(1, math.Round(RealFrameTime() / engine.TickInterval()))
	local mult = 2.3

	mouse.dx = mouse.dx * mult
	mouse.dy = mouse.dy * mult

	-- Scale by time to 60 FPS. Demos call CalcView and HUDPaint more than normal
	mouse.ang.y = mouse.ang.y - (mouse.yaw:GetFloat() * (mouse.dx * mouse.sens:GetFloat())) * scale
	mouse.ang.p = math.Clamp(mouse.ang.p + (mouse.pitch:GetFloat() * (mouse.dy * mouse.sens:GetFloat())) * scale, -89, 89)
	mouse.ang.r = 0 -- we don't want any roll
	mouse.ang:Normalize() -- Probably unnecessary, but it doesn't hurt to call

	mouse.dx = 0
	mouse.dy = 0
end

local function GetCalcViewData(ply, pos, ang, fov)
	if vars.noclip then
		UpdateMouseData()

		-- Would've been cooler if CGameMovement::FullNoClipMove was implemented instead
		mouse.cam = mouse.cam + mouse.velocity * RealFrameTime()
		mouse.velocity:Zero()
		return { origin = mouse.cam, angles = mouse.ang, fov = fov, drawviewer = true }
	elseif vars.spectate and not vars.window then
		return { origin = GetEyePos(), angles = GetEyeAngles(), fov = GetFOV(), drawviewer = true }
	end

	if vars.thirdperson then
		return { origin = pos, angles = ang, fov = fov }
	end
end

local function CalcView(ply, pos, ang, fov)
	local data = GetCalcViewData(ply, pos, ang, fov)
	if not data then return end

	-- Thirdperson logic
	if not vars.noclip and vars.thirdperson then
		-- Reuse our noclip handling data for thirdperson
		UpdateMouseData()
		data.angles = mouse.ang -- Orbit around our "fake" viewangles

		-- Move the camera back and slightly up
		data.origin = data.origin + (data.angles:Forward() * -vars.fov:GetFloat()) + (data.angles:Up() * 4)
		data.drawviewer = true
	end

	return data
end
hook.Add("CalcView", "demo_calc_view", CalcView)

local function DrawOutlines()
	if drawing_window or not vars.outline:GetBool() then return end

	local target = GetTarget()
	local range = vars.range:GetInt() ^ 2

	local teams = {}
	for i, ply in player.Iterator() do
		-- We don't want to draw the outline for players who are dead. Their SetupBones does not correspond to their ragdoll's SetupBones and it looks weird.
		if IsValid(ply) and player_Alive(ply) and not ply:IsDormant() and (vars.noclip or ply ~= target) and GetEyePos():DistToSqr(ply:GetPos()) <= range then
			local ply_team = ply:Team()
			teams[ply_team] = teams[ply_team] or {}
			table.insert(teams[ply_team], ply)
		end
	end

	for ply_team, ents in pairs(teams) do
		halo.Add(ents, team.GetColor(ply_team), 2, 2, 1, true, true)
	end
end
hook.Add("PreDrawHalos", "demo_draw_outlines", DrawOutlines)

-- Don't draw the spectatee (if that's even a real word)
local function PrePlayerDraw(ply)
	-- render.RenderView pretty much renders the game again. If we didn't have this here, it would draw the target entity's clothings and player model
	if drawing_window and ply == target.ent then
		return true
	end

	if vars.spectate and not vars.window and not vars.thirdperson and IsValid(target.ent) and target.ent == ply then
		return true
	end
end
hook.Add("PrePlayerDraw", "demo_manage_player_draw", PrePlayerDraw)

local function EntityKilled(data)
	if not vars.logs then
		return
	end

	local killer = Entity(data.entindex_attacker)
	local victim = Entity(data.entindex_killed)
	local weapon = Entity(data.entindex_inflictor)

	if not IsValid(killer) or not IsValid(victim) then
		return
	end

	local str = ""
	if IsValid(weapon) and not weapon:IsPlayer() then
		str = "using " .. (weapon.PrintName or (weapon.GetPrintName and weapon:GetPrintName()) or weapon:GetClass() or "unknown")
	end

	MsgC(Color(255, 30, 30, 255), string.format("[#%d] Player %s killed %s %s\n", engine.TickCount(), FormatPlayerName(killer), FormatPlayerName(victim), str))
end
gameevent.Listen("entity_killed")
hook.Add("entity_killed", "demo_kill_logs", EntityKilled)

-- PrintTable(hook.GetTable())
hook.Remove("PlayerPostThink", "PlayerHeartbeat")
hook.Remove("RenderScreenspaceEffects", "VariousVisualEffects")
hook.Remove("RenderScreenspaceEffects", "StunEffect")

-- If you wish to add more UIs to block, run the following whilst in a demo, with the menu that you wish to blacklist open:
--[[
	found = {}
	for k, v in pairs(vgui.GetAll()) do found[v:GetName()] = 1 end
	PrintTable(found)
]]
local overrides = {
	"perp2_dialog",
	"chemical_table_panel",
	"ph_tv_menu",
	"perpheads_act_wheel",
	"perp_animation_hud",
	"perpheads_armory_frame",
	"perpheads_armory",
	"BillboardMenu",
	"buddy_preferences_top",
	"SendAdvertMenu",
	"perp2_drown",
	"perp2_blood",
	"PoliceComputerPanel"
}

cached_overrides = cached_overrides or {}
for i, s in ipairs(overrides) do
	local t = vgui.GetControlTable(s)
	if not t then continue end

	cached_overrides[s] = cached_overrides[s] or { t.Paint, t.MakePopup, t.Show }
	t["Paint"] = function(...)
		if vars.disable_uis:GetBool() then return end
		cached_overrides[s][1](...)
	end

	t["MakePopup"] = function(...)
		if vars.disable_uis:GetBool() then return end
		cached_overrides[s][2](...)
	end

	t["Show"] = function(...)
		if vars.disable_uis:GetBool() then return end
		cached_overrides[s][3](...)
	end
end

-- Calling vgui.Create makes a copy of the control table. This resets most menus.
ResetUI()

function GAMEMODE:ScoreboardShow() end
function GAMEMODE:ScoreboardHide() end

local function ShouldOverride(ply)
	return ply == LocalPlayer() and (vars.noclip or (vars.spectate and IsValid(target.ent)) or vars.thirdperson)
end

player_SetVoiceVolumeScale = player_SetVoiceVolumeScale or PLAYER.SetVoiceVolumeScale
function PLAYER:SetVoiceVolumeScale(value)
	if target.voice then
		return player_SetVoiceVolumeScale(self, self:EntIndex() == target.voice and 1 or 0)
	end

	return player_SetVoiceVolumeScale(self, value)
end

function PLAYER:Alive()
	if ShouldOverride(self) then
		return true
	end

	return player_Alive(self)
end

function PLAYER:GetBloodLevel()
	if ShouldOverride(self) then
		return 100
	end

	return player_GetBloodLevel(self)
end

function PLAYER:GetBleedingAmount()
	if ShouldOverride(self) then
		return 0
	end

	return player_GetBleedingAmount(self)
end

if is_playing_demo then
	RunConsoleCommand("demo_pause")
end


