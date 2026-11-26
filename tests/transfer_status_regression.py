from lupa.lua54 import LuaRuntime
l=LuaRuntime();l.execute('package.path="xtapp/?.lua;"..package.path')
l.execute('''
local transfer=require("transfer_status")
local now=2147482000
local ctx={clock={millis=function() return now end},after=function(self,ms,cb) assert(ms==5000);next_tick=cb end}
local function notify(c,text) last=text;count=(count or 0)+1 end
local task=transfer.start(ctx,"6 MB",notify)
assert(last=="正在下载 6 MB · 已等待 0 秒")
now=(now+5000)&0x7FFFFFFF;next_tick(ctx)
assert(last=="正在下载 6 MB · 已等待 5 秒")
now=(now+5000)&0x7FFFFFFF;next_tick(ctx)
assert(last=="正在下载 6 MB · 已等待 10 秒")
task:stop();local n=count;last="下载成功";next_tick(ctx)
assert(count==n and last=="下载成功")
local task2=transfer.start(ctx,nil,notify);task2:stop();last="下载失败";next_tick(ctx)
assert(last=="下载失败")
''')
print('PASS elapsed display, 5s refresh, clock wrap, completion/error cannot be overwritten by old timers')
