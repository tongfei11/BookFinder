-- Website fallback for the EAPI keyword-search refusal observed on 2026-11-23.
-- No JavaScript is executed. Only the site's known SHA-1 work page is handled.
local network = require("network")
local M = {}
local scratch = "zlib-web-cache.html"
local proof, cache

local function unescape(s)
  local entities={amp="&",lt="<",gt=">",quot='"',apos="'",nbsp=" "}
  s=s:gsub("&#(x?[%da-fA-F]+);",function(v)
    local n=v:sub(1,1)=="x" and tonumber(v:sub(2),16) or tonumber(v)
    if n then local ok,c=pcall(utf8.char,n);if ok then return c end end
    return ""
  end)
  return (s:gsub("&(%a+);",function(k) return entities[k] or ("&"..k..";") end))
end

function M.text(s)
  return unescape((s or ""):gsub("<[bB][rR]%s*/?>","\n")
    :gsub("</[pP]>","\n\n"):gsub("<[^>]*>","")):match("^%s*(.-)%s*$")
end

local function attr(s,key)
  return s:match('%f[%w_]'..key..'%s*=%s*"([^"]*)"')
    or s:match("%f[%w_]"..key.."%s*=%s*'([^']*)'")
end

function M.parse_search(html)
  local start=html:find('id="searchResultBox"',1,true)
  if not start then return nil,"网页未返回搜索列表，可能需要浏览器验证" end
  local finish=html:find('class="paginator',start,true) or #html
  local result,seen={},{}
  for classes,attributes,body in html:sub(start,finish):gmatch('<div%s+class="book%-item([^"]*)"([^>]*)>(.-)</z%-bookcard>') do
    local tag=body:match("<z%-bookcard%s+(.-)>")
    if tag and not attributes:find("hidden",1,true) and not tag:find("nofollow",1,true) then
      local id,href,ext=attr(tag,"id"),attr(tag,"href"),attr(tag,"extension")
      local hash=href and href:match("^/book/([%w]+)/")
      ext=ext and ext:lower()
      if id and id:match("^%d+$") and hash and not seen[id]
        and attr(tag,"deleted")~="1" and (ext=="epub" or ext=="txt") and #result<50 then
        local size=M.text(attr(tag,"filesize"))
        local number,unit=size:match("([%d%.]+)%s*([%a]+)")
        local units={B=1,KB=1024,MB=1048576,GB=1073741824}
        result[#result+1]={id=id,hash=hash,extension=ext,
          title=M.text(body:match('<div%s+slot="title">(.-)</div>')),
          author=M.text(body:match('<div%s+slot="author">(.-)</div>')),
          publisher=M.text(attr(tag,"publisher")),language=attr(tag,"language"),year=attr(tag,"year"),
          filesizeString=size,filesize=tonumber(number) and tonumber(number)*(units[(unit or ""):upper()] or 1),
          web_path=href,web_download=(attr(tag,"download") or ""):match("^/dl/[%w]+$")}
        seen[id]=true
      end
    end
  end
  local pages=tonumber(html:match("pagesTotal:%s*(%d+)")) or 1
  return {books=result,pages=math.min(pages,10000)}
end

-- Parse only the visible download button. Hidden template links are decoys.
function M.parse_detail(html)
  local link
  for attributes in html:gmatch("<a%s+([^>]+)>") do
    local class=attr(attributes,"class") or ""
    if class:find("dlButton",1,true) and class:find("addDownloadedBook",1,true) then
      local href=attr(attributes,"href")
      if href and href:match("^/dl/[%w]+$") then link=href;break end
    end
  end
  local _,opening=html:find('<div[^>]+id="bookDescriptionBox"[^>]*>')
  local description
  if opening then
    local depth,cursor=1,opening+1
    while cursor<=#html do
      local first,last,closing,name=html:find('<(/?)([%w]+)[^>]*>',cursor)
      if not first then break end
      if name:lower()=="div" then
        depth=depth+(closing=="/" and -1 or 1)
        if depth==0 then description=html:sub(opening+1,first-1);break end
      end
      cursor=last+1
    end
  end
  return {download=link,description=description and M.text(description) or "暂无简介",
    has_description=description~=nil}
