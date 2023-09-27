local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local TableToString = require(script:WaitForChild("TableToString"))

local function fixNestedTable(value: {})
	if typeof(value) == "table" then
		local metatable = getmetatable(value)

		if metatable then
			value = {}

			for i, v in metatable.__index do
				value[tostring(i)] = fixNestedTable(v)
			end
		end
	end

	return value
end

local remote = script:WaitForChild("RemoteEvent")
local module = {}
module.EventCooldown = 0
module.Memory = {}

function module.new(key: any, notInMemory: boolean): DynamicTable
	if notInMemory ~= true then
		if module.Memory[key] then
			return module.Memory[key]
		end
	end
	
	local events: {BindableEvent} = {}
	local proxy = {}
	
	function proxy:GetPropertyChangedSignal(index: any): RBXScriptSignal
		if events[index] == nil then
			events[index] = Instance.new("BindableEvent")
		end
		
		return events[index].Event
	end
	
	local meta = {}
	meta.__index = proxy
	meta.__newindex = function(t, i, v)
		if typeof(v) == "table" then
			proxy[i] = module.new(i, true)
			
			for property, value in v do
				proxy[i][property] = value
			end
		else
			proxy[i] = v
		end
		
		if events[i] then
			events[i]:Fire(v)
		end
		
		if RunService:IsEdit() ~= true and RunService:IsServer() and typeof(v) ~= "function" then
			task.delay(module.EventCooldown, function()
				remote:FireAllClients("set", key, i, v)
			end)

			module.EventCooldown += 0.5
		end
	end
	
	meta.__tostring = function(t)
		return TableToString(fixNestedTable(t))
		
		--[[
		local str = "{"
		for i, v in proxy do
			if typeof(v) ~= "function" then
				str = str .. tostring(i) .. ": " .. tostring(v) .. ", "
			end
		end
		str = string.sub(str, 1, #str-2) .. "}"
		return str
		]]
	end
	
	local class = setmetatable({}, meta)
	
	if notInMemory ~= true then
		module.Memory[key] = class
	end
	
	return class
end

local fakeProxy = {}
function fakeProxy:GetPropertyChangedSignal(index: any): RBXScriptSignal
	
end
export type DynamicTable = typeof(fakeProxy)

if RunService:IsEdit() ~= true then
	if RunService:IsClient() then
		-- client
		local ready = Instance.new("BindableEvent")

		remote.OnClientEvent:Connect(function(action: string, ...)
			if action == "set" then
				local key: any, i: any, v: any = ...

				module.new(key)[i] = v
			elseif action == "ready" then
				ready:Fire()
			end
		end)

		remote:FireServer() -- tell server that client is ready to receive information
		ready.Event:Wait() -- loaded dynamic tables on client
		ready:Destroy()
	elseif RunService:IsServer() then
		-- server
		remote.OnServerEvent:Connect(function(player)
			for key: any, class in module.Memory do
				for property, value in getmetatable(class).__index do
					if typeof(value) ~= "function" then
						remote:FireClient(player, "set", key, property, fixNestedTable(value))
					end
				end
			end
			remote:FireClient(player, "ready")
		end)
	end
end

RunService.Heartbeat:Connect(function(delta)
	module.EventCooldown = math.max(module.EventCooldown - delta, 0)
end)

return module
