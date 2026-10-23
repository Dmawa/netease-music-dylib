# ne-music

免越狱 iOS 网易云音乐悬浮播放器（dylib）。

注入到目标 App 的容器内即可使用；**不 hook 宿主任何代码**，不依赖 MobileSubstrate /
Cydia Substrate / ElleKit，也不改动宿主的类、方法或界面。

## 设计边界

| 项 | 做法 |
|---|---|
| 启动方式 | dylib 的 `__attribute__((constructor))`，自己建 `UIWindow` 挂浮层 |
| 对宿主的侵入 | 仅一条 `LC_LOAD_DYLIB` 加载指令；无 hook、无 swizzle、无 fishhook |
| 卸载 | 从 `.app` 删除 dylib + 去掉加载指令即完全消失 |
| 登录 | 网易云二维码登录（扫码，无需账号密码） |
| 音频 | `AVPlayer` + `AVAudioSession(Playback)`，支持锁屏封面与远程控制 |

> 免越狱的安装方式：把 `Player.dylib` 注入宿主 IPA 后重签，再用
> Sideloadly / TrollStore 等工具安装。

## 目录

```
src/
  NEEntry.m            构造器入口：等宿主就绪 → 装浮层
  Core/
    NESession.{h,m}    HTTP 会话、Cookie 持久化（MUSIC_U）
    NEApi.{h,m}        网易云接口：扫码/搜索/歌单/播放地址/歌词
    NEPlayer.{h,m}     AVPlayer 队列、后台播放、锁屏控制
  UI/                  可整体替换的表现层
    NEUITheme.h        所有颜色/尺寸常量集中在此
    NEFloatingBall.{h,m}  悬浮球与面板容器（唯一窗口相关代码）
    NEMainPanel.{h,m}     登录/发现/搜索/播放页
scripts/inject.py      把 dylib 注入宿主 IPA（LIEF）
.github/workflows/     macOS CI：真 Xcode SDK 编译 + ad-hoc 签名
```

UI 层与 Core 之间只通过 `NEApi` / `NEPlayer` 的公开接口通信，**换界面只需替换
`src/UI`**，不触碰网络与播放逻辑。

## 构建

推荐走 CI（macOS runner 自带真 iOS SDK，产物同时含 arm64 与 arm64e）：

```
Actions → build → 下载 Player.dylib
```

本地/Theos：

```bash
export THEOS=~/theos
make
```

## 注入

```bash
pip install lief
python3 scripts/inject.py --ipa 宿主.ipa --dylib Player.dylib --out dist
```

脚本会：解包 → 加 `LC_LOAD_DYLIB` → 拷入 dylib → 校验 → ad-hoc 重签 → 重打包。

## 已验证

- 网易云接口（明文，无需 weapi 加密）：扫码 unikey / 轮询 801→803 / 搜索 /
  歌单详情 / 播放地址 v1 / 歌词，均已实测返回正常
- 注入脚本：对真实 arm64 IPA 实测，依赖数 33 → 34，`verify` 通过，
  产物中 dylib 与加载指令均存在

## 已知限制

- 未登录时部分歌曲 `url` 为 `null`（版权/会员限制），会提示登录
- VIP 专享曲目即使登录也可能只返回试听片段
- 播放地址带时效签名（约 20 分钟），长时间暂停后恢复需重新解析
- 需要在 macOS 上完成签名，Windows/Linux 只能改二进制不能签名

## 合规

仅供个人学习与自用。请遵守网易云音乐用户协议，不要用于分发或商业用途。