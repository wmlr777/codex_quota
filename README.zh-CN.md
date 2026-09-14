# Codex Quota

[English](README.md) | [简体中文](README.zh-CN.md)

一个轻量的原生 macOS 菜单栏应用，显示你的 **Codex 订阅剩余额度**。

```text
◉ 72% · 周 85%
```

点击菜单栏可查看进度条、重置倒计时、具体重置时间和最近成功更新时间。每 60 秒自动刷新，电脑唤醒后刷新，也支持手动刷新。

> 这是独立的社区应用，并非 OpenAI 官方产品。它新增自己的菜单栏按钮，不修改官方 Codex 菜单。界面跟随 macOS 首选语言，支持中文和英文，其他语言回退到英文。更改系统或单独为本应用设置语言后，请重启应用。

## 下载使用

1. 安装 Codex，并使用**你自己的 ChatGPT 账号**登录。支持查找 `/Applications/Codex.app`、`/Applications/ChatGPT.app` 内置的 Codex，或单独安装的 Codex CLI。
2. 从 [Releases](../../releases/latest) 下载 **Codex-Quota-macOS.zip**。
3. 解压后将 **Codex Quota.app** 拖进“应用程序”。
4. 打开应用，额度会出现在 macOS 顶部菜单栏；没有 Dock 图标。

**运行要求：**macOS 14 或更新版本、Apple Silicon 或 Intel Mac、网络连接，以及已经登录 ChatGPT 账号的 Codex。通用下载包包含两种 CPU 架构，使用者无需安装 Swift、Python 或 Node.js。

发布包使用临时签名，**尚未经过 Apple 公证**，首次启动可能被 macOS 阻止。如果你信任下载的版本，可在尝试打开后进入“系统设置 → 隐私与安全性 → 仍要打开”，按系统提示操作；也可以自行编译。无需全局关闭 Gatekeeper。

如需开机启动，可在“系统设置 → 通用 → 登录项”中添加应用。应用不会自动修改这项设置。

## 操作

- **刷新**：立即查询。
- **齿轮 → 打开 Codex**：打开已安装的 Codex/ChatGPT 应用。
- **齿轮 → 选择 Codex 可执行文件…**：自动查找失败时，手动选择 `codex` 程序。
- **齿轮 → 退出**：停止应用并移除菜单栏按钮。

弹出面板按屏幕可用高度限制尺寸，内容可滚动，避免加载或报错时超出边界。窗口名称依据服务返回的时长显示，常见窗口为 5 小时和 1 周。缺失数据用 `—` 表示。读取失败时保留上次成功数据并标记警告；到达重置时间后，也不会自行假定额度已经恢复到 100%。

## 查询的是哪个账号？

应用启动本机 `codex app-server`，由它使用已有登录状态。应用没有内置作者的账号，不要求粘贴令牌，也不直接读取认证文件。分享给别人后，读取的是**对方本机 Codex 登录账号的额度**。

如果使用多个 Codex 安装位置或不同 `CODEX_HOME` 环境，应用查询的账号可能与某个已打开的桌面窗口不同。当前界面不显示账号邮箱。额度看起来不对时，请确认所选 Codex 环境；切换账号请在 Codex 中完成，之后刷新本应用。

可执行文件查找顺序：

1. `CODEX_BIN` 环境变量，适合测试或从终端启动。
2. 在应用中手动选择的路径。
3. `/Applications` 下 Codex/ChatGPT 应用内置的程序。
4. `/opt/homebrew/bin/codex`、`/usr/local/bin/codex` 和 `PATH`。

从 Finder 启动的应用可能不继承终端环境。自定义 CLI 安装位置可通过齿轮菜单选择。

## 从源码构建

安装 Apple Command Line Tools（`xcode-select --install`）或 Xcode，使用较新的 Swift 工具链。在克隆后的仓库根目录执行：

```sh
./scripts/build.sh
open "dist/Codex Quota.app"
```

默认构建当前 Mac 的架构。生成同时支持 Apple Silicon 和 Intel 的通用压缩包：

```sh
./scripts/package.sh
```

产物为 `dist/Codex-Quota-macOS.zip` 和 `dist/SHA256SUMS.txt`。构建和打包脚本只写入本仓库，不安装应用，也不注册登录项。

## 测试与排查

```sh
./scripts/build.sh
./scripts/test.sh
"dist/Codex Quota.app/Contents/MacOS/CodexQuota" --probe
```

测试使用 Python 3 启动本地模拟服务，无需登录 Codex，也无需网络。覆盖命名额度分组、字段缺失、比例边界、窗口名称、初始化握手、无关通知和错误返回。`--probe` 则是单独的真实接口检查，使用你的登录，仅输出剩余额度百分比。

读取失败时：

- 确认选定的 Codex 已使用 ChatGPT 账号登录，而不是仅配置 API Key。
- 检查网络连接，再点击“刷新”。
- Codex 位于其他目录时，通过齿轮菜单选择正确的可执行文件。
- 单次查询 30 秒超时，应用将在下次刷新时重试。

## 可选的 Codex 配套插件

[`plugins/codex-quota`](plugins/codex-quota) 包含指导 Codex 构建、启动和诊断本仓库的技能。**运行菜单栏应用不需要安装插件。** 它没有发布到官方插件目录，这些脚本也不会自动安装插件。

仅分享插件不包含原生应用。使用技能时需保留完整仓库，并告诉 Codex 仓库位置。启用或禁用插件不会自动启动或退出应用；关闭应用请使用其“退出”菜单。

## 实现与隐私

通过官方文档中的 [Codex App Server](https://learn.chatgpt.com/docs/app-server) stdio 协议，依次发送 `initialize`、`initialized`、`account/rateLimits/read`。每次读取完成后关闭本次子进程。刷新不创建对话，也不调用模型推理。

- 优先读取 `rateLimitsByLimitId.codex`，兼容旧的 `rateLimits`。
- 剩余量为 `100 - usedPercent`，限制在 0–100%。
- 不收集使用统计，也不向本项目运营的服务器发送额度数据。
- 应用自身不将额度快照或凭证写入磁盘；Codex 仍会维护自己的认证和运行状态。
- 仅显示 Codex 订阅额度，不显示 OpenAI API 账单余额或 ChatGPT 网页聊天的独立消息上限。
- 每分钟轮询，不是秒级推送。

二进制以 macOS 14+ 为编译目标，目前实际运行验证环境为搭载 Apple Silicon 的 macOS 26。Intel 和其他支持的系统版本仍需更多实机验证。

## 许可证

[MIT](LICENSE)。
