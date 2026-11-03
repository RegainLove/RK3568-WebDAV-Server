#!/bin/bash
# ============================================================
#  部署 WebDAV 到板子
#    ./deploy.sh                          # 默认 192.168.2.5 / root
#    ./deploy.sh 192.168.2.5 myuser
#    WEBDAV_PASS=mypass ./deploy.sh       # 临时指定密码
#
#  说明: 二进制 + 模块 + 配置放 /userdata/webdav，
#        启动脚本装到 /etc/init.d/S51webdav（重刷固件会丢，重跑本脚本即可）
# ============================================================
set -e
cd "$(dirname "$0")"

IP=${1:-192.168.2.5}
USER=${2:-root}
DEST=/userdata/webdav
APP_USER=webdav
APP_PASS=

# 本地配置（不入库）：WEBDAV_USER / WEBDAV_PASS
[ -f ./.env ] && . ./.env
APP_USER=${WEBDAV_USER:-webdav}
if [ -z "${WEBDAV_PASS:-}" ]; then
    echo "❌ 未设置密码：export WEBDAV_PASS=xxx  或在本目录 .env 写入 WEBDAV_PASS=xxx"
    exit 1
fi
APP_PASS=$WEBDAV_PASS

if [ ! -x build/out/sbin/lighttpd ]; then
    echo "❌ 还没编译，先跑 ./build.sh"
    exit 1
fi

# ---- 本地生成认证文件（{SHA}，不传明文）----
echo ">>> 生成认证文件 (user: $APP_USER)"
mkdir -p build
SHA=$(printf '%s' "$APP_PASS" | openssl dgst -sha1 -binary | base64)
printf '%s:{SHA}%s\n' "$APP_USER" "$SHA" > build/lighttpd.user
chmod 600 build/lighttpd.user

# ---- 创建目录 ----
echo ">>> 部署到 $USER@$IP:$DEST"
ssh "$USER@$IP" "mkdir -p $DEST/sbin $DEST/lib $DEST/etc $DEST/data $DEST/log $DEST/run $DEST/tmp"

# ---- 先停服务，避免覆盖运行中的二进制 ----
ssh "$USER@$IP" "/etc/init.d/S51webdav stop >/dev/null 2>&1 || true"

# ---- 传输文件 ----
scp -q build/out/sbin/lighttpd     "$USER@$IP:$DEST/sbin/"
scp -q build/out/lib/*.so          "$USER@$IP:$DEST/lib/"
scp -q conf/lighttpd.conf          "$USER@$IP:$DEST/etc/lighttpd.conf"
scp -q build/lighttpd.user         "$USER@$IP:$DEST/etc/lighttpd.user"
scp -q conf/S51webdav              "$USER@$IP:/etc/init.d/S51webdav"

# ---- 权限 + 启动 ----
ssh "$USER@$IP" "set -e
chmod 755 $DEST/sbin/lighttpd /etc/init.d/S51webdav
chmod 644 $DEST/lib/*.so $DEST/etc/lighttpd.conf
chmod 600 $DEST/etc/lighttpd.user
chmod 755 $DEST $DEST/sbin $DEST/lib $DEST/etc $DEST/data $DEST/log $DEST/run $DEST/tmp
chown -R www-data:www-data $DEST/data $DEST/log $DEST/run $DEST/tmp
chown www-data:www-data $DEST/etc/lighttpd.user
/etc/init.d/S51webdav restart
sleep 1
echo '--- 端口 ---'
ss -ltn 2>/dev/null | grep -q ':8080' && echo '8080 监听中' || echo '8080 未监听，检查 /userdata/webdav/log/error.log'
"

echo ""
echo ">>> 完成"
echo "    地址: http://$IP:8080/"
echo "    账号: $APP_USER / (部署时设置的密码)"
echo "    日志: $DEST/log/error.log"
echo ""
echo "    自检: curl -u $APP_USER:****** -X PROPFIND -H 'Depth: 1' http://$IP:8080/"
