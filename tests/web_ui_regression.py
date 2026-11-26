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
l.execute("""
web_calls={search=0,detail=0,download=0}
package.loaded.web={
 search=function(c,body,notify,done)
  web_calls.search=web_calls.search+1
  last_web_origin=c.state.zlib_origin
  book.web_path="/book/abc/book.html";book.web_download="/dl/abc"
  done(c,{success=1,books={book},pagination={total_pages=2}})
 end,
 detail=function(c,b,notify,done) web_calls.detail=web_calls.detail+1;done(c,{description="网页简介",download="/dl/abc"}) end,
 fetch=function(c,url,save,notify,done) web_calls.download=web_calls.download+1;done(c,{ok=true,status=200,saved=true}) end
}
""")
l.execute(Path('xtapp/index.lua').read_text())
l.execute("""
on_load(ctx)
tap(100,290)
draw()
assert(web_calls.search==1 and web_calls.download==0 and texts["查看"])
assert(count==0) -- First search does not call EAPI, even after a fresh app load.
assert(ctx.state.account.key=="k")
tap(400,280);draw()
assert(web_calls.detail==1 and web_calls.download==0 and texts["图书详情"])
local limit_hint=false
for _,b in ipairs(boxes) do if b.t=="单文件下载上限 8 MiB" then limit_hint=true end end
assert(not limit_hint)

tap(100,665);draw()
assert(web_calls.search==2 and web_calls.download==1 and web_calls.detail==1)
assert(ctx.state.last_download=="zlib-1-ab.epub" and texts["打开阅读"])
-- A server switch also searches the website immediately and keeps the account.
tap(30,40);tap(30,40)
ctx.state.zlib_origin="https://mirror.example"
tap(100,290)
assert(last_web_origin=="https://mirror.example" and web_calls.search==3 and count==0)
assert(ctx.state.account.key=="k")
on_input(ctx,{type="key",phase="up",key="right"});draw()
assert(texts["上一页"].x==74 and texts["上一页"].y==758)
book.web_detail_loaded=nil
package.loaded.web.detail=function(c,b,notify,done) finish_detail=function() done(c,{description=long_description,download="/dl/abc"}) end end
tap(400,280);draw()
local fixed_y=texts["下载 EPUB"].y
finish_detail();draw()
assert(texts["下载 EPUB"].y==fixed_y and not texts["上一页"] and not texts["下一页"])
function detail_number()
 for label in pairs(texts) do local number=label:match("^(%d+)/%d+$");if number then return tonumber(number) end end
end
assert(detail_number()==1)
on_input(ctx,{type="key",phase="up",key="right"});draw()
assert(detail_number()==2 and texts["下载 EPUB"].y==fixed_y)
on_input(ctx,{type="pointer",phase="up",gesture="swipe_down",x=160,y=300});draw()
assert(detail_number()==1)
on_input(ctx,{type="pointer",phase="up",gesture="swipe_up",x=160,y=300});draw()
assert(detail_number()==2)
ctx.input.keys.ok=false
on_input(ctx,{type="key",phase="up",key="down"});draw();assert(detail_number()==3)
on_input(ctx,{type="key",phase="up",key="up"});draw();assert(detail_number()==2)
assert(texts["下载 EPUB"].y==fixed_y and not texts["上一页"] and not texts["下一页"])
tap(30,40);tap(30,40)
book.filesize=8388609
package.loaded.web.detail=function(c,b,notify,done) done(c,{description="简介",download="/dl/abc"}) end
tap(100,290);tap(400,280);draw()
local oversized=false
for _,b in ipairs(boxes) do if b.t=="文件超过下载上限 8 MiB" then oversized=true end end
assert(not oversized)
tap(100,665);draw()
local clicked_limit=false
for _,b in ipairs(boxes) do if b.t=="文件超过固件直存上限 8 MiB" then clicked_limit=true end end
assert(clicked_limit and web_calls.download==1)
""")
print("PASS first search and server switch use website directly; view -> explicit download -> downloaded/open; no EAPI search")
