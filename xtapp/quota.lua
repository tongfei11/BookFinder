local network=require("network")
local M={}

local function day(ctx)
  local now=ctx.clock and ctx.clock:now()
  if now and now.valid then return ("%04d-%02d-%02d"):format(now.year,now.month,now.day) end
end

function M.refresh(ctx,perform)
  local account=ctx.state.account
  if not account or not ctx.state.zlib_origin then return end
  local previous=ctx.state.quota
  if previous then previous.stale=true end
  local headers=network.headers()
  headers["remix-userid"],headers["remix-userkey"]=account.id,account.key
  headers.cookie="remix_userid="..account.id.."; remix_userkey="..account.key
  perform(ctx,{url=ctx.state.zlib_origin.."/eapi/user/profile",headers=headers,timeout_ms=5000},function(c,res)
    local ok,data=pcall(function() return c.json:decode(res.body or "") end)
    local user=ok and type(data)=="table" and data.success==1 and data.user
    if res.ok and not res.err and res.status==200 and type(user)=="table"
      and tostring(user.id)==account.id and c.state.account==account then
      local used,limit=tonumber(user.downloads_today),tonumber(user.downloads_limit)
      if used and limit and used>=0 and limit>=0 then
        c.state.quota={id=account.id,used=math.floor(used),limit=math.floor(limit),
          premium=user.isPremium==true or tonumber(user.isPremium)==1,day=day(c)}
      end
    end
    c:invalidate()
  end)
end

function M.label(ctx)
  if not ctx.state.account then return "登录后显示下载额度" end
  local q=ctx.state.quota
  if not q or q.id~=ctx.state.account.id then return "下载额度待查询" end
  local kind=q.premium and "Premium" or "普通账号"
  if q.day~=day(ctx) then return kind.." · 下载额度待刷新" end
  return ("%s · 今日 %d/%d · 剩余 %d 次%s"):format(kind,q.used,q.limit,
    math.max(0,q.limit-q.used),q.stale and "（上次）" or "")
end

return M