end

local function headers(ctx,url)
  local h=network.headers("text/html,application/xhtml+xml,*/*")
  local origin=ctx.state.zlib_origin
  if url:sub(1,#origin+1)==origin.."/" then
    local cookies={}
    local a=ctx.state.account
    if a then cookies[1]="remix_userid="..a.id.."; remix_userkey="..a.key end
    if proof and proof.origin==origin then cookies[#cookies+1]=proof.cookie end
    if #cookies>0 then h.cookie=table.concat(cookies,"; ") end
  end
  return h
end

local function solve(ctx,body,notify,done)
  local seed=body:match("['\"]([A-F0-9]+)['\"]")
  if not seed or #seed~=40 or not body:find("c_token=",1,true)
    or not body:find("s[n1]===0xb0",1,true) or not body:find("s[n1+0x1]===0xb",1,true) then
    return done(ctx,nil,"网页验证类型暂不支持，请用浏览器下载后传书")
  end
  notify(ctx,"正在完成网页连接验证")
  local position=tonumber(seed:sub(1,1),16)+1
  local i,started=0,ctx.clock:millis()
  local function step(c)
    if c.budget then c.budget:extend() end
    local slice=c.clock:millis()
    for _=1,256 do
      local value=seed..i
      local digest=c.hash:sha1(value)
      if not digest then return done(c,nil,"固件无法计算网页连接验证") end
      if digest:byte(position)==176 and digest:byte(position+1)==11 then
        local elapsed=((c.clock:millis()-started)&0x7FFFFFFF)/1000
        proof={origin=c.state.zlib_origin,cookie="c_token="..value.."; c_time="..tostring(elapsed)}
        return done(c,true)
      end
      i=i+1
      if ((c.clock:millis()-slice)&0x7FFFFFFF)>=20 then break end
    end
    if i>=1048576 or ((c.clock:millis()-started)&0x7FFFFFFF)>30000 then
      return done(c,nil,"网页连接验证超时，请稍后重试")
    end
    c:after(1,step)
  end
  step(ctx)
end

function M.fetch(ctx,url,save,notify,done)
  local attempts,hops=0,0
  local function fetch(c,address)
    local timeout=save and save.name~=scratch and 60000 or 15000
    local job,err=c.net:request({url=address,headers=headers(c,address),save=save,timeout_ms=timeout},function(host,res)
      if address:sub(1,#host.state.zlib_origin+1)==host.state.zlib_origin.."/"
        and res.status==503 and type(res.body)=="string"
        and res.body:find("Checking your browser",1,true) and attempts<2 then
        attempts=attempts+1
        return solve(host,res.body,notify,function(h,ok,reason)
          if not ok then return done(h,nil,reason) end
          fetch(h,address)
        end)
      end
      local location=(res.headers or {}).location
      if res.status and res.status>=300 and res.status<400 and type(location)=="string" and hops<3 then
        if location:sub(1,1)=="/" and location:sub(1,2)~="//" then
          location=address:match("^(https://[^/]+)")..location
        end
        if location:match("^https://[%w%.%-]+/") then hops=hops+1;return fetch(host,location) end
      end
      if not res.ok or res.err or res.status~=200 or (save and not res.saved) then
        return done(host,nil,network.failure(res))
      end
      done(host,res)
    end)
    if not job then done(c,nil,"网页请求启动失败："..tostring(err)) end
  end
  fetch(ctx,url)
end

local function html(ctx,path,notify,done,detail)
  local origin=ctx.state.zlib_origin
  ctx.files:remove(scratch)
  M.fetch(ctx,origin..path,{to="files",name=scratch},notify,function(c,res,reason)
    if not res then return done(c,nil,reason) end
    if not detail and res.bytes>524288 then c.files:remove(scratch);return done(c,nil,"搜索网页过大，请缩小搜索范围") end
    local chunks,offset={},0
    local buffer,parsed="",{description="暂无简介",download=type(detail)=="string" and detail or nil}
    local function read(h)
      local part,err=h.files:read(scratch,offset,16384)
      if not part then h.files:remove(scratch);return done(h,nil,"读取网页失败："..tostring(err)) end
      offset=offset+#part
      if detail then
        if h.budget then h.budget:extend() end
        buffer=buffer..part
        local found=M.parse_detail(buffer)
        parsed.download=found.download or parsed.download
        if found.has_description then
          parsed.description,parsed.has_description=found.description,true
        end
        if parsed.download and parsed.has_description then
          h.files:remove(scratch)
          return done(h,parsed)
        end
        local start=buffer:find('<div[^>]+id="bookDescriptionBox"')
        if start and found.description=="暂无简介" and #buffer-start<131072 then
          buffer=buffer:sub(start)
        else buffer=buffer:sub(-8192) end
        if #part==16384 then return h:after(1,read) end
        h.files:remove(scratch)
        return done(h,parsed)
      end
      chunks[#chunks+1]=part
      if #part==16384 then return h:after(1,read) end
      if h.budget then h.budget:extend() end
      local text=table.concat(chunks);chunks=nil
      h.files:remove(scratch)
      done(h,text)
    end
    read(c)
  end)
end

function M.search(ctx,form,notify,done)
  local message=form:match("message=([^&]*)") or ""
  local page=tonumber(form:match("page=(%d+)")) or 1
  local limit=math.min(tonumber(form:match("limit=(%d+)")) or 4,50)
  local identity=ctx.state.zlib_origin.."|"..message.."|"..tostring(form:match("&e=1")~=nil)
  local account=ctx.state.account
  if account then identity=identity.."|"..account.id.."|"..account.key end
  if not cache or cache.identity~=identity then
    cache={identity=identity,counts={},pages=1}
  end
  local selected,requests={},0
  local first=(page-1)*limit+1
  local function finish(c)
    local count=0
    for i=1,cache.pages do count=count+(cache.counts[i] or 50) end
    done(c,{success=1,books=selected,pagination={total_pages=math.max(page,math.ceil(count/limit))}})
  end
  local load
  load=function(c)
    local index,prefix=1,0
    local wanted=first+#selected
    while cache.counts[index] and wanted>prefix+cache.counts[index] do
      prefix=prefix+cache.counts[index];index=index+1
    end
    if index>cache.pages then return finish(c) end
    if index>256 then return done(c,nil,"网页结果过多，请缩小搜索范围") end
    local function collect(h,data)
      cache.counts[index]=#data.books
      cache.page,cache.data,cache.pages=index,data,math.min(data.pages,256)
      for i=wanted-prefix,math.min(#data.books,wanted-prefix+limit-#selected-1) do
        selected[#selected+1]=data.books[i]
      end
      if #selected<limit and index<cache.pages then return load(h) end
      finish(h)
    end
    if cache.page==index then return collect(c,cache.data) end
    if requests>=3 then return done(c,nil,"网页结果异常，请缩小搜索范围后重试") end
    requests=requests+1
    local path="/s/"..message.."?page="..index.."&extensions%5B%5D=epub&extensions%5B%5D=txt"
    if form:find("&e=1",1,true) then path=path.."&e=1" end
    notify(c,"正在通过网页搜索")
    html(c,path,notify,function(h,text,reason)
      if not text then return done(h,nil,reason) end
      local data,error=M.parse_search(text)
      if not data then return done(h,nil,error) end
      collect(h,data)
    end)
  end
  load(ctx)
end

function M.detail(ctx,book,notify,done)
  if not book.web_path or not book.web_path:match("^/book/[%w]+/[^?#]*$") then
    return done(ctx,nil,"网页图书地址无效")
  end
  html(ctx,book.web_path,notify,function(c,text,reason)
    if not text then return done(c,nil,reason) end
    local data=type(text)=="table" and text or M.parse_detail(text)
    if not data.download then return done(c,nil,"网页没有返回可下载文件，请确认已登录") end
    done(c,data)
  end,book.web_download or true)
end

return M
