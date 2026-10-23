#  ne-music — 免越狱网易云音乐悬浮播放器 dylib
#
#  本仓库主构建走 GitHub Actions（macOS runner 自带真 iOS SDK），
#  本地/Theos 构建为备用路径。
#
#  产物：Player.dylib（arm64 + arm64e），注入宿主 App 后自带浮层，
#        不 hook 宿主任何代码。

TARGET := iphone:clang:latest:13.0
ARCHS  := arm64 arm64e

LIBRARY_NAME = Player

Player_FILES = src/NEEntry.m \
               src/Core/NESession.m \
               src/Core/NECrypto.m \
               src/Core/NEApi.m \
               src/Core/NEPlayer.m \
               src/Core/NELyric.m \
               src/Core/NEImageCache.m \
               src/UI/NEFloatingBall.m \
               src/UI/NEMainPanel.m \
               src/UI/NEPlayerPage.m \
               src/UI/NEProfilePage.m \
               src/UI/NESettingsPage.m \
               src/UI/NEDiscoverPage.m \
               src/UI/NESidebar.m \
               src/UI/NELoginView.m \
               src/UI/NEWebLogin.m \
               src/UI/NELyricView.m \
               src/UI/NEQRCode.m

Player_CFLAGS = -fobjc-arc -fblocks \
                -I src -I src/Core -I src/UI -I src/Support \
                -Wall -Wno-unused-parameter

Player_FRAMEWORKS = Foundation UIKit AVFoundation MediaPlayer QuartzCore CoreGraphics CoreMedia Security WebKit
Player_LIBRARIES  = sqlite3

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/library.mk