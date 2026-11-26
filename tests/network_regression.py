from pathlib import Path
from lupa.lua54 import LuaRuntime
l=LuaRuntime()
l.execute('package.path="xtapp/?.lua;"..package.path')
l.execute("""
function makefont(px)
 return {px=px,ascent=px-3,line_height=px+4,
 measure=function(self,t) return utf8.len(t)*px end,
 layout=function(self,t,w,h)
  local count=math.max(0,math.floor(w/px)*math.floor(h/(px+4)))
  local ending=utf8.offset(t,math.min(utf8.len(t),count)+1) or (#t+1)
  local lines=math.ceil(math.min(utf8.len(t),count)/math.max(1,math.floor(w/px)))
  return lines,lines*(px+4),ending-1
 end}
end
f=makefont(24)
book={id=1,hash="ab",title="完整图书名称",author="完整作者",extension="epub",filesize=100,size="100 B",filesizeString="100 B"}
long_description=string.rep("这是完整图书描述，应该能够上下滑动阅读。",120)
fixtures={["{}"]={},search={success=1,books={book}},
details={success=1,book={description="<p>"..long_description.."</p>"}},
formats={success=1,books={book}},link={success=1,file={downloadLink="https://cdn.example/a.epub"}}}
fixtures.profile={success=1,user={id=1,downloads_today=1,downloads_limit=10,isPremium=0}}
ctx={state={zlib_origin="https://test.example",query="Book",account={id="1",key="k",origin="https://test.example"}},
screen={width=480,height=800},fonts={medium=f,large=makefont(30),size=function(self,px) return makefont(px) end},
invalidate=function() end,storage={read=function() return "{}" end,write=function() return true end},
json={decode=function(self,b) return fixtures[b] end,encode=function() return "{}" end},
net={request=function(self,o,cb) if o.url:find("/eapi/user/profile",1,true) then cb(ctx,{ok=true,status=200,body="profile"});return {} end;count=count+1;pending=o;response=function(r) cb(ctx,r) end;return {} end},
files={exists=function() return false end,read=function() return "PK"..string.char(3,4) end},
input={keys={ok=true}}}
count=0
g={size=function() return 480,800 end,clear=function() texts={};boxes={} end,
text=function(self,x,y,t,o) texts[t]={x=x,y=y,o=o} end,
text_box=function(self,x,y,w,h,t,o) boxes[#boxes+1]={x=x,y=y,w=w,h=h,t=t,o=o} end,
rect=function() end,line=function() end,polyline=function() end}
function tap(x,y) on_input(ctx,{type="pointer",phase="up",gesture="tap",x=x,y=y}) end
function draw() on_draw(ctx,g) end
function swipe() on_input(ctx,{type="pointer",phase="up",gesture="swipe_up",x=160,y=300}) end
""")
# Keep website transport separate while exercising authenticated EAPI details.
l.execute('package.loaded.web={search=function(c,body,notify,done) web_account=c.state.account;web_origin=c.state.zlib_origin;done(c,{success=1,books={book}}) end}')
l.execute(Path('xtapp/index.lua').read_text())

l.execute("""
local network=require("network")
assert(network.failure({status=400},{error="Access denied"}):find("HTTP 400",1,true))
assert(network.failure({status=400},{error="拒绝访问"}):find("服务器拒绝当前请求",1,true))
assert(network.failure({status=400},{error="Invalid credentials"}):find("重新登录",1,true))
assert(network.failure({status=400},{error="quota"}):find("quota",1,true))
local account=ctx.state.account
on_load(ctx)
ctx.state.zlib_origin="https://new.example"
tap(100,290)
assert(count==0 and web_origin=="https://new.example" and web_account==account)
tap(400,280)
assert(pending.headers["remix-userid"]==account.id)
assert(pending.headers["remix-userkey"]==account.key)
assert(pending.url=="https://new.example/eapi/book/1/ab")
fixtures.denied={success=0,error="Access denied"}
response({ok=false,status=400,body="denied"})
assert(ctx.state.account==account)
assert(ctx.state.last_network_error.status==400)
assert(ctx.state.last_network_error.reason:find("服务器拒绝当前请求",1,true))
fixtures.expired={success=0,error="Invalid credentials"}
tap(30,40);tap(400,280);response({ok=false,status=400,body="expired"})
assert(ctx.state.account==account)
assert(ctx.state.last_network_error.reason:find("重新登录",1,true))
local mirrors=require("mirrors")
fixtures.domains={success=1,domains={}}
local finished=false
mirrors.detect(ctx,function() end,function() finished=true end,{"https://other.example"},false)
assert(pending.url=="https://other.example/eapi/info/domains")
response({ok=true,status=200,body="domains"})
assert(finished and ctx.state.zlib_origin=="https://other.example" and ctx.state.account==account)
finished=false
mirrors.detect(ctx,function() end,function() finished=true end,{"https://failed.example"},false)
response({ok=false,status=403,body=""})
assert(finished and not ctx.state.zlib_origin and ctx.state.account==account)
""")
print("PASS session reused after server switch and retained on detection/API failures; HTTP 400 JSON classified")
