-- The HTTP contract has no streaming byte counter. Show elapsed waiting time,
-- never an invented percentage. One pending timer per active transfer.
local M={}

function M.start(ctx,size,notify)
  local active=true
  local started=ctx.clock and ctx.clock:millis() or 0
  local label="正在下载"..(size and size~="" and (" "..size) or "")
  notify(ctx,label.." · 已等待 0 秒")
  local function tick(c)
    if not active then return end
    local elapsed=((c.clock:millis()-started)&0x7FFFFFFF)//1000
    notify(c,label.." · 已等待 "..elapsed.." 秒")
    c:after(5000,tick)
  end
  if ctx.after and ctx.clock then ctx:after(5000,tick) end
  return {stop=function() active=false end}
end

return M
