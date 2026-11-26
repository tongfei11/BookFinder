# 找书神器 · BookFinder

面向阅星瞳 X4 Pro 的 **Z-Library 第三方客户端**：在阅读器上检测服务器、登录自己的 Z-Library 账号、搜索书籍、查看详情并下载 EPUB/TXT，下载后可调用系统阅读器打开。界面适配墨水屏，支持触控和实体按键。当前版本为 XTApp 构建 **0031**。

本项目不是 Z-Library 官方应用，不提供电子书文件或共享账号。

![商店封面](store-assets/cover-1200x675.png)

[English](README.en.md)

## 功能

- 跟随系统语言：中文/繁体中文系统使用中文，其他系统语言回退英文；书籍元数据和简介保持原文。
- 检测原链接或镜像服务器，切换地址保留登录会话。
- 网页搜索，列表显示作者、大小；点击“查看”进入详情，点击“下载”才下载，多个格式弹窗选择。
- 首页显示账号状态和实际下载额度；下载显示文件大小及已等待时间。
- 已下载支持打开、删除；详情支持按键及上下滑动分页，底部操作位置固定。

## 下载与安装

1. 到 [Releases](https://github.com/tongfei11/BookFinder/releases) 下载 **BookFinder-0031.xtapp**。
2. 设备进入 USB 模式，将文件复制到 SD 卡，安全弹出后在系统文件管理器点开 `.xtapp`，确认安装。
3. 需要甘草固件；原中文流程已在 X4 Pro 固件 26112101 验证系统阅读器打开。0031 英文 UI 仍需真机验收。

开发者源码在 `xtapp/`，可用 [XTApp Studio](https://xtapp-ai.xteink.cn/) 预览与导出。安装包由 Studio 内置加密打包器生成并完成结构自检；不是改名后的 ZIP。

## 首次使用

1. **检测地址**：首页底部点击“检测服务器地址”，尝试内置的原链接候选域名；若不可用，点击“检测服务器地址（镜像）”，从下述 GitHub 目录更新镜像列表并检测。成功后首页会显示当前服务器地址；显示“无服务器地址”时，需要先完成检测才能登录、搜索。
2. **登录账号**：点击首页右上角“登录”，输入自己的 Z-Library 邮箱和密码。成功后变为可点击的“已登录”，首页显示账号下载额度。更换服务器地址会保留登录信息。
3. **搜索书籍**：首页输入书名、作者或 ISBN，点击“搜索”。当前使用网站搜索方式，展示 EPUB/TXT 结果；列表显示书名、作者和文件大小，可用翻页按钮或实体按键翻页。
4. **查看并下载**：点击结果的“查看”，进入完整书名、作者、大小和简介页面，再点击底部“下载”；有多个可用格式时弹窗选择。详情可用实体按键或上下滑动翻页。
5. **打开或删除**：回到首页进入“已下载”，点击“打开”调用系统阅读器，或点击“删除”并确认。

## 服务器地址与镜像来源

| 首页按钮 | 地址来源与行为 |
| --- | --- |
| 检测服务器地址 | 尝试内置原链接候选列表，包含 `https://z-lib.gd` 等域名。完整列表见 [xtapp/mirrors.lua](xtapp/mirrors.lua)，并非实时更新的官方地址公告。 |
| 检测服务器地址（镜像） | 运行时读取 [dongyubin/Awesome-Zlibrary](https://github.com/dongyubin/Awesome-Zlibrary) 的 README，提取“国内网络是否能访问”表格中标记可用的地址，覆盖本地候选列表后检测；读取失败时保留上次列表。 |

镜像目录由第三方维护，其可用标记不保证当前网络一定可达，也不代表 Z-Library 官方背书。可在上述仓库查看目录原文；应用首页显示的是实际选中的服务器地址。检测通过仅表示检测接口可达，搜索、登录或下载仍可能受上游限制。

应用使用设备当前的 Wi-Fi 网络，没有内置 HTTP/SOCKS5 代理。若出现 `Access denied` 或连接失败，可换用另一组入口重新检测；仍失败时，在浏览器确认同一地址能否搜索，必要时通过浏览器下载后传书。

请求协议研究参考 [heartleo/zlib](https://github.com/heartleo/zlib)，本项目使用独立的 Lua 实现。来源与许可详见 [NOTICE.md](NOTICE.md)。

## 已知限制

- 当前固件直接下载上限为 **8 MiB**；超过时点击“下载”会提示，请通过浏览器下载后传书。
- 固件不提供实时下载字节回调，因此显示等待时间，不显示模拟百分比。
- 上游网页或验证机制变化可能导致不可用；不承诺永久稳定。网页详情分段解析，下载直接使用搜索结果中的入口。
- 原生版密码输入目前为明文，便于小屏触控核对；密码仅用于当次登录，会话保存在设备应用状态中，请勿共享状态文件。
- 免费/付费下载额度以账号实际响应为准；不提供电子书文件，不绕过账号权限或下载额度。

## 验证

在仓库根目录安装 [uv](https://docs.astral.sh/uv/)，执行：

```sh
uv run --no-project --with lupa python tests/web_regression.py
uv run --no-project --with lupa python tests/web_ui_regression.py
uv run --no-project --with lupa python tests/network_regression.py
uv run --no-project --with lupa python tests/quota_regression.py
uv run --no-project --with lupa python tests/transfer_status_regression.py
uv run --no-project --with lupa python tests/locale_regression.py
```

这些是离线回归测试，不读取账号、不请求实际下载。2026-11-24 六小时低频联网检查：网页搜索、详情及可见下载入口共 73/78 成功；直连 39/39、代理 34/39。三个直连域名最终指向同一入口，不能当作独立镜像；这不代表高频不限流，测试未下载文件。

## 开源与贡献

MIT，见 [LICENSE](LICENSE) 与 [NOTICE.md](NOTICE.md)。提交问题请附构建号、固件、操作步骤与脱敏错误，**不要上传密码、Cookie、会话 key 或电子书**。仅获取和使用你有权访问的资源。

