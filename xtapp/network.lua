local M = {}

-- Match the upstream CLI's request identity for EAPI and file requests.
local user_agent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
  .. "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

function M.headers(accept)
  return {accept=accept or "application/json", ["user-agent"]=user_agent}
end

function M.valid_file(extension,head,headers)
  if type(head)~="string" or head=="" then return false end
  local mime=((headers or {})["content-type"] or ""):lower()
  if mime:find("text/html",1,true) or mime:find("application/xhtml",1,true) then return false end
  if extension=="epub" then return head:sub(1,4)=="PK\003\004" end
  local text=head:gsub("^\239\187\191",""):lower():match("^%s*(.*)")
  -- Permit leading whitespace/BOM/comments, but never register a login or
  -- browser-verification page as a downloaded TXT book.
  while text:sub(1,4)=="<!--" do
    local ending=text:find("-->",5,true)
    if not ending then return false end
    text=text:sub(ending+3):match("^%s*(.*)")
  end
  return not (text:match("^<!doctype%s+html") or text:match("^<html[%s>]")
    or text:match("^<head[%s>]") or text:match("^<body[%s>]") or text:match("^<script[%s>]"))
end

function M.failure(res, data)
  local message = type(data)=="table" and type(data.error)=="string" and data.error or ""
  local body = type(res.body)=="string" and res.body:sub(1,4096):lower() or ""
  local lower = message:lower()
  local status = res.status and ("HTTP " .. res.status) or tostring(res.err or "无响应")
  if res.status==401 or lower=="invalid credentials" or lower=="please login"
    or message=="登录到您的账户" then
    return "登录会话未被接受，请重新登录（" .. status .. "）"
  end
  if res.status==403 or lower:find("access denied",1,true)
    or message:find("拒绝访问",1,true)
    or body:find("access denied",1,true) or body:find("__diamwall",1,true)
    or body:find("cf-chl-",1,true) then
    return "服务器拒绝当前请求（" .. status .. "），可尝试重新登录或切换地址"
  end
  if message~="" then return message .. "（" .. status .. "）" end
  return "请求失败（" .. status .. "）"
end

return M
