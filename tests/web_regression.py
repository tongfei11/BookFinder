"""Run from repository root: uv run --no-project --with lupa python tests/web_regression.py"""
from collections import deque
from pathlib import Path
import hashlib,time
from lupa.lua54 import LuaRuntime

l=LuaRuntime()
l.execute('package.path="xtapp/?.lua;"..package.path')
l.globals().clock_ms=lambda:int(time.monotonic()*1000)&0x7fffffff
l.globals().sha1=lambda s:hashlib.sha1(s.encode()).digest()
l.execute('''
web=require("web")
function card(id,extra)
 return '<div class="book-item resItemBoxBooks" '..(extra or '')..'><z-bookcard id="'..id..'" href="/book/abc'..id..'/book.html" extension="epub" filesize="398 KB" language="English" year="2010" deleted="0"><div slot="title">A &amp; B &#x4e66;</div><div slot="author">Author</div></z-bookcard></div>'
end
local raw='<div id="searchResultBox">'..card(1)..card(999,'hidden aria-hidden="true"')..card(2)..'</div><div class="paginator"></div><script>pagesTotal: 2</script>'
local parsed=assert(web.parse_search(raw))
assert(#parsed.books==2 and parsed.pages==2 and parsed.books[1].title=="A & B 书")
assert(parsed.books[1].filesize==398*1024 and parsed.books[2].id=="2")
assert(not web.parse_search('<html>sign in</html>'))
local malformed=assert(web.parse_search('<div id="searchResultBox">'..card(3):gsub('398 KB','1.2.3 MB')))
assert(not malformed.books[1].filesize)
local network=require("network")
assert(network.valid_file("txt","正常文本",{}))
assert(not network.valid_file("txt",string.char(239,187,191).."  <!DOCTYPE html><html>",{}))
assert(not network.valid_file("txt","<!-- test --><html>",{}))
assert(not network.valid_file("txt","Page",{["content-type"]="text/html; charset=utf-8"}))
local detail=web.parse_detail('<template><a href="/dl/decoy" hidden></a></template><a class="btn dlButton addDownloadedBook" href="/dl/actual">Download</a><div id="bookDescriptionBox"><p>Description</p></div>')
assert(detail.download=="/dl/actual" and detail.description=="Description")
assert(not web.parse_detail('<a class="dlButton addDownloadedBook" href="https://evil.example/">bad</a>').download)
queue={};files={};requests={};tick=0
ctx={state={zlib_origin="https://test.example",account={id="1",key="k"}},
clock={millis=function() return clock_ms() end},hash={sha1=function(self,s) return sha1(s) end},
after=function(self,ms,cb) queue[#queue+1]=cb end,
files={remove=function(self,n) files[n]=nil;return true end,read=function(self,n,o,len) local part=files[n] and files[n]:sub(o+1,o+len);bytes_read=(bytes_read or 0)+(part and #part or 0);return part end},
net={request=function(self,o,cb) requests[#requests+1]=o;pending=o;response=function(r) cb(ctx,r) end;return {} end}}
function pump() while #queue>0 do local cb=table.remove(queue,1);cb(ctx) end end
function note() end
function serve(html)
 files[pending.save.name]=html
 response({ok=true,status=200,saved=true,bytes=#html})
 pump()
end
-- A native page can cross the website's 50-result boundary. Hidden cards
-- must not displace entries, and a short final page must hide Next correctly.
web.search(ctx,"message=Book&page=13&limit=4",note,function(c,data,reason) result=data;error=reason end)
local first='<div id="searchResultBox">'
for i=1,49 do first=first..card(i) end
first=first..card(999,'hidden')..'<div class="paginator"></div><script>pagesTotal: 2</script>'
serve(first)
assert(pending.url:find('page=2',1,true))
serve('<div id="searchResultBox">'..card(50)..card(51)..card(52)..card(53)..card(54)..'<div class="paginator"></div><script>pagesTotal: 2</script>')
assert(result and #result.books==4 and result.books[1].id=="49" and result.books[4].id=="52")
assert(result.pagination.total_pages==14 and not files['zlib-web-cache.html'])
-- Same-query page 2 cache is reused without another network request.
local n=#requests
web.search(ctx,"message=Book&page=14&limit=4",note,function(c,data) result=data end)
assert(#requests==n and #result.books==2 and result.books[1].id=="53" and result.books[2].id=="54")
-- A changed layout cannot trap one interaction in a long chain of empty pages.
result=nil;error=nil
web.search(ctx,"message=Changed&page=1&limit=4",note,function(c,data,reason) result=data;error=reason end)
local before=#requests
for i=1,3 do serve('<div id="searchResultBox"><div class="paginator"></div><script>pagesTotal: 256</script>') end
assert(not result and error:find('网页结果异常',1,true) and #requests==before+2)
-- A large detail can put its button across a 16 KiB read boundary.
local padding=string.rep(" ",16340)
web.detail(ctx,{web_path="/book/abc/book.html"},note,function(c,data,reason) large=data;error=reason end)
serve(padding..'<a class="btn dlButton addDownloadedBook" href="/dl/actual">Download</a>'..string.rep(" ",600000)..'<div id="bookDescriptionBox">Large page description</div>')
assert(large and large.download=="/dl/actual" and large.description=="Large page description")
assert(not files['zlib-web-cache.html'])
bytes_read=0
web.detail(ctx,{web_path="/book/abc/book.html",web_download="/dl/actual"},note,function(c,data,reason) early=data;error=reason end)
serve('<div id="bookDescriptionBox"><div>Nested description</div>complete end</div>'..string.rep(" ",600000))
assert(early and early.description=="Nested descriptioncomplete end" and early.download=="/dl/actual")
assert(bytes_read==16384 and not files['zlib-web-cache.html'])
-- Recognise only the known work page, do not evaluate arbitrary page scripts.
local challenge="Checking your browser c_token= '9D9F0FA7596FB9573EB54BC6CA2EA41827C8D367' s[n1]===0xb0 s[n1+0x1]===0xb"
web.fetch(ctx,"https://test.example/s/Book",nil,note,function(c,res,why) fetched=res;error=why end)
response({ok=true,status=503,body=challenge})
pump()
assert(pending.headers.cookie:find('c_token=',1,true))
assert(pending.headers.cookie:find('remix_userkey=k',1,true))
response({ok=true,status=302,headers={location="https://cdn.example/file.epub"}})
assert(pending.url=="https://cdn.example/file.epub" and not pending.headers.cookie)
response({ok=true,status=200,body="PK"})
assert(fetched)
web.fetch(ctx,"https://test.example/s/Book",nil,note,function(c,res,why) fetched=res;error=why end)
response({ok=true,status=503,body='Checking your browser arbitrary script'})
assert(not fetched and error:find('暂不支持',1,true))
''')
print('PASS website cards/entities/hidden decoys, details, 50-result boundary, cache, proof, CDN cookie isolation, unsupported challenge')
