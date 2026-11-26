local network = require("network")
local M = {}
M.original = {
  "https://z-lib.gd", "https://z-lib.gl", "https://z-library.ec",
  "https://article.sk", "https://articles.sk", "https://zlib.bz",
  "https://z-lib.by", "https://z-library.qa", "https://z-library.website",
  "https://z-library.im", "https://z-library.sk", "https://z-lib.sk",
  "https://z-lib.fm", "https://1lib.sk"
}
M.source = "https://raw.githubusercontent.com/dongyubin/Awesome-Zlibrary/main/README.md"
local sources = {
  M.source,
  "https://api.github.com/repos/dongyubin/Awesome-Zlibrary/contents/README.md"
}

local function origin(url)
  if type(url) ~= "string" then return nil end
  local host = url:match("^https://([%w%.%-]+)/?$")
  if not host or not host:find(".", 1, true) or #host > 200 then return nil end
  return "https://" .. host:lower()
end

function M.parse(text)
  if type(text) ~= "string" then return nil end
  local urls, seen = {}, {}
  local in_table = false
  for line in text:gmatch("[^\r\n]+") do
    if line:match("^|") and line:find("国内网络是否能访问", 1, true) then
      in_table = true
    elseif in_table and not line:match("^|") then
      break
    elseif in_table and line:find("✅", 1, true) and not line:find("🚫", 1, true) then
      local url = line:match("%]%((https?://[^%)]+)%)")
      -- Prefer HTTPS even when the directory still advertises plain HTTP.
      url = url and origin((url:gsub("^http://", "https://")))
      if url and not seen[url] and #urls < 32 then
        seen[url] = true
        urls[#urls + 1] = url
      end
    end
  end
  if #urls > 0 then return urls end
end

function M.update(ctx, notify, done)
  ctx.state.last_good_origin = ctx.state.zlib_origin or ctx.state.last_good_origin
  local function fetch(index)
    local job, err = ctx.net:request({
      url = sources[index],
      headers = { accept = "application/vnd.github.raw+json" },
      timeout_ms = 5000
    }, function(c, res)
      local urls = res.ok and not res.err and res.status == 200 and M.parse(res.body)
      if not urls then
        if index < #sources then return fetch(index + 1) end
        notify(c, "更新失败，保留上次入口")
        return done()
      end
      c.state.mirrors = urls
      c.state.mirror_source = M.source
      local retained = false
      for _, url in ipairs(urls) do
        if c.state.zlib_origin == url then retained = true end
      end
      if not retained then c.state.zlib_origin = nil end
      notify(c, ("已覆盖入口列表 · %d 个"):format(#urls))
      done()
    end)
    if not job then
      if index < #sources then return fetch(index + 1) end
      notify(ctx, "更新失败 " .. tostring(err))
      done()
    end
  end
  notify(ctx, "正在读取 GitHub 地址列表")
  fetch(1)
end

function M.detect(ctx, notify, done, candidates, preferred)
  local urls, included = {}, {}
  local cached = origin(preferred)
  if preferred == nil then
    cached = origin(ctx.state.zlib_origin) or origin(ctx.state.last_good_origin)
  end
  if cached then urls[1], included[cached] = cached, true end
  for _, value in ipairs(candidates or ctx.state.mirrors or {}) do
    local base = origin(value)
    if base and not included[base] then
      urls[#urls + 1], included[base] = base, true
    end
  end
  local visited = {}
  local index = 0
  local function next_origin()
    index = index + 1
    if index > #urls then
      ctx.state.zlib_origin = nil
      notify(ctx, "未检测到可用入口")
      return done()
    end
    local base = origin(urls[index])
    if not base or visited[base .. "/eapi/info/domains"] then return next_origin() end
    local function probe(url, hops)
      notify(ctx, ("检测入口 %d/%d"):format(index, #urls))
      visited[url] = true
      local job = ctx.net:request({
        url = url, headers = network.headers(), timeout_ms = 4000
      }, function(c, res)
        if res.err == "no_network" then
          ctx.state.zlib_origin = nil
          notify(c, "Wi-Fi 未连接，请联网后重试")
          return done()
        end
        if res.ok and res.status == 200 and not res.err then
          local decoded, data = pcall(function() return c.json:decode(res.body) end)
          if decoded and type(data) == "table" and data.success == 1
            and type(data.domains) == "table" then
            c.state.zlib_origin = url:match("^(https://[^/]+)")
            c.state.last_good_origin = c.state.zlib_origin
            notify(c, "已连接 " .. c.state.zlib_origin:gsub("^https://", ""))
            return done()
          end
        end
        local location = (res.headers or {}).location
        local target
        if res.status and res.status >= 300 and res.status < 400
          and type(location) == "string" and hops < 3 then
          local host = url:match("^(https://[^/]+)")
          if location:sub(1, 1) == "/" and location:sub(1, 2) ~= "//" then
            location = host .. location
          end
          local target_origin, path = location:match("^(https://[^/]+)(/[^?#]*)")
          if origin(target_origin) then
            -- Redirectors sometimes discard the API path. Probe it on the new host.
            target = target_origin .. "/eapi/info/domains"
            if path == "/eapi/info/domains" then target = location end
          elseif origin(location) then
            target = origin(location) .. "/eapi/info/domains"
          end
        end
        if target and not visited[target] then return probe(target, hops + 1) end
        next_origin()
      end)
      if not job then next_origin() end
    end
    probe(base .. "/eapi/info/domains", 0)
  end
  next_origin()
end

return M
