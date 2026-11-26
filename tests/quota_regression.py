from pathlib import Path
from lupa.lua54 import LuaRuntime
l=LuaRuntime()
l.execute('package.path="xtapp/?.lua;"..package.path')
l.execute('''
local quota=require("quota")
local account={id="1",key="k"}
local today={valid=true,year=2026,month=11,day=24}
ctx={state={account=account,zlib_origin="https://test.example"},clock={now=function() return today end},
json={decode=function(self,s) return result end},invalidate=function() end}
function perform(c,options,callback) pending=options;response=function(r) callback(c,r) end end
quota.refresh(ctx,perform)
assert(pending.url=="https://test.example/eapi/user/profile" and pending.timeout_ms==5000)
assert(pending.headers["remix-userkey"]=="k")
result={success=1,user={id=1,downloads_today=1,downloads_limit=10,isPremium=0}}
response({ok=true,status=200,body="profile"})
assert(quota.label(ctx)=="普通账号 · 今日 1/10 · 剩余 9 次")
quota.refresh(ctx,perform);response({ok=true,status=401,body="profile"})
assert(ctx.state.account==account and quota.label(ctx):find("上次",1,true))
today.day=25;assert(quota.label(ctx):find("待刷新",1,true))
result.user={id=1,downloads_today=50,downloads_limit=999,isPremium=1}
quota.refresh(ctx,perform);response({ok=true,status=200,body="profile"})
assert(quota.label(ctx)=="Premium · 今日 50/999 · 剩余 949 次")
ctx.state.account={id="2",key="new"};assert(quota.label(ctx)=="下载额度待查询")
-- A reply for an earlier account cannot replace the current account's quota.
ctx.state.account=account;quota.refresh(ctx,perform);ctx.state.account={id="2",key="new"}
response({ok=true,status=200,body="profile"});assert(ctx.state.quota.id=="1")
ctx.state.account=nil;assert(quota.label(ctx)=="登录后显示下载额度")
''')
print('PASS quota normal/Premium/remaining/day rollover/failure cache/account isolation; no quota hardcoding')
