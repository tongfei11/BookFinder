from pathlib import Path
from lupa.lua54 import LuaRuntime
# Reuse the app's existing fixture and run it in each system locale.
fixture=Path('tests/web_ui_regression.py').read_text().split('l.execute("""',1)[1].split('""")',1)[0]
for language in ['zh','zh-TW','en','de']:
 l=LuaRuntime();l.execute('package.path="xtapp/?.lua;"..package.path');l.execute(fixture)
 l.globals().language=language
 l.execute('''ctx.i18n={locale=language};tr=require("locale")
 assert(tr.t(ctx,"搜索")==((language=="zh" or language=="zh-TW") and "搜索" or "Search"))
 package.loaded.web={search=function(c,b,n,done) book.web_path="/book/a/book.html";done(c,{success=1,books={book}}) end,
 detail=function(c,b,n,done) done(c,{description="这是原文简介",download="/dl/a"}) end}
 ''')
 l.execute(Path('xtapp/index.lua').read_text())
 l.execute('''on_load(ctx);draw()
 local english=language~="zh" and language~="zh-TW"
 assert(texts[english and "BookFinder z-lib" or "找书神器z-lib"])
 assert(texts[english and "Search" or "搜索"])
 tap(100,290);draw();assert(texts[book.title]) -- Book metadata is never translated.
 tap(400,280);draw();assert(texts[english and "Book details" or "图书详情"])
 local content=false;for _,b in ipairs(boxes) do if b.t=="这是原文简介" then content=true end end;assert(content)
 if english then
  for _,b in ipairs(boxes) do assert(not b.t:find("正在",1,true)) end
  assert(tr.t(ctx,"正在下载 6 MB · 已等待 5 秒")=="Downloading 6 MB · Waiting 5 s")
  assert(tr.t(ctx,"普通账号 · 今日 1/10 · 剩余 9 次"):find("Free account",1,true))
 end
 ''')
print('PASS system zh/zh-TW/en/other fallback, home/details/status/counts, original book text preserved')
