# RK3568 WebDAV Server

在正点原子 **ATK-DLRK3568**（Buildroot 2021.11 / aarch64）上部署带认证的 WebDAV 服务。

采用 **lighttpd 1.4.61 + mod_webdav** 交叉编译后部署到 `/userdata`，无需重刷固件、不污染 rootfs。

## 特性

- 完整 WebDAV 语义：`PROPFIND` / `PROPPATCH` / `MKCOL` / `PUT` / `GET` / `COPY` / `MOVE` / `DELETE` / `LOCK` / `UNLOCK`
- HTTP Basic 认证，板上只存 `{SHA}` 摘要（不存明文）
- 独立端口 **8080**，与板上已有 nginx(80)、vsftpd(21) 共存
- 开机自启（`/etc/init.d/S51webdav`），常驻内存约 **3MB**
- 一键交叉编译 + 一键部署，产物仅 320KB + 12 个模块

## 目录结构

```
.
├── build.sh              # 下载 lighttpd 源码 + 交叉编译
├── deploy.sh             # scp 部署 + 安装开机自启 + 重启服务
├── conf/
│   ├── lighttpd.conf     # 板端配置（8080 / WebDAV / 认证）
│   └── S51webdav         # 板端 init 脚本
├── .env.example          # 账号密码模板（复制为 .env）
└── TASKS.md              # 任务拆解 + 实测结果 + 已知坑
```

板端布局：

```
/userdata/webdav/
├── sbin/lighttpd
├── lib/*.so              # 12 个模块
├── etc/lighttpd.conf
├── etc/lighttpd.user     # {SHA} 认证文件
├── data/                 # WebDAV 根目录
├── log/                  # error.log / access.log
├── run/                  # pid + webdav.db（sqlite 属性库）
└── tmp/                  # 上传临时目录
/etc/init.d/S51webdav     # 开机自启
```

## 环境要求

| 端 | 依赖 |
|---|---|
| 编译主机 | `/opt/atk-dlrk356x-toolchain`（aarch64-buildroot-linux-gnu-gcc 10.3.0），sysroot 内需有 pcre / libxml2 / sqlite3 / uuid / zlib |
| 目标板 | Buildroot 2021.11，运行时库 `libpcre.so.1`、`libxml2.so.2`、`libsqlite3.so.0`、`libuuid.so.1`、`libz.so.1`、`liblzma.so.5` |

## 快速开始

1. 配置账号密码（本地文件，不入库）

```sh
cp .env.example .env
vi .env          # 改 WEBDAV_PASS
```

2. 交叉编译（首次会自动下载并校验 lighttpd-1.4.61）

```sh
./build.sh
```

3. 部署到板子（默认 `root@192.168.2.5`）

```sh
./deploy.sh 192.168.2.5
```

4. 使用

```
地址: http://192.168.2.5:8080/
账号: .env 中的 WEBDAV_USER / WEBDAV_PASS
```

- macOS Finder：连接服务器 → `http://192.168.2.5:8080/`
- Android：ES / Solid Explorer → 新建 WebDAV
- Windows：映射网络驱动器（HTTP 下 Basic 认证需改注册表 `BasicAuthLevel=2`，建议改用 HTTPS）

## 板端管理

```sh
/etc/init.d/S51webdav start|stop|restart
tail -f /userdata/webdav/log/error.log
```

## 验证

```sh
B=http://192.168.2.5:8080
U=webdav:你的密码

curl -u $U -X PROPFIND -H 'Depth: 1' $B/          # 207
curl -u $U -T file.bin $B/file.bin                # 201
curl -u $U -o file.bin $B/file.bin                # 200
curl -u $U -X MKCOL $B/newdir                     # 201
curl -u $U -X DELETE $B/newdir                    # 204
```

## 已知坑

1. `auth.backend = "plain"` **不支持** `{SHA}`（只做明文比较），必须用 `htpasswd` 后端，否则一律 401
2. ssh 会话默认 umask 077，`/userdata/webdav` 会变 700，`www-data` 无法进入 → `deploy.sh` 已补 `chmod 755`
3. 覆盖运行中的二进制会报 `Text file busy` → `deploy.sh` 先 stop 再 scp
4. `webdav.sqlite-db-name` 必须放在 `www-data` 可写目录（本项目用 `run/`）
5. 重刷固件会丢失 `/etc/init.d/S51webdav`，重跑 `./deploy.sh` 即可恢复（`/userdata` 数据不受影响）

## 安全说明

- 默认 **HTTP 明文**，仅建议在可信局域网使用；需要公网/跨网访问请增加 TLS（`ssl.engine` + 证书）
- 密码只保存在本机 `.env` 与板端 `{SHA}` 摘要文件；`.env`、`build/` 已在 `.gitignore` 中排除

## License

未指定。
