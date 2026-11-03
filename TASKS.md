# WebDAV 部署任务（lighttpd + mod_webdav）

- 设备: `root@192.168.2.5` | Buildroot 2021.11 / aarch64 / 3.7G RAM
- 服务: lighttpd 1.4.61 + mod_webdav（props + locks 全开）
- 端口: **8080**（80=nginx、21=vsftpd 已占用）
- 数据: `/userdata/webdav/data`（`/userdata` 50G 可用）
- 运行用户: `www-data`(33)，降权启动
- 账号: `webdav` / 密码见本机 `.env`（不入库，板上只存 `{SHA}` 摘要）

## 环境事实（已探测）

- 工具链 `/opt/atk-dlrk356x-toolchain`；sysroot 含 pcre/libxml2/sqlite3/uuid/zlib（含 `.pc`、`pcre-config`、`xml2-config`）
- 板端运行库 `libpcre.so.1` / `libxml2.so.2` / `libsqlite3.so.0` / `libuuid.so.1` / `libz.so.1` 齐全
- rootfs `/dev/mmcblk0p6` ext4 **rw**；`start-stop-daemon` 可用（busybox）
- 板上无 `/usr/sbin/lighttpd`；nginx 未编 `http_dav_module`，故不复用 nginx
- 本机缺 autoconf/automake/libtool（lighttpd tarball 的 configure 在 buildroot 中被 AUTORECONF）
- 源码: `lighttpd-1.4.61.tar.xz`
  sha256 `43f0d63d04a1b7c5b8aab07e0612e44ccad0afc0614bab784c5b019872363432`

## 目录规划

板端：

```
/userdata/webdav/
├── sbin/lighttpd
├── lib/*.so              # 只保留必需模块（12 个）
├── etc/lighttpd.conf
├── etc/lighttpd.user     # 认证文件（{SHA}）
├── data/                 # WebDAV 根
├── log/                  # error.log / access.log
├── run/                  # pid + webdav.db（sqlite 属性库）
└── tmp/                  # 上传临时目录
/etc/init.d/S51webdav     # 开机自启（重刷固件会丢，deploy.sh 负责重装）
```

本机：

```
app/webdav/
├── TASKS.md              # 本文件
├── build.sh              # 交叉编译（风格对齐 app/rknn_rtsp_qt/build.sh）
├── deploy.sh             # 一键部署（风格对齐 app/rknn_rtsp_qt/deploy.sh）
├── conf/lighttpd.conf    # 配置模板
├── conf/S51webdav        # 板端启动脚本模板
└── build/                # 编译中间产物 + 下载的源码
```

## 任务（已完成 ✅）

- [x] T1 下载 `lighttpd-1.4.61.tar.xz` 到 `build/`，sha256 校验通过
- [x] T2 tarball 自带 `configure` 可用，`--with-webdav-props/locks` 均识别（无需 autotools）
- [x] T3 `build.sh` 交叉编译完成 → `build/out/sbin/lighttpd`(320K) + `build/out/lib/*.so`(12 个模块)
      - `--with-webdav-props --with-webdav-locks --with-pcre --with-zlib`
      - 依赖: bin→libpcre/libc；mod_webdav→libxml2/libz/liblzma/libsqlite3/libuuid（板端全有）
- [x] T4 `conf/lighttpd.conf`：8080 / docroot / auth / webdav / 目录列表 / accesslog
- [x] T5 认证文件 `{SHA}`：**必须用 `auth.backend = "htpasswd"`**（`plain` 后端只做明文比较，会 401）
- [x] T6 `deploy.sh`：停服务 → scp → chmod/chown → 重装 S51webdav → 重启 → 端口自检
- [x] T7 板端 `/etc/init.d/S51webdav`（pid: `/userdata/webdav/run/lighttpd.pid`）
- [x] T8 协议验证全部通过（见下方"实测结果"）
- [x] T9 curl 模拟客户端语义通过（PROPFIND/LOCK）；Windows/macOS/手机真机挂载待验证
- [x] T10 reboot 后自动启动 ✅；master RSS ≈ 2.9MB

## 实测结果（2026-11-03）

| 项 | 结果 |
|---|---|
| 未认证访问 | `401` |
| PROPFIND Depth:1 | `207`，返回 DAV multistatus + `supportedlock` |
| MKCOL / PUT / GET / COPY / MOVE / DELETE | `201 / 201 / 200 / 201 / 201 / 204` |
| LOCK / UNLOCK | `200 / 204`（`Lock-Token: <urn:uuid:...>`） |
| 50MB 上传 | `201`，36.9s ≈ **1.4MB/s**（Wi-Fi 上行） |
| 50MB 下载 | `200`，4.1s ≈ **12.8MB/s**，内容一致 |
| reboot 自启 | 通过：关机停止 → 开机 `server started`，PROPFIND 207 |
| 内存 | lighttpd master `VmRSS ≈ 2.9MB` |

## 资源占用（实测 2026-11-03）

