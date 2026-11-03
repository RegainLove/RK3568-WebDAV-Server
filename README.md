# RK3568 WebDAV Server

在正点原子 **ATK-DLRK3568**（Buildroot 2021.11 / aarch64）上部署带认证的 **HTTPS WebDAV** 服务。

采用 **lighttpd 1.4.61 + mod_webdav + mod_openssl**，证书使用 **Let's Encrypt（自动续期）**，部署在 `/userdata`，无需重刷固件。

## 特性

- 完整 WebDAV：`PROPFIND` / `PROPPATCH` / `MKCOL` / `PUT` / `GET` / `COPY` / `MOVE` / `DELETE` / `LOCK` / `UNLOCK`
- **HTTPS 443**：Let's Encrypt 证书（`bane2005.fun`），浏览器/手机/Kazumi 默认信任
- **HTTP 8080**：仅内网/兼容客户端（如不认自签证书的 App）
- IPv4 + IPv6 双栈监听
- HTTP Basic 认证，板上只存 `{SHA}` 摘要
- 开机自启：WebDAV `S51webdav`、ddns-go `S99ddns-go`、crond `S98crond`
- 证书自动续期：certbot + 阿里云 DNS-01 + crond（每天 03:00 检查）

## 目录结构

```
.
├── build.sh              # 下载 lighttpd 源码 + 交叉编译（含 openssl）
├── deploy.sh             # 部署二进制/配置/自启脚本（证书由 certbot 管理）
├── conf/
│   ├── lighttpd.conf     # 443 HTTPS + 8080 HTTP + IPv6 双栈
│   └── S51webdav         # 板端 init 脚本
├── .env.example          # 账号密码模板（复制为 .env）
└── TASKS.md              # 任务拆解 + 实测数据 + 已知坑
```

板端布局：

```
/userdata/webdav/
├── sbin/lighttpd
├── lib/*.so              # 模块（含 mod_openssl）
├── etc/lighttpd.conf
├── etc/lighttpd.user     # {SHA} 认证文件
├── etc/server.pem        # Let's Encrypt 证书+私钥（600）
├── data/                 # WebDAV 根目录
├── log/ run/ tmp/
/userdata/certbot/        # 凭据、续期脚本、deploy-hook
/etc/letsencrypt/         # certbot 证书库
/etc/ssl/certs/ca-certificates.crt   # 板端 CA（HTTPS 调用需要）
/etc/init.d/S51webdav S98crond S99ddns-go
```

## 环境要求

| 端 | 依赖 |
|---|---|
| 编译主机 | `/opt/atk-dlrk356x-toolchain`（gcc 10.3.0），sysroot 需有 pcre / libxml2 / sqlite3 / uuid / zlib / **openssl** |
| 目标板 | Buildroot 2021.11；运行时库 libpcre / libxml2 / libsqlite3 / libuuid / libz / liblzma / libssl / libcrypto |
| 板端 Python | python3 + pip（用于 certbot / certbot-dns-aliyun） |

## 快速开始

1. 配置账号密码（本地，不入库）

```sh
cp .env.example .env
vi .env                      # WEBDAV_PASS=你的密码
```

2. 交叉编译

```sh
./build.sh
```

3. 部署到板子

```sh
./deploy.sh 192.168.2.5
```

4. 申请 Let's Encrypt 证书（板端执行，DNS-01 走阿里云 API）

```sh
# 凭据文件格式：
#   dns_aliyun_access_key = LTAI...
#   dns_aliyun_access_key_secret = ...
certbot certonly --non-interactive --agree-tos -m 你的邮箱 \
  --authenticator dns-aliyun \
  --dns-aliyun-credentials /userdata/certbot/aliyun.ini \
  --dns-aliyun-propagation-seconds 60 \
  -d bane2005.fun

# 合并给 lighttpd 用
cat /etc/letsencrypt/live/bane2005.fun/fullchain.pem \
    /etc/letsencrypt/live/bane2005.fun/privkey.pem \
    > /userdata/webdav/etc/server.pem
chmod 600 /userdata/webdav/etc/server.pem && chown www-data:www-data /userdata/webdav/etc/server.pem
```

5. 访问

```
公网/手机：https://bane2005.fun/        （Let's Encrypt，无需导入证书）
内网兼容：http://192.168.2.5:8080/     （Kazumi 等）
账号：.env 中的 WEBDAV_USER / WEBDAV_PASS
```

## 自动续期

- `/userdata/certbot/renew.sh`：`certbot renew` + `deploy-hook`
- `/userdata/certbot/deploy-hook.sh`：合并证书 → 重启 WebDAV
- `crond`（`S98crond`）每天 03:00 执行
- 日志：`/userdata/certbot/renew.log`


## 公网访问（Cloudflare Tunnel）

- 隧道: Cloudflare 命名 Tunnel `rk3568`（Zero Trust → Networks → Tunnels，token 方式）
- 板端: `/userdata/cloudflared/cloudflared`，token `/userdata/cloudflared/token`（600）
- 自启: `/etc/init.d/S99cloudflared`
- 公网地址: **https://bane2005.fun**（Cloudflare 边缘 TLS，无需公网 IP、无需路由器放行端口、无需本地证书）
- 内网仍可用: `http://192.168.2.5:8080/`、`https://192.168.2.5/`（Let's Encrypt）
- 已停用: ddns-go（`S99ddns-go.disabled`）；域名 NS 已迁到 Cloudflare
- Public Hostname 在 Cloudflare 侧配置: `bane2005.fun` → `http://localhost:8080`

## 板端管理

```sh
/etc/init.d/S51webdav {start|stop|restart}
/etc/init.d/S99ddns-go {start|stop|restart}
/etc/init.d/S98crond {start|stop|restart}
tail -f /userdata/webdav/log/error.log /userdata/certbot/renew.log
```

## 验证

```sh
U=webdav:你的密码
curl -u $U -X PROPFIND -H 'Depth: 1' https://bane2005.fun/    # 207（证书受信任，无需 -k）
curl -u $U -X PROPFIND -H 'Depth: 1' http://192.168.2.5:8080/ # 207（内网）
```

## 已知坑

1. `auth.backend = "plain"` 不支持 `{SHA}`，必须 `htpasswd` 后端
2. ssh 会话 umask 077 → `/userdata/webdav` 变 700，www-data 进不去 → deploy 里 `chmod 755`
3. 覆盖运行中的二进制报 `Text file busy` → deploy 先 stop 再 scp
4. `webdav.sqlite-db-name` 放 www-data 可写目录（`run/`）
5. Buildroot **没有 systemd**，`ddns-go -s install` 无效，用 `/etc/init.d/S99ddns-go`
6. 板端默认**没有 CA 证书**：`/etc/ssl/certs/ca-certificates.crt` 缺失会导致 certbot/ddns-go 报 `unknown authority`，需从编译机拷贝
7. lighttpd `server.bind = "::"` 会报 `getaddrinfo failed`，IPv6 要用 `$SERVER["socket"] == "[::]:443"` 块，并设 `net.ipv6.bindv6only=1`
8. `/var` 是 tmpfs，crontab 重启会丢 → `S98crond` 每次从 `/userdata/certbot/crontab` 重新安装
9. 443 需要 root 绑定：lighttpd root 启动后降权到 www-data

## 安全说明

- 公网入口是 HTTPS（Let's Encrypt），密码加密传输
- 8080 是明文，仅建议内网使用；设备无 iptables filter 表，无法做 IP 白名单
- 证书私钥 `server.pem` 权限 600、属主 www-data；`conf/*.pem`、`.env` 已在 `.gitignore`

## License

未指定。
