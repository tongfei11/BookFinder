# 找书神器 · BookFinder


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
4. 进入应用，检测服务器，登录自己的账号后搜索、查看和下载。

开发者源码在 `xtapp/`，可用 [XTApp Studio](https://xtapp-ai.xteink.cn/) 预览与导出。安装包由 Studio 内置加密打包器生成并完成结构自检；不是改名后的 ZIP。

## 已知限制

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

