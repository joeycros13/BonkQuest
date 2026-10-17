--!strict
-- Signal: a small pure-Luau event used by tracks, tweens and motions.
--
-- No BindableEvent or instance behind it, so firing is cheap and values pass
-- through untouched. Handlers run in the order they connected; one that errors
-- is reported and the rest still run.
--
--   local s = Signal.new()
--   local c = s:Connect(function(x) print(x) end)
--   s:Fire(1)        s:Once(fn)        s:Wait()        c:Disconnect()

local Signal = {}
Signal.__index = Signal

export type Connection = { Connected: boolean, Disconnect: (Connection) -> () }

function Signal.new()
	return setmetatable({ _handlers = {} :: { any } }, Signal)
end

function Signal:Connect(fn: (...any) -> ()): Connection
	local handlers = self._handlers
	local entry: any = { fn = fn, Connected = true }
	function entry.Disconnect(_self: any)
		if not entry.Connected then
			return
		end
		entry.Connected = false
		local index = table.find(handlers, entry)
		if index then
			table.remove(handlers, index)
		end
	end
	table.insert(handlers, entry)
	return entry
end

function Signal:Once(fn: (...any) -> ()): Connection
	local connection: Connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		fn(...)
	end)
	return connection
end

function Signal:Fire(...: any)
	local handlers = self._handlers
	if #handlers == 0 then
		return
	end
	-- A copy, so handlers may connect or disconnect while firing.
	for _, entry in table.clone(handlers) do
		if entry.Connected then
			local ok, err = pcall(entry.fn, ...)
			if not ok then
				warn("[Animation.Signal] handler error: " .. tostring(err))
			end
		end
	end
end

-- Yield until the next Fire; returns its values.
function Signal:Wait(): ...any
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:DisconnectAll()
	for _, entry in self._handlers do
		entry.Connected = false
	end
	table.clear(self._handlers)
end

return Signal
