# RK3568 WebDAV Server

在正点原子 **ATK-DLRK3568**（Buildroot 2021.11 / aarch64）上部署带认证的 **HTTPS WebDAV** 服务。

采用 **lighttpd 1.4.61 + mod_webdav + mod_openssl** 交叉编译后部署到 `/userdata`，无需重刷固件、不污染 rootfs。

## 特性

- 完整 WebDAV 语义：`PROPFIND` / `PROPPATCH` / `MKCOL` / `PUT` / `GET` / `COPY` / `MOVE` / `DELETE` / `LOCK` / `UNLOCK`
- **HTTPS**（TLS 1.2+，自签证书），明文 8080 已关闭
- HTTP Basic 认证，板上只存 `{SHA}` 摘要（不存明文）
- 独立端口 **443**，与板上已有 nginx(80)、vsftpd(21) 共存
- 开机自启（`/etc/init.d/S51webdav`），常驻内存约 4.5MB
- 一键交叉编译 + 一键部署，程序 550KB + 13 个模块

## 目录结构

```
.
├── build.sh              # 下载 lighttpd 源码 + 交叉编译（含 openssl）
├── deploy.sh             # scp 部署 + 安装开机自启 + 重启服务
├── conf/
│   ├── lighttpd.conf     # 板端配置（443 / WebDAV / 认证 / TLS）
│   ├── S51webdav         # 板端 init 脚本
│   └── gen-cert.sh       # 生成自签证书（本机执行，skipped by git）
├── .env.example          # 账号密码模板（复制为 .env）
└── TASKS.md              # 任务拆解 + 实测结果 + 已知坑
```

板端布局：

```
/userdata/webdav/
├── sbin/lighttpd
├── lib/*.so              # 13 个模块（含 mod_openssl）
├── etc/lighttpd.conf
├── etc/lighttpd.user     # {SHA} 认证文件
├── etc/server.pem        # 证书+私钥（600，不入库）
├── data/                 # WebDAV 根目录
├── log/                  # error.log / access.log
├── run/                  # pid + webdav.db（sqlite 属性库）
└── tmp/                  # 上传临时目录
/etc/init.d/S51webdav     # 开机自启
```

## 环境要求

| 端 | 依赖 |
|---|---|
| 编译主机 | `/opt/atk-dlrk356x-toolchain`（gcc 10.3.0），sysroot 需有 pcre / libxml2 / sqlite3 / uuid / zlib / **openssl** |
| 目标板 | Buildroot 2021.11，运行时库 `libpcre.so.1`、`libxml2.so.2`、`libsqlite3.so.0`、`libuuid.so.1`、`libz.so.1`、`liblzma.so.5`、`libssl.so.1.1`、`libcrypto.so.1.1` |

## 快速开始

1. 配置账号密码（本地文件，不入库）

```sh
cp .env.example .env
vi .env          # 改 WEBDAV_PASS
```

2. 交叉编译（首次自动下载并校验 lighttpd-1.4.61）

```sh
./build.sh
```

3. 生成自签证书（板端没有 openssl 命令，必须在本机生成）

```sh
./conf/gen-cert.sh 192.168.2.5
# 产物: conf/server.pem（证书+私钥，部署用）
#       conf/cert.pem （仅证书，客户端导入用）
```

4. 部署到板子（默认 `root@192.168.2.5`）

```sh
./deploy.sh 192.168.2.5
```

5. 使用

```
地址: https://192.168.2.5/
账号: .env 中的 WEBDAV_USER / WEBDAV_PASS
```

- macOS Finder：连接服务器 → `https://192.168.2.5/`
- Android：ES / Solid Explorer → 新建 WebDAV（HTTPS）
- Windows：映射网络驱动器 → `https://192.168.2.5/`（需先信任证书，见下节）

## 客户端信任自签证书

| 平台 | 做法 |
|---|---|
| Windows | 双击 `conf/cert.pem` → 安装到「受信任的根证书颁发机构」 |
| macOS | 钥匙串访问 → 导入 `cert.pem` → 设为「始终信任」 |
| iOS | AirDrop/邮件发送 `cert.pem` → 安装描述文件 → 设置中「证书信任设置」开启 |
| Android | 安装为用户证书（7.0+ App 默认不信任用户证书，可用支持自定义 CA 的客户端） |
| 临时跳过 | `curl -k` / 浏览器「高级 → 继续访问」 |

## 板端管理

```sh
/etc/init.d/S51webdav start|stop|restart
tail -f /userdata/webdav/log/error.log
```

## 验证

```sh
B=https://192.168.2.5
U=webdav:你的密码

curl -k -u $U -X PROPFIND -H 'Depth: 1' $B/     # 207
curl -k -u $U -T file.bin $B/file.bin           # 201
curl -k -u $U -o file.bin $B/file.bin           # 200
curl -k -u $U -X MKCOL $B/newdir                # 201
curl -k -u $U -X DELETE $B/newdir               # 204
```

## 已知坑

1. `auth.backend = "plain"` **不支持** `{SHA}`（只做明文比较），必须用 `htpasswd` 后端，否则一律 401
2. ssh 会话默认 umask 077，`/userdata/webdav` 会变 700，`www-data` 无法进入 → `deploy.sh` 已补 `chmod 755`
3. 覆盖运行中的二进制会报 `Text file busy` → `deploy.sh` 先 stop 再 scp
4. `webdav.sqlite-db-name` 必须放在 `www-data` 可写目录（本项目用 `run/`）
5. 重刷固件会丢失 `/etc/init.d/S51webdav`，重跑 `./deploy.sh` 即可恢复（`/userdata` 数据不受影响）
6. 443 需要 root 绑定：lighttpd 由 root 启动、绑端口后再降权到 `www-data`
7. 自签证书必须让客户端信任，否则 Windows WebClient / Finder 直接报证书错误
8. TLS 有 CPU 开销：loopback 4 并发从明文 330MB/s 降到 59MB/s（约 61% 单核），Wi-Fi 场景不受影响

## 安全说明

- 已启用 TLS；密码只保存在本机 `.env` 与板端 `{SHA}` 摘要文件
- `conf/server.pem` 含私钥，已在 `.gitignore` 排除，**不要提交**
- 自签证书适合内网/自用；若要对公网提供服务，建议用 Let's Encrypt（acme.sh）或 Cloudflare Tunnel 终止 TLS

## License

未指定。