| 场景 | CPU（占单核） | VmRSS | 说明 |
|---|---|---|---|
| 空闲（无请求） | **0%**（10s 内 0 ticks） | **3.0MB** | 1 进程 / 1 线程 / 11 个 fd |
| 3 路并发（Wi-Fi，~0.4–1.4MB/s） | **2.0–2.7%** | 3.3MB 峰值 | 瓶颈在 Wi-Fi 与板上其他负载 |
| loopback 4 路下载 400MB | **25.6–26.3%** | 3.0MB | 310–339 MB/s，≈1200MB/s/核 |

- 程序体积：`sbin` 321K + `lib` 217K ≈ **538KB**；配置+认证 5K；sqlite 属性库 20K
- RSS 不随传输大小增长：文件走 `sendfile` 零拷贝，不经用户态缓冲
- 换算：约每 **100MB/s 吞吐消耗 8% 单核**
- 日志随访问量增长（`access.log` 19K 时约 200 次请求），可按需加日志轮转

## 已知坑（踩过）

1. `auth.backend = "plain"` 不支持 `{SHA}`，必须用 `htpasswd` 后端
2. ssh 会话 umask 077 → `/userdata/webdav` 变 700，www-data 无法进入；deploy 里已 `chmod 755`
3. 覆盖运行中的二进制会 `Text file busy`；deploy 先 stop 再 scp
4. `webdav.sqlite-db-name` 要放 www-data 可写目录（用 `run/`，不是 `etc/`）

## 验证命令（预留）

```sh
# 列目录
curl -s -u user:pass -X PROPFIND -H "Depth: 1" http://192.168.2.5:8080/ | head
# 上传/下载/删除
curl -u user:pass -T big.bin http://192.168.2.5:8080/big.bin
curl -u user:pass -o big.bin http://192.168.2.5:8080/big.bin
curl -u user:pass -X DELETE http://192.168.2.5:8080/big.bin
```

## 回滚

```sh
/etc/init.d/S51webdav stop
rm -f /etc/init.d/S51webdav
rm -rf /userdata/webdav        # 注意先备份 data/
```

## 可选增强

- TLS：自签证书 + `ssl.engine = "enable"`（Windows 需导入证书）
- nginx 80 端口反代 `/webdav` → `127.0.0.1:8080`（规避非标端口）
- 只读挂载、多用户、目录列表美化

## 风险

- tarball configure 与 buildroot AUTORECONF 差异 → 编译前先确认 `--with-webdav-props/locks` 被识别
- 重刷固件会丢 `/etc/init.d/S51webdav` → 由 `deploy.sh` 重装（或后续做 rootfs overlay 集成）
- `/userdata/webdav/data` 权限必须给 `www-data`，否则 WebDAV 写入报 500/403

## 待定

- [x] 账号密码：`webdav` / 见本机 `.env`（`WEBDAV_PASS`）
- [x] 已允许写入（`webdav.is-readonly = "disable"`）
- [ ] 是否需要 HTTPS（自签证书 + `ssl.engine`）

## 使用

```sh
# 首次：配置账号密码（.env 已在 .gitignore，不会入库）
cp .env.example .env
vi .env                    # WEBDAV_USER / WEBDAV_PASS

# 部署（默认 192.168.2.5/root）
cd /home/alientek/RK3568/app/webdav
./build.sh                 # 首次/改动后编译
./deploy.sh 192.168.2.5    # 部署并重启（密码从 .env 读取）

# 板端
/etc/init.d/S51webdav {start|stop|restart}
tail -f /userdata/webdav/log/error.log
```

- Windows: 资源管理器 → 映射网络驱动器 → `http://192.168.2.5:8080/`
  （WebClient 默认只允许 HTTPS 下 Basic 认证，HTTP 需改注册表 `BasicAuthLevel=2`，或后续加 TLS）
- macOS: Finder → 连接服务器 → `http://192.168.2.5:8080/`
- Android: 文件管理器/ES、Solid Explorer 添加 WebDAV

## HTTPS（Let's Encrypt，2026-11-03）

- 证书: `bane2005.fun`，Let's Encrypt，有效期至 **2027-02-01**，90 天自动续期
- 申请: certbot 5.9.0 + certbot-dns-aliyun（pip 装在板上持久化），DNS-01 走阿里云 API
- 凭据: `/userdata/certbot/aliyun.ini`（复用 ddns-go 的 AccessKey，600）
- 续期: crond 每天 03:00 跑 `/userdata/certbot/renew.sh` → `deploy-hook.sh` 合并 `server.pem` 并重启 WebDAV
- 端口: **443 HTTPS**（IPv4+IPv6）/ **8080 HTTP**（内网，Kazumi 等）
- 验证: `curl --resolve bane2005.fun:443:192.168.2.5 ... https://bane2005.fun/` → `207`，`Verify return code: 0 (ok)`，TLSv1.3
- 踩坑: 板端缺 CA（已补）；`server.bind="::"` 不支持需用 `[::]:443` 块；`/var` 是 tmpfs 导致 crontab 丢失（S98crond 重装）
