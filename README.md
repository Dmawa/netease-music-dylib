# ne-music

免越狱 iOS 网易云音乐悬浮播放器（dylib）。注入到目标 App 里即可使用；
**不 hook 宿主任何代码**，不依赖 MobileSubstrate / Cydia Substrate / ElleKit，
也不改宿主的类、方法或界面。

- 最低系统：iOS 13.0（arm64 / arm64e）
- 产物：`Player.dylib` + 可选的测试空壳 `NEMusicShell.ipa`
- 最近一次 CI：run [40020444181](https://github.com/Dmawa/netease-music-dylib/actions/runs/40020444181) ✅（三个 job 全绿）
- 最新版本：v0.6.0（登录按钮自动隐藏 / 设置页 / 播放进度记忆）

## 设计边界

| 项 | 做法 |
|---|---|
| 启动方式 | dylib 的 `__attribute__((constructor))`，自己建 `UIWindow` 挂浮层 |
| 窗口挂载 | iOS 13+ 先找活跃 `UIWindowScene` 再挂（scene 架构宿主必需） |
| 对宿主的侵入 | 仅一条 `LC_LOAD_DYLIB` 加载指令；无 hook、无 swizzle、无 fishhook |
| 卸载 | 从 `.app` 删除 dylib + 去掉加载指令即完全消失 |
| 登录 | 网易云二维码登录（扫码，无需账号密码），`MUSIC_U` 落盘可跨启动恢复 |
| 音频 | `AVPlayer` + `AVAudioSession(Playback)`，支持锁屏封面与远程控制 |

## 功能

- **悬浮球**：可拖动、松手吸边；点击展开面板。面板可拖动、iPad 右下角可缩放。
- **登录**：二维码扫码（801 等待 / 802 已扫 / 803 成功 / 800 过期），
  走官方 web 同一套 **/weapi 加密接口**（AES-128-CBC + RSA-1024），
  不是为了炫技——明文 `/api/login/qrcode/*` 会被服务端当成旧版客户端，
  扫码确认后回 8821「请切换其他登录方式或升级新版本再试」。
  成功后向服务端确认登录态，不靠本地 Cookie 猜测；界面内直接显示诊断信息。
- **兜底登录**：若服务端限制第三方客户端扫码（8821「请切换其他登录方式或升级新版本再试」），
  登录页底部「其他登录方式」提供：
  ① 应用内 `WKWebView` 打开官方网页（扫码/手机号/短信都由官方页面处理），
  登录后从 `WKHTTPCookieStore` 读取 `MUSIC_U` 并同步给会话（顶栏「已完成」可手动触发检测）；
  ② 直接粘贴浏览器里的 Cookie。
- **发现**：快捷入口（每日推荐、排行榜已接通；私人漫游 / 心动模式 / 私人雷达
  仍是占位）、推荐歌单、最近热门新歌。
- **我的**：我喜欢的音乐 + 我创建/收藏的歌单。
- **播放**：队列、上一首/下一首、进度拖动、后台播放、锁屏/耳机控制、
  中断与拔耳机处理；退出前把队列与进度写盘，下次启动恢复上次歌曲（点播放重新取流并 seek）。
- **设置页**：「我的」页顶部账号栏（头像/昵称/VIP）+ 右上角齿轮进入设置：
  账号信息、VIP 等级、我的消息、关于（版本 + 作者）、退出登录；登录后顶栏登录按钮自动隐藏。
- **歌词**：同时解析 `lrc` / `tlyric` / `yrc`；整行高亮 + 逐字点亮 + 翻译 +
  点击跳转；用 `CADisplayLink` 做 60fps 时间插值，不整表重排。
- **搜索**：顶部搜索框，走 `/api/cloudsearch/pc`（能拿到 `al.picUrl` 封面）。

## 目录

```
src/
  NEEntry.m            构造器入口：等宿主 scene 就绪 → 挂窗口 → 装浮层
  Core/
    NESession.{h,m}    HTTP 会话、Cookie 持久化（MUSIC_U / __csrf）、weapi POST
    NECrypto.{h,m}     weapi 加密：AES-128-CBC 两层 + RSA-1024（与官方 asrsea 等价）
    NEApi.{h,m}        网易云接口：扫码/账号/搜索/歌单/榜单/播放地址/歌词
    NEPlayer.{h,m}     AVPlayer 队列、后台播放、锁屏控制、中断处理
    NELyric.{h,m}      lrc / tlyric / yrc 解析与二分查找
    NEImageCache.{h,m} 封面缓存（内存 + 磁盘 + 并发去重）
  UI/                  可整体替换的表现层
    NEUITheme.h        所有颜色/尺寸常量集中在此
    NEFloatingBall.{h,m}  悬浮球与面板容器（唯一窗口相关代码）
    NEMainPanel.{h,m}     导航/搜索/列表/播放条/登录入口
    NEDiscoverPage.{h,m}  发现页
    NEProfilePage.{h,m}   我的页
    NEPlayerPage.{h,m}    播放页（封面 + 歌词 + 控制）
    NELyricView.{h,m}     歌词滚动与逐字点亮
    NESidebar.{h,m}       左侧竖排导航
    NELoginView.{h,m}     扫码登录 + 兜底入口（网页登录/粘贴 Cookie）
    NEWebLogin.{h,m}      应用内官方网页登录（WKWebView，检测 MUSIC_U）
    NESettingsPage.{h,m}  设置页：账号/VIP/消息/关于/退出登录
    NEAppInfo.h           插件版本与作者常量（关于页用）
    NEQRCode.{h,m}        内置 QR 生成（字节模式，版本 1-10，纠错 M）
shell-app/              测试用空壳宿主（scene 架构，模拟真实宿主条件）
scripts/
  inject.py             把 dylib 注入任意宿主 IPA（LIEF）+ 重签 + 重打包
  inject_app.py         把 dylib 注入已解包的 .app（CI 分步用）
  ent.plist             空壳重签用的 entitlements
.github/workflows/      macOS CI：真 Xcode SDK 编译 + 注入 + 签名 + 打包
```

UI 层与 Core 之间只通过 `NEApi` / `NEPlayer` 的公开接口通信，**换界面只需替换
`src/UI`**，不触碰网络与播放逻辑。

## 构建

推荐走 CI（macOS runner 自带真 iOS SDK，产物同时含 arm64 与 arm64e）：

```
Actions → build → 下载 Player.dylib / NEMusicShell.ipa
```

本地 / Theos：

```bash
export THEOS=~/theos
make
```

## 注入真实宿主

```bash
pip install lief
python3 scripts/inject.py --ipa 宿主.ipa --dylib Player.dylib --out dist
```

脚本会：解包 → 加 `LC_LOAD_DYLIB` → 拷入 dylib → 校验 → ad-hoc 重签 → 重打包。
注意 `--ipa` 必须是**已脱壳**的 IPA（App Store 原包是 FairPlay 加密的，注入后跑不起来）。

## CI 实测项

每次 push 到 `main` 会依次验证：

1. `clang -arch arm64 / arm64e` 两轮编译，`lipo` 合成 fat 二进制；
2. `codesign --force --sign -` ad-hoc 签名，`lief` 读回 `LC_CODE_SIGNATURE`；
3. 空壳 App 编译，注入后 `otool -L` 必须出现 `@executable_path/Player.dylib`，
   `Player.dylib` 必须真的在 `.app` 里（不通过就红）；
4. 打包 IPA，产物 `NEMusicShell.ipa` 可下载。

最近一次产物：`Player.dylib` 1.17 MB（arm64 + arm64e，ad-hoc 已签名），
`NEMusicShell.ipa` 370 KB。
本机可复核：

```bash
python3 -c "import lief; b=lief.MachO.parse('Player.dylib'); print(b.size, [str(b.at(i).header.cpu_type) for i in range(b.size)])"
```

## 真机排查

所有日志都带前缀，Console.app / Xcode Devices 里过滤即可：

- `[NEMusic]` 注入时机、窗口挂到哪个场景（`浮层窗口已挂到场景 390x844`）
- `[NELogin] poll raw = {...}` 轮询接口的原始响应（含 8821 这类非标准码）
- `[NELogin]` 状态码、服务端 message、803 时的 Set-Cookie、cookie 汇总
- `[NEMusic] 获取播放地址失败` 版权/登录导致的取流失败

扫码不成功时的排查顺序：

1. 看登录页状态文字：现在会显示 `<服务端原话>（状态码）`；
2. 8821 是「服务端不接受这个客户端扫码」的信号：v0.5.2 已改用官方 `/weapi`
   加密接口；若仍出现，请走登录页底部「其他登录方式」→ 网页登录；
3. 803 之后仍失败，界面会区分「没收到 Cookie / 缺 MUSIC_U / MUSIC_U 不认」，
   对应服务端没下发凭证、Cookie 被系统拦下、凭证被判定无效三种情况。

## 已知限制

- 未登录时部分歌曲 `url` 为 `null`（版权/会员限制），界面会提示登录。
- VIP 专享曲目即使登录也可能只返回试听片段。
- 播放地址带时效签名（约 20 分钟），长时间暂停后恢复需重新解析。
- 签名必须在 macOS 上完成；Windows/Linux 只能改二进制不能签名。
- UI 逻辑（布局、手势、歌词滚动）需要真机确认；CI 只能保证编译、注入与打包。
- 注入真实 App Store 版网易云需要其已脱壳版本，且重签后需自备证书或用
  TrollStore / Sideloadly 安装。

## 合规

仅供个人学习与自用。请遵守网易云音乐用户协议，不要用于分发或商业用途。
