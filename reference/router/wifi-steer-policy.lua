local M = {}
M.aps = {'phy0-ap0', 'phy2-ap0'}
M.interval = 3
M.cooldown = 1800

function M.busy(a, b)
 if not a or a.freq ~= b.freq then return nil end
 local active, busy = b.active - a.active, b.busy - a.busy
 if active <= 0 or busy < 0 or busy > active then return nil end
 return busy / active
end

function M.supports_btm(station)
 local caps = station and station.extended_capabilities
 return station and station.authorized and station.assoc and caps and
        type(caps[3]) == 'number' and math.floor(caps[3] / 8) % 2 == 1
end

function M.has_player(stations, players)
 for mac in pairs(players) do
  if stations[mac] then return true end
 end
 return false
end

-- An interrupted sample sequence or changed direction starts a new streak.
function M.candidates(previous, current, streak, active, protected, blocked)
 local choices, next_streak = {}, {}
 if not previous then return choices, next_streak end
 local dt = current.at - previous.at
 if dt < 1 or dt > 2 * M.interval + 1 then return choices, next_streak end
 for i, src in ipairs(M.aps) do
  local dst = M.aps[3-i]
  local a, b = previous[src], current[src]
  local sb = M.busy(a, b)
  local tb = M.busy(previous[dst], current[dst])
  if sb and tb and tb <= 0.45 and sb - tb >= 0.08 and
     M.has_player(b.stations, active) and not M.has_player(current[dst].stations, protected) then
   for mac, sta in pairs(b.stations) do
    local old = a.stations[mac]
    if old and not protected[mac] and not blocked[mac] and not current[dst].stations[mac] and
       M.supports_btm(sta) and old.bytes and sta.bytes and old.bytes.tx and sta.bytes.tx then
     local rate = (sta.bytes.tx - old.bytes.tx) * 8e-6 / dt
     if rate >= 40 then
      local key = src .. '/' .. mac
      next_streak[key] = (streak[key] or 0) + 1
      if next_streak[key] >= 3 then
       choices[#choices+1] = {mac=mac, src=src, dst=dst, rate=rate, srcBusy=sb, dstBusy=tb}
      end
     end
    end
   end
  end
 end
 table.sort(choices, function(x,y) return x.rate > y.rate end)
 return choices, next_streak
end

return M
