local locale = require("locale")
local mirrors = require("mirrors")
local network = require("network")
local web = require("web")
local quota = require("quota")
local transfer_status = require("transfer_status")
local status = "请检测服务器地址"
local page = "home"
local focus = 1
local books = {}
local PAGE_SIZE = 4
local current
local downloaded
local busy = false
local search_page = 1
local total_pages = 1
local actions = {}
local library = {}
local library_page = 1
local detail_origin = "results"
local metadata = {}
local editor
local format_options = {}
local selected_title = ""
local confirm_return = "detail"
local detail_book
local detail_page = 1
local detail_pages = {}
local detail_height
local heading_font, author_font, size_font
local scroll_detail
local search
local note_font

local function remember(ctx, name, book)
  metadata[name] = {
    id=book.id, hash=book.hash, title=book.title, author=book.author,
    extension=book.extension, size=book.size, filesize=book.filesize
  }
  local names = {}
  for key in pairs(metadata) do names[#names+1] = key end
  table.sort(names)
  while #names > 100 do
    local oldest = table.remove(names, 1)
    if oldest == name then oldest = table.remove(names, 1) end
    metadata[oldest] = nil
  end
  local body = ctx.json:encode(metadata)
  if body then ctx.storage:write("downloads.json", body) end
end

local function show(ctx, text)
  status = text
  ctx:invalidate()
end

local function encode(text)
  return text:gsub("([^A-Za-z0-9%-._~])", function(c) return ("%%%02X"):format(c:byte()) end)
end

local function decode(ctx, text)
  local ok, data = pcall(function() return ctx.json:decode(text or "") end)
  if ok and type(data) == "table" then return data end
end

local function request(ctx, options, callback)
  busy = true
  local job, err = ctx.net:request(options, function(c, res)
    busy = false
    callback(c, res)
  end)
  if not job then
    busy = false
    show(ctx, "请求启动失败 " .. tostring(err))
  end
  return job
end

local function refresh_quota(ctx)
  if not busy then quota.refresh(ctx,request) end
end

local function api(ctx, path, body, callback, anonymous)
  if path=="/eapi/book/search" then
    busy=true
    return web.search(ctx,body,show,function(host,data,reason)
      busy=false
      if data then
        host.state.last_network_error=nil
        return callback(host,data)
      end
      host.state.last_network_error={operation="网页搜索",host=host.state.zlib_origin,
        reason=reason}
      show(host,"网页搜索："..tostring(reason))
    end)
  end
  local headers = network.headers()
  local account = ctx.state.account
  if not anonymous and account then
    headers["remix-userid"] = account.id
    headers["remix-userkey"] = account.key
    headers.cookie = "remix_userid=" .. account.id .. "; remix_userkey=" .. account.key
  end
  if body then headers["content-type"] = "application/x-www-form-urlencoded" end
  request(ctx, {
    url = ctx.state.zlib_origin .. path,
    method = body and "POST" or "GET",
    body = body, headers = headers, timeout_ms = 30000
  }, function(c, res)
    local data = not res.err and decode(c, res.body)
    if not data or data.success~=1 then
      local operation = path:find("/search",1,true) and "搜索"
        or (anonymous and "登录" or "书籍请求")
      local reason = network.failure(res,data)
      c.state.last_network_error = {
        operation=operation, host=c.state.zlib_origin,
        status=res.status, reason=reason
      }
      return show(c,operation .. "：" .. reason)
    end
    c.state.last_network_error = nil
    callback(c, data)
  end)
end

local function update(ctx, mode)
  busy = true
  ctx.state.server_mode = mode
  ctx.state.server_cache = ctx.state.server_cache or {}
  local function detect()
    local candidates = mode=="original" and mirrors.original or ctx.state.mirrors
    mirrors.detect(ctx, show, function()
      busy = false
      if ctx.state.zlib_origin then
        ctx.state.server_cache[mode] = ctx.state.zlib_origin
      end
      ctx:invalidate()
      refresh_quota(ctx)
    end, candidates or {}, ctx.state.server_cache[mode] or false)
  end
  if mode=="mirror" then
    mirrors.update(ctx, show, detect)
  else
    detect()
  end
end

local function login(ctx)
  if not ctx.state.zlib_origin then return show(ctx, "请先检测服务器地址") end
  busy = true
  ctx.input:text({title=locale.t(ctx,"Z-Library 邮箱"), text=ctx.state.email or "", max_bytes=120}, function(c, email)
    if not email or email == "" then busy = false; return end
    email = email:match("^%s*(.-)%s*$")
    c.input:text({title=locale.t(c,"Z-Library 密码（明文）"), secret=false, max_bytes=120}, function(host, password)
      busy = false
      if not password or password == "" then return end
      show(host, "正在登录")
      api(host, "/eapi/user/login", "email=" .. encode(email) .. "&password=" .. encode(password),
        function(h, data)
          local user = data.user
          local key = type(user) == "table" and (user.remix_userkey or user.remix_user_key)
          if not key or not user.id then return show(h, "登录响应缺少会话信息") end
          h.state.account = {id=tostring(user.id), key=key, origin=h.state.zlib_origin}
          h.state.email = email
          show(h, "登录成功")
          refresh_quota(h)
        end, true)
    end)
  end)
end

local function open_book(ctx)
  if not downloaded then return end
  if not ctx.system:can_open("file", {name=downloaded}) then
    return show(ctx, "请从系统文件管理器打开已下载文件")
  end
  ctx.state.return_to_downloads = true
  local _, err = ctx.system:open("file", {name=downloaded})
  if err then show(ctx, "打开失败 " .. err) end
end

local function load_library(ctx)
  local files, err = ctx.files:list()
  if not files then return show(ctx, "读取已下载失败 " .. tostring(err)) end
  library = {}
  for _, file in ipairs(files) do
    local ext = file.name:lower():match("%.([^.]+)$")
    if ext == "epub" or ext == "txt" then
      local book = metadata[file.name] or {}
      library[#library+1] = {
        name=file.name, title=book.title or file.name, author=book.author or "",
        extension=ext, size=("%d 字节"):format(file.size)
      }
    end
  end
  library_page = math.min(library_page, math.max(1, math.ceil(#library/PAGE_SIZE)))
  page, focus = "library", 1
  show(ctx, #library == 0 and "还没有已下载的书" or locale.t(ctx,("已下载 %d 本"):format(#library)))
end

local function delete_book(ctx)
  if not downloaded then return end
  local ok, err = ctx.files:remove(downloaded)
  if not ok then return show(ctx, "删除失败 " .. tostring(err)) end
  metadata[downloaded] = nil
  local body = ctx.json:encode(metadata)
  if body then ctx.storage:write("downloads.json", body) end
  if ctx.state.last_download == downloaded then
    ctx.state.last_download, ctx.state.last_book = nil, nil
  end
  current, downloaded = nil, nil
  load_library(ctx)
  show(ctx, "已删除文件")
end

local function download(ctx)
  local book = current
  if not book then return end
  local account = ctx.state.account
  if not account then
    return show(ctx, "请返回首页登录账号")
  end
  if tonumber(book.filesize) and tonumber(book.filesize) > 8388608 then
    return show(ctx, "文件超过固件直存上限 8 MiB")
  end
  local name = "zlib-" .. book.id .. "-" .. book.hash .. "." .. book.extension
  if ctx.files:exists(name) then
    downloaded = name
    return show(ctx, "此文件已下载，可打开阅读")
  end
  if book.web_path then
    busy=true
    show(ctx,"正在获取网页下载地址")
    local function transfer(c,data,reason)
      if not data then busy=false;return show(c,tostring(reason)) end
      local progress=transfer_status.start(c,book.size,show)
      web.fetch(c,c.state.zlib_origin..data.download,{to="files",name=name},show,function(h,res,error)
        progress:stop()
        busy=false
        if not res then return show(h,"下载失败："..tostring(error)) end
        local head=h.files:read(name,0,256)
        if not network.valid_file(book.extension,head,res.headers) then
          h.files:remove(name)
          return show(h,"返回文件格式异常，请重试")
        end
        downloaded=name
        h.state.last_download,h.state.last_book=name,book
        remember(h,name,book)
        show(h,"下载成功，可打开阅读")
        refresh_quota(h)
      end)
    end
    if book.web_download and book.web_download:match("^/dl/[%w]+$") then
      return transfer(ctx,{download=book.web_download})
    end
    return web.detail(ctx,book,show,transfer)
  end
  show(ctx, "正在获取下载地址")
  api(ctx, "/eapi/book/" .. encode(book.id) .. "/" .. encode(book.hash) .. "/file", nil,
    function(c, data)
      local url = type(data.file) == "table" and data.file.downloadLink
      url = url or data.downloadLink or data.url or data.link
      if type(url) == "string" and url:sub(1,1) == "/" and url:sub(1,2) ~= "//" then
        url = c.state.zlib_origin .. url
      end
      if type(url) ~= "string" or not url:match("^https://[^/]+/") then
        return show(c, "下载响应缺少 HTTPS 文件地址")
      end
      local progress=transfer_status.start(c,book.size,show)
      local fetch
      fetch = function(address, hops)
        local job=request(c, {url=address, headers=network.headers("*/*"), save={to="files",name=name}, timeout_ms=60000},
          function(host, res)
            if res.saved and res.ok and not res.err then
              progress:stop()
              local head = host.files:read(name, 0, 256)
              if not network.valid_file(book.extension,head,res.headers) then
                host.files:remove(name)
                return show(host, "返回文件格式异常，请重试")
              end
              downloaded = name
              host.state.last_download = name
              host.state.last_book = book
              remember(host, name, book)
              show(host, "下载成功，可打开阅读")
              return refresh_quota(host)
            end
            local location = (res.headers or {}).location
            if res.status and res.status >= 300 and res.status < 400
              and type(location) == "string" and hops < 3 then
              if location:sub(1,1) == "/" and location:sub(1,2) ~= "//" then
                location = address:match("^(https://[^/]+)") .. location
              end
              if location:match("^https://[^/]+/") then return fetch(location, hops+1) end
            end
            progress:stop()
            show(host, res.err == "limit_exceeded" and "文件超过 8 MiB 或存储额度"
              or "下载失败 " .. tostring(res.err or res.status))
          end)
        if not job then progress:stop() end
      end
      fetch(url, 0)
    end)
end

local function same_book(a, b)
  return a.title:lower() == b.title:lower() and a.author:lower() == b.author:lower()
    and (not a.language or not b.language or a.language == b.language)
    and (not a.year or not b.year or tostring(a.year) == tostring(b.year))
    and (not a.publisher or not b.publisher or a.publisher == b.publisher)
end

local function choose_download(ctx, book)
  if not ctx.state.account then return show(ctx, "请先登录账号再下载") end
  selected_title = book.title
  show(ctx, "正在查询可用格式")
  api(ctx, "/eapi/book/search", "message=" .. encode(book.title)
    .. "&e=1&limit=30&page=1&extensions[]=epub&extensions[]=txt", function(c, data)
      format_options = {book}
      local seen = {[book.extension]=true}
      for _, item in ipairs(type(data.books) == "table" and data.books or {}) do
        local ext = type(item.extension) == "string" and item.extension:lower()
        local candidate = {
          id=tostring(item.id or ""),hash=item.hash,title=item.title or "",author=item.author or "",
          language=item.language,year=item.year,publisher=item.publisher,
          description=item.description,
          web_path=item.web_path,
          web_download=item.web_download,
          extension=ext,filesize=item.filesize,
          size=item.filesizeString or tostring(item.filesize or "大小未知")
        }
        if (ext=="epub" or ext=="txt") and not seen[ext] and same_book(book,candidate)
          and candidate.id:match("^%d+$") and type(candidate.hash)=="string"
          and candidate.hash:match("^%w+$") then
          format_options[#format_options+1]=candidate
          seen[ext]=true
        end
      end
      detail_origin, downloaded = "results", nil
      focus=1
      if #format_options > 1 then
        page="formats"
        show(c,"选择下载格式")
      else
        current=book
        page="detail"
        download(c)
      end
    end)
end

local function plain_description(text)
  if type(text)~="string" or text=="" then return "暂无简介" end
  text=text:gsub("<[bB][rR]%s*/?>","\n"):gsub("</[pP]>","\n\n"):gsub("<[^>]*>","")
  text=text:gsub("&#(x?[%da-fA-F]+);",function(value)
    local number=value:sub(1,1)=="x" and tonumber(value:sub(2),16) or tonumber(value)
    if number then local ok,char=pcall(utf8.char,number); if ok then return char end end
    return ""
  end)
  local entities={nbsp=" ",amp="&",lt="<",gt=">",quot='"',apos="'"}
  return (text:gsub("&(%a+);",function(key) return entities[key] or ("&"..key..";") end))
end

local function view_detail(ctx, book)
  current=book
  detail_origin="results"
  local name="zlib-"..book.id.."-"..book.hash.."."..book.extension
  downloaded=ctx.files:exists(name) and name or nil
  page,focus="detail",1
  detail_book=nil
  if book.web_detail_loaded then return show(ctx,"") end
  show(ctx,"正在加载简介")
  if book.web_path then
    busy=true
    return web.detail(ctx,book,show,function(c,data,reason)
      busy=false
      book.description=data and data.description or "暂无简介"
      if data then
        book.web_download=data.download or book.web_download
        book.web_detail_loaded=true
      end
      detail_book=nil
      show(c,data and "" or tostring(reason))
    end)
  end
  api(ctx,"/eapi/book/"..encode(book.id).."/"..encode(book.hash),nil,function(c,data)
    local item=type(data.book)=="table" and data.book or {}
    book.description=plain_description(item.description or book.description)
    detail_book=nil
    show(c,"")
  end)
end

search = function(ctx, number)
  show(ctx, "正在搜索")
  api(ctx, "/eapi/book/search",
    "message=" .. encode(ctx.state.query) .. "&page=" .. number
      .. "&limit=4&extensions[]=epub&extensions[]=txt", function(c, data)
      books = {}
      for _, item in ipairs(type(data.books) == "table" and data.books or {}) do
        local extension = type(item.extension) == "string" and item.extension:lower()
        local id = item.id and tostring(item.id)
        if #books < PAGE_SIZE and id and id:match("^%d+$") and type(item.hash) == "string"
          and item.hash:match("^%w+$") and (extension == "epub" or extension == "txt") then
          books[#books+1] = {
            id=id, hash=item.hash, title=item.title or "未命名",
            author=item.author or "", extension=extension, filesize=item.filesize,
            language=item.language, year=item.year, publisher=item.publisher,
            description=item.description,
            web_path=item.web_path,
            web_download=item.web_download,
            size=item.filesizeString or tostring(item.filesize or "")
          }
        end
      end
      search_page = number
      total_pages = math.max(number, tonumber((data.pagination or {}).total_pages) or number)
      page, focus = "results", 1
      show(c, #books == 0 and "没有 EPUB/TXT 结果" or "")
    end)
end

local function submit_search(ctx)
  if editor then
    ctx.state.query = editor:close()
    editor = nil
  end
  local text = (ctx.state.query or ""):match("^%s*(.-)%s*$")
  if text == "" then return show(ctx, "请输入书名、作者或 ISBN") end
  if not ctx.state.zlib_origin then return show(ctx, "请先检测服务器地址") end
  ctx.state.query = text
  search(ctx, 1)
end

local function ask_search(ctx)
  if editor then return end
  local width = ctx.screen.width
  editor = ctx.input:edit({
    rect={x=42,y=page=="home" and 181 or 78,w=width-84,h=40},
    text=ctx.state.query or "", placeholder=locale.t(ctx,"书名、作者或 ISBN"), max_chars=32, enter="search",
    on_change=function(c,text) c.state.query=text; c:invalidate() end,
    on_end=function(c,text,how)
      editor=nil
      c.state.query=text
      if how=="enter" then submit_search(c) else c:invalidate() end
    end
  })
  ctx:invalidate()
end

local function home(ctx)
  page, focus = "home", 1
  show(ctx, "")
  refresh_quota(ctx)
end

local function controls(ctx)
  local rows = {}
  local function add(label, action) rows[#rows+1] = {label=label, action=action} end
  if page == "home" then
    add("检测服务器地址", function(c) update(c,"original") end)
    add("检测服务器地址（镜像）", function(c) update(c,"mirror") end)
    add(ctx.state.account and "已登录" or "登录", login)
    add("搜索框", ask_search)
    add("搜索", submit_search)
    add("已下载", load_library)
  elseif page == "library" then
    for i=(library_page-1)*PAGE_SIZE+1, math.min(library_page*PAGE_SIZE,#library) do
      local item = library[i]
      add("打开", function(c)
        current, downloaded = item, item.name
        detail_origin = "library"
        open_book(c)
      end)
      rows[#rows].item_row=(i-1)%PAGE_SIZE+1
      add("删除", function(c)
        current, downloaded = item, item.name
        detail_origin, confirm_return = "library", "library"
        page,focus="confirm_delete",1
        show(c,"确认删除当前书籍文件？")
      end)
      rows[#rows].item_row=(i-1)%PAGE_SIZE+1
    end
    if library_page > 1 then add("上一页", function(c) library_page=library_page-1; load_library(c) end) end
    if library_page*PAGE_SIZE < #library then add("下一页", function(c) library_page=library_page+1; load_library(c) end) end
  elseif page == "confirm_delete" then
    add("确认删除此书", delete_book)
    add("取消", function(c)
      if confirm_return=="library" then return load_library(c) end
      page,focus="detail",1
      show(c,"")
    end)
  elseif page == "formats" then
    for _, option in ipairs(format_options) do
      add(option.extension:upper() .. " · " .. option.size, function(c)
        option.description=option.description or (current and current.description)
        current, downloaded = option, nil
        page,focus="detail",1
        download(c)
      end)
    end
    add("取消", function(c) page,focus="detail",1; show(c,"") end)
  elseif page == "results" then
    for _, book in ipairs(books) do
      add("查看", function(c) view_detail(c,book) end)
    end
    if search_page > 1 then add("上一页", function(c) search(c, search_page-1) end) end
    if search_page < total_pages then add("下一页", function(c) search(c, search_page+1) end) end
    add("修改搜索", ask_search)
  else
    add(downloaded and "打开阅读" or "下载 " .. current.extension:upper(), downloaded and open_book or function(c) choose_download(c,current) end)
    if downloaded then
      add("删除", function(c)
        confirm_return="detail"
        page,focus="confirm_delete",1
        show(c,"确认删除当前书籍文件？")
      end)
    end
    add(detail_origin == "library" and "返回已下载" or "返回搜索结果", function(c)
      if detail_origin == "library" then return load_library(c) end
      page,focus="results",1
      show(c,"")
    end)
  end
  local width = ctx.screen.width
  for i,row in ipairs(rows) do
    row.x,row.y,row.w,row.h=24,225+(i-1)*64,width-48,54
  end
  if page=="home" then
    local positions={{24,ctx.screen.height-156,width-48,58},{24,ctx.screen.height-88,width-48,58},
      {width-132,12,108,52},{24,160,width-48,92},{24,272,width-48,60},{24,344,width-48,58}}
    for i,row in ipairs(rows) do
      row.x,row.y,row.w,row.h=table.unpack(positions[i])
    end
  elseif page=="results" then
    for i,row in ipairs(rows) do
      if row.label=="修改搜索" then
        row.x,row.y,row.w,row.h=24,68,width-48,54
      elseif i<=#books then
        row.x,row.y,row.w,row.h=width-124,200+(i-1)*124+64,100,44
      else
        row.x,row.y,row.w,row.h = row.label=="上一页" and 24 or width-124,
          ctx.screen.height-64,100,44
      end
    end
  end
  if page=="library" then
    for _,row in ipairs(rows) do
      if row.item_row then
        row.x,row.y,row.w,row.h=width-(row.label=="打开" and 236 or 124),
          144+(row.item_row-1)*124+64,100,44
      else
        row.x,row.y,row.w,row.h=row.label=="上一页" and 24 or width-124,
          ctx.screen.height-64,100,44
      end
    end
  end
  if page=="detail" then
    for i,row in ipairs(rows) do
      row.y = ctx.screen.height-32-#rows*64+(i-1)*64
    end

  end
  if page=="formats" or page=="confirm_delete" then
    for i,row in ipairs(rows) do
      row.x,row.y,row.w,row.h=48,330+(i-1)*64,width-96,52
    end
  end
  return rows
end

function on_load(ctx)
  if ctx.budget then ctx.budget:extend() end
  note_font = ctx.fonts:size(20, "中")
  heading_font = ctx.fonts:size(28,locale.english(ctx) and "A" or "中")
  author_font = ctx.fonts:size(22,"中")
  size_font = ctx.fonts:size(18,"中")
  ctx.state.server_cache = ctx.state.server_cache or {}
  if not ctx.state.server_mode and ctx.state.zlib_origin then
    ctx.state.server_cache.mirror = ctx.state.zlib_origin
    ctx.state.server_mode = "mirror"
  end
  ctx.state.server_mode = ctx.state.server_mode or "original"
  status = ctx.state.zlib_origin and "" or "请先检测服务器地址"
  metadata = decode(ctx, ctx.storage:read("downloads.json")) or {}
  if ctx.state.last_book and ctx.state.last_download and ctx.files:exists(ctx.state.last_download) then
    if not metadata[ctx.state.last_download] then
      remember(ctx, ctx.state.last_download, ctx.state.last_book)
    end
    if ctx.state.return_to_downloads then load_library(ctx) end
  end
  ctx.state.return_to_downloads = nil
  if page=="home" then refresh_quota(ctx) end
end

local function go_back(ctx)
  if page=="confirm_delete" then
    if confirm_return=="library" then return load_library(ctx) end
    page="detail"
  elseif page=="formats" then page="detail"
  elseif page=="detail" and detail_origin=="results" then page="results"
  elseif page=="detail" and detail_origin=="library" then return load_library(ctx)
  else return home(ctx) end
  focus=1
  show(ctx,"")
end

local function prepare_detail(ctx)
  local bottom=controls(ctx)[1].y-78
  if detail_book==current and detail_height==bottom then return end
  local blocks={
    {text=current.title,font=heading_font or ctx.fonts.large},
    {text=current.author~="" and current.author:gsub("・","·") or locale.t(ctx,"作者未知"),font=author_font or ctx.fonts.medium},
    {text=current.size~="" and current.size or locale.t(ctx,"大小未知"),font=size_font or note_font},
    {text=current.description=="暂无简介" and locale.t(ctx,"暂无简介") or plain_description(current.description),font=note_font}
  }
  detail_pages={{}}
  local y=144
  for _,block in ipairs(blocks) do
    local offset=1
    while offset<=#block.text do
      local _,height,consumed=block.font:layout(block.text:sub(offset),ctx.screen.width-48,bottom-y,{overflow="clip"})
      if not consumed or consumed==0 then
        detail_pages[#detail_pages+1]={}
        y=144
      else
        local segments=detail_pages[#detail_pages]
        segments[#segments+1]={text=block.text:sub(offset,offset+consumed-1),font=block.font,y=y,h=height}
        offset=offset+consumed
        y=y+height+18
      end
    end
  end
  detail_book,detail_height=current,bottom
  detail_page=1
end

scroll_detail = function(ctx, forward)
  if not current then return end
  prepare_detail(ctx)
  detail_page=math.max(1,math.min(#detail_pages,detail_page+(forward and 1 or -1)))
  ctx:invalidate()
end

function on_input(ctx, event)
  if event.phase ~= "up" then return false end
  if event.type == "key" and event.key == "back" then
    if busy then return false end
    if page ~= "home" then go_back(ctx); return true end
    return false
  end
  if busy then return true end
  if page=="detail" and event.type=="pointer" and event.y>=144
    and event.y<controls(ctx)[1].y-78 then
    if event.gesture=="swipe_up" then scroll_detail(ctx,true); return true end
    if event.gesture=="swipe_down" then scroll_detail(ctx,false); return true end
  end
  if (page=="results" or page=="library") and event.type=="key" then
    local native_pages=(ctx.device and ctx.device.model=="x4_pro")
      or (ctx.input.keys and not ctx.input.keys.ok)
    local previous=event.key=="left" or (native_pages and event.key=="up")
    local following=event.key=="right" or (native_pages and event.key=="down")
    if previous or following then
      local step=following and 1 or -1
      if page=="results" then
        local number=search_page+step
        if number>=1 and number<=total_pages then search(ctx,number) end
      else
        local number=library_page+step
        if number>=1 and number<=math.max(1,math.ceil(#library/PAGE_SIZE)) then
          library_page=number
          load_library(ctx)
        end
      end
      return true
    end
  end
  if page=="detail" and event.type=="key" then
    if event.key=="right" then scroll_detail(ctx,true); return true end
    if event.key=="left" then scroll_detail(ctx,false); return true end
    if ctx.input.keys and not ctx.input.keys.ok and (event.key=="up" or event.key=="down") then
      scroll_detail(ctx,event.key=="down")
      return true
    end
  end
  if event.type=="pointer" and event.gesture=="tap" and page~="home"
    and page~="formats" and page~="confirm_delete" and event.x<64 and event.y<64 then
    go_back(ctx)
    return true
  end
  actions = controls(ctx)
  if #actions == 0 then return false end
  if event.type == "key" then
    if event.key == "up" or event.key == "down" then
      focus = (focus-1+(event.key=="down" and 1 or -1)) % #actions+1
      ctx:invalidate()
      return true
    elseif event.key == "ok" then actions[focus].action(ctx); return true end
  elseif event.type == "pointer" and event.gesture == "tap" then
    for i,row in ipairs(actions) do
      if event.x>=row.x and event.x<row.x+row.w and event.y>=row.y and event.y<row.y+row.h then
        focus=i
        if editor and row.label~="搜索框" and row.label~="修改搜索" then
          ctx.state.query=editor:close()
          editor=nil
        end
        row.action(ctx)
        ctx:invalidate()
        return true
      end
    end
  end
  return false
end

local function one_line(font, text, width)
  text = text:gsub("[\r\n]+", " "):gsub("・","·")
  if font:measure(text) <= width then return text end
  local low, high = 0, utf8.len(text) or 0
  while low < high do
    local middle = (low + high + 1) // 2
    local ending = utf8.offset(text, middle + 1) or (#text + 1)
    if font:measure(text:sub(1, ending - 1) .. "...") <= width then
      low = middle
    else
      high = middle - 1
    end
  end
  local ending = utf8.offset(text, low + 1) or (#text + 1)
  return text:sub(1, ending - 1) .. "..."
end

function on_draw(ctx, g)
  local width = g:size()
  local small, body, title = note_font or ctx.fonts.medium, ctx.fonts.medium, ctx.fonts.large
  g:clear(0)
  if page=="home" then
    g:text(24,24,locale.t(ctx,"找书神器z-lib"),{font=title})
  else
    local arrow_height=title.ascent or 26
    local half=arrow_height//2
    g:polyline({24+half,40-half,24,40,24+half,40+half},{line_width=2})
    g:line(24,40,24+arrow_height,40,{line_width=2})
    g:text(24+arrow_height+16,40,locale.t(ctx,(page=="detail" or page=="confirm_delete") and "图书详情" or "Z-Library"),
      {font=title,valign="middle"})
  end
  if page=="home" then
    g:text(24,76,one_line(small,ctx.state.zlib_origin or locale.t(ctx,"无服务器地址"),width-48),{font=small})
    g:text(24,116,one_line(size_font or small,locale.t(ctx,quota.label(ctx)),width-48),{font=size_font or small})
  elseif page=="results" or page=="formats" then
    g:text(width-24,30,tostring(search_page).." / "..tostring(total_pages),{font=small,align="right"})
  end
  if page=="library" then
    g:text(width-24,88,locale.t(ctx,("已下载 %d 本"):format(#library)),{font=body,align="right"})
    g:text(width-24,30,tostring(library_page).."/"..tostring(math.max(1,math.ceil(#library/PAGE_SIZE))),
      {font=small,align="right"})
  end
  if page=="results" or page=="formats" or page=="library" then
    local visible = books
    if page=="library" then
      visible={}
      for i=(library_page-1)*PAGE_SIZE+1,math.min(library_page*PAGE_SIZE,#library) do visible[#visible+1]=library[i] end
    end
    for i,book in ipairs(visible) do
      local y=(page=="library" and 144 or 200)+(i-1)*124
      g:text(24,y,one_line(body,book.title,width-48),{font=body})
      g:text(24,y+36,one_line(small,book.author~="" and book.author or locale.t(ctx,"作者未知"),page=="library" and width-284 or width-172),{font=small})
      g:text(24,y+80,one_line(small,book.size~="" and locale.t(ctx,book.size~="" and book.size or "大小未知"),page=="library" and width-284 or width-172),{font=small})
      g:rect(24,y+112,width-48,1,{fill=true})
    end
  else
    -- Detail headings are part of the navigation bar.
  end
  local status_y=page=="home" and 284 or 116
  if page=="home" then status_y=424 end
  if page=="results" or page=="formats" then
    g:text_box(140,134,width-164,42,locale.t(ctx,status),{font=small})
  elseif page=="detail" then
    local status_top=controls(ctx)[1].y-60
    g:text_box(24,status_top,width-48,48,locale.t(ctx,status),{font=small})
  elseif page=="confirm_delete" then
    -- Confirmation text is inside its modal.
  elseif page=="library" then
    if not status:match("^已下载 %d+ 本$") then
      g:text_box(24,664,width-48,54,locale.t(ctx,status),{font=small})
    end
  else
    g:text_box(24,status_y,width-48,42,locale.t(ctx,status),{font=small})
  end
  if page=="detail" and current then
    prepare_detail(ctx)
    for _,segment in ipairs(detail_pages[detail_page]) do
      g:text_box(24,segment.y,width-48,segment.h,segment.text,{font=segment.font,overflow="clip"})
    end
    if #detail_pages>1 then
      g:text(width-24,30,tostring(detail_page).."/"..tostring(#detail_pages),{font=small,align="right"})
    end
  end
  actions=controls(ctx)
  if page=="formats" or page=="confirm_delete" then
    local height=120+#actions*64
    g:rect(24,244,width-48,height,{fill=true,color=0,radius=8})
    g:rect(24,244,width-48,height,{line_width=2,radius=8})
    g:text(width//2,280,locale.t(ctx,page=="formats" and "选择下载格式" or "删除这本书？"),
      {font=body,align="center",valign="middle"})
  end
  for i,row in ipairs(actions) do
    local field=row.label=="搜索框" or row.label=="修改搜索"
    local primary=page=="home" and row.label=="搜索"
    local selected=i==focus
    g:rect(row.x,row.y,row.w,row.h,{radius=4,line_width=selected and 2 or 1,fill=primary})
    if not field or not editor then
      local text=field and (ctx.state.query and ctx.state.query~="" and ctx.state.query or locale.t(ctx,"书名、作者或 ISBN")) or locale.t(ctx,row.label)
      if field then
        g:text_box(row.x+18,row.y+10,row.w-36,row.h-12,text,{font=body})
      else
        g:text(row.x+row.w//2,row.y+row.h//2,text,
          {font=(page=="results" or page=="library" or locale.english(ctx)) and small or body,color=primary and 0 or 15,
            align="center",valign="middle"})
      end
    end
  end
end
