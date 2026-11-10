#!/usr/bin/env bash
#
# 把 theos 编译出来的 .app 打成未签名 IPA。
#
#   ./make_ipa.sh [YueduLite.app]
#
# 不传参数时会在 .theos/ 下常见位置自动查找。
# 越狱机安装未签名 IPA 需要 AppSync Unified；
# 非越狱机请自行用 Xcode / 证书重新签名后再安装。
#
set -euo pipefail

find_app() {
    local candidate
    for candidate in \
        "$1" \
        ".theos/obj/YueduLite.app" \
        ".theos/obj/iphoneos/YueduLite.app" \
        ".theos/obj/debug/YueduLite.app" \
        ".theos/_/Applications/YueduLite.app" \
        "YueduLite.app"; do
        if [ -n "$candidate" ] && [ -d "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    # 新版 theos 的 obj 路径带 SDK / 架构前缀，直接找
    candidate="$(find .theos -type d -name 'YueduLite.app' -print -quit 2>/dev/null || true)"
    if [ -n "$candidate" ]; then
        printf '%s\n' "$candidate"
        return 0
    fi
    return 1
}

APP="$(find_app "${1:-}")" || {
    echo "找不到 YueduLite.app" >&2
    echo "用法: $0 /path/to/YueduLite.app" >&2
    exit 1
}

NAME="$(basename "$APP")"
if [ "$NAME" != "YueduLite.app" ]; then
    echo "警告: app 名称是 $NAME，仍按原名打包" >&2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/Payload"
cp -R "$APP" "$WORK/Payload/"

# 越狱机通常需要 ldid 签名；theos 一般已经签过，这里再补一次无害。
if command -v ldid >/dev/null 2>&1; then
    BINARY="$WORK/Payload/$NAME/${NAME%.app}"
    if [ -f "$BINARY" ]; then
        ENTITLEMENTS="$(pwd)/entitlements.plist"
        if [ -f "$ENTITLEMENTS" ]; then
            # 越狱安装器需要 platform-application / mobileinstall 权限，
            # 否则 sandbox 会拒绝 posix_spawn、MobileInstallationInstall。
            ldid -S"$ENTITLEMENTS" "$BINARY" || true
        else
            ldid -S "$BINARY" || true
        fi
    fi
fi

OUT="$(pwd)/YueduLite.ipa"
rm -f "$OUT"
(
    cd "$WORK"
    zip -qry "$OUT" Payload
)

echo "已生成: $OUT"
echo "安装到越狱机: Filza 打开 IPA，或配合 AppSync Unified 用其他工具安装。"
