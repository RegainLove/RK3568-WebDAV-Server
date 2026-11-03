#!/bin/bash
# ============================================================
#  生成自签 TLS 证书（本机执行，板端没有 openssl 命令）
#    ./gen-cert.sh [IP] [HOSTNAME]
#  产物: conf/server.pem（证书+私钥合并，lighttpd 用）
#        conf/cert.pem（仅证书，可导入客户端）
#  说明: server.pem 含私钥，已在 .gitignore 排除，不要提交
# ============================================================
set -e
cd "$(dirname "$0")"

IP=${1:-192.168.2.5}
HOST=${2:-ATK-DLRK3568}
DAYS=3650

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days "$DAYS" \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem" \
    -subj "/C=CN/O=RK3568/CN=$IP" \
    -addext "subjectAltName=IP:$IP,IP:127.0.0.1,DNS:$HOST,DNS:localhost" 2>/dev/null

cat "$tmp/cert.pem" "$tmp/key.pem" > server.pem
cp "$tmp/cert.pem" cert.pem
chmod 600 server.pem

echo ">>> 已生成自签证书（$DAYS 天，CN=$IP）"
echo "    server.pem : 证书+私钥（部署到板端，600）"
echo "    cert.pem   : 仅证书（导入 Windows/手机 可消除警告）"
openssl x509 -in cert.pem -noout -subject -dates -ext subjectAltName | sed 's/^/    /'
