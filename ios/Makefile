# iPhone 4S 是 32 位 armv7。新版 SDK 已不带 armv7 切片，
# 请把 iPhoneOS9.3.sdk 放进 $THEOS/sdks 并使用：
#     TARGET := iphone:clang:9.3:9.0
TARGET := iphone:clang:latest:9.0
ARCHS := armv7
INSTALL_TARGET_PROCESSES = YueduLite

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = YueduLite

YueduLite_FILES = $(wildcard *.m)
YueduLite_FRAMEWORKS = UIKit Foundation JavaScriptCore CoreFoundation AVFoundation CoreText
YueduLite_LIBRARIES = z
# 新版 Xcode 的 clang 无法模块化 iOS 9.3 的老 SDK 头文件
# （CoreFoundation/UIKit 的 module.map 会直接报错），所以关掉 clang modules。
YueduLite_USE_MODULES = 0
YueduLite_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-deprecated-module-dot-map -Wno-error
# iOS 9.3 的老 .tbd 桩文件里有若干符号（CGPointZero / NSURLSession / memset 等）
# 被 $ld$hide$ 规则藏掉，静态链接会报 undefined；越狱应用按 theos 插件惯例
# 交给 dyld 在运行时解析即可。
YueduLite_LDFLAGS = -Wl,-undefined,dynamic_lookup

include $(THEOS_MAKE_PATH)/application.mk
