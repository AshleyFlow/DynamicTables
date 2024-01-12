local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local BridgeNet2 = require(script:WaitForChild("BridgeNet2"))
local TableLib = require(script:WaitForChild("TableLib"))
local Signal = require(script:WaitForChild("Signal"))

local bridge = BridgeNet2.ReferenceBridge("DynamicTables")
local tables = {}

function Main(key: string)
	if tables[key] then return tables[key] end

	local length = 0
	local t = {}

	local userdata = newproxy(true)
	local events = {}
	local array = {}
	local changesHappened = false
	local changes = {}
	local meta = getmetatable(userdata)
	local ignore = {}

	if RunService:IsServer() then
		RunService.Heartbeat:Connect(function()
			if changesHappened == false then return end

			bridge:Fire(BridgeNet2.AllPlayers(), {1, key, changes})

			changes = {}
			changesHappened = false
		end)
	end

	meta.__index = array
	meta.__newindex = function(_, i, v)
		local old = array[i]
		
		changes[i] = v
		changesHappened = true
		array[i] = v

		if old == nil and v ~= nil then
			length += 1
			t[length] = i
		elseif old ~= nil and v == nil then
			length -= 1
			t[length] = nil
		end

		if events[i] then
			events[i]:Fire(old, v)
		end
	end

	meta.__tostring = function(_)
		return key or tostring(array)
	end

	meta.__len = function(_)
		-- returns a number when # is used on table
		return length
	end

	meta.__iter = function(_)
		-- used in for i, v loops
		local i = 0

		return function()
			i = i + 1

			if i <= length then
				return t[i], array[t[i]]
			end
		end
	end

	function array:Changed(index: any): RBXScriptSignal
		if events[index] then
			return events[index]
		else
			local event = Signal.new()

			events[index] = event

			return event
		end
	end

	function array:GetData()
		return array
	end

	ignore[array.Changed] = true
	ignore[array.GetData] = true

	if key then
		tables[key] = userdata
	end

	return userdata
end

if RunService:IsServer() then
	local function PlayerAdded(player: Player)
		for i, v in tables do
			bridge:Fire(player, {0, i, v:GetData()})
		end
	end

	for i, v in Players:GetPlayers() do
		PlayerAdded(v)
	end

	Players.PlayerAdded:Connect(PlayerAdded)
else
	bridge:Connect(function(info)
		local operation, key = table.unpack(info)
		local dynamicTable = Main(key)

		if operation == 0 then
			-- create
			local i, v = table.unpack(info, 3)
			if v == nil then
				local v = i
				for i, v in v do
					dynamicTable[i] = v
				end
			else
				dynamicTable[i] = v
			end
		else
			-- update
			local changes = table.unpack(info, 3)
			for i, v in changes do
				dynamicTable[i] = v
			end
		end
	end)
end

return Main
