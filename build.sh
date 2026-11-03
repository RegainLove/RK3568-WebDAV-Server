#!/bin/bash
# ============================================================
#  lighttpd + mod_webdav 交叉编译
#    ./build.sh          # 下载源码 -> 交叉编译 -> 收集产物
#    ./build.sh clean    # 清理 build/
#
#  产物: build/out/sbin/lighttpd
#        build/out/lib/*.so
#  说明: 依赖板端已有的 libpcre/libxml2/libsqlite3/libuuid/zlib
#        (已确认 /usr/lib 下均有)，故不额外编译第三方库。
# ============================================================
set -e
cd "$(dirname "$0")"
ROOT=$(pwd)

TC=/opt/atk-dlrk356x-toolchain
SR=$TC/aarch64-buildroot-linux-gnu/sysroot
CROSS=$TC/bin/aarch64-buildroot-linux-gnu
VER=1.4.61
SHA256=43f0d63d04a1b7c5b8aab07e0612e44ccad0afc0614bab784c5b019872363432
SRC=build/lighttpd-$VER
OUT="$ROOT/build/out"
STAGE="$ROOT/build/stage"

if [ "$1" = "clean" ]; then
    rm -rf "$OUT" "$STAGE" "$ROOT/build/lighttpd-$VER"
    echo "已清理 build/（源码包保留）"
    exit 0
fi

if [ ! -x "$CROSS-gcc" ]; then
    echo "❌ 找不到交叉工具链: $CROSS-gcc"
    exit 1
fi

mkdir -p build
cd build

# ---- 下载 + 校验 ----
if [ ! -f lighttpd-$VER.tar.xz ]; then
    echo ">>> 下载 lighttpd-$VER.tar.xz"
    curl -LO "https://download.lighttpd.net/lighttpd/releases-1.4.x/lighttpd-$VER.tar.xz"
fi
echo "$SHA256  lighttpd-$VER.tar.xz" | sha256sum -c - || {
    echo "❌ sha256 校验失败，请删除 build/lighttpd-$VER.tar.xz 后重试"
    exit 1
}
[ -d lighttpd-$VER ] || tar xf lighttpd-$VER.tar.xz

# ---- 交叉编译环境 ----
export PKG_CONFIG_SYSROOT_DIR="$SR"
export PKG_CONFIG_LIBDIR="$SR/usr/lib/pkgconfig:$SR/usr/share/pkgconfig"
export PCRECONFIG="$SR/usr/bin/pcre-config"

CFLAGS="-Os -mcpu=cortex-a55 --sysroot=$SR"
LDFLAGS="--sysroot=$SR -Wl,-rpath-link,$SR/usr/lib"

cd lighttpd-$VER
./configure \
    --host=aarch64-buildroot-linux-gnu \
    --build=x86_64-pc-linux-gnu \
    --prefix=/usr \
    --sbindir=/usr/sbin \
    --libdir=/userdata/webdav/lib \
    --sysconfdir=/userdata/webdav/etc \
    --localstatedir=/userdata/webdav/var \
    --with-webdav-props \
    --with-webdav-locks \
    --with-pcre \
    --with-zlib \
    --without-openssl \
    --without-pam \
    --without-bzip2 \
    --without-lua \
    --without-wolfssl \
    CC="$CROSS-gcc" \
    CFLAGS="$CFLAGS" \
    LDFLAGS="$LDFLAGS"

make -j"$(nproc)"

# ---- 收集产物（DESTDIR 方式，避免猜路径）----
rm -rf "$STAGE" "$OUT"
mkdir -p "$STAGE"
make -C "$ROOT/build/lighttpd-$VER" install DESTDIR="$STAGE"

mkdir -p "$OUT/sbin" "$OUT/lib"
cp "$STAGE/usr/sbin/lighttpd" "$OUT/sbin/"
$CROSS-strip "$OUT/sbin/lighttpd"

# 只部署 WebDAV 需要的模块
for m in mod_webdav mod_auth mod_authn_file mod_access mod_accesslog \
         mod_dirlisting mod_staticfile mod_setenv mod_alias mod_indexfile \
         mod_redirect mod_deflate mod_magnet; do
    f="$STAGE/userdata/webdav/lib/$m.so"
    if [ -f "$f" ]; then
        cp "$f" "$OUT/lib/"
        $CROSS-strip "$OUT/lib/$m.so"
    fi
done

echo ""
echo "============================================"
echo " 产物:"
ls -lh "$OUT/sbin" "$OUT/lib"
echo "============================================"
echo " 下一步:  ./deploy.sh 192.168.2.5"
