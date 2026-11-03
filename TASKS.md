# WebDAV 部署任务（lighttpd + mod_webdav）

- 设备: `root@192.168.2.5` | Buildroot 2021.11 / aarch64 / 3.7G RAM
- 服务: lighttpd 1.4.61 + mod_webdav（props + locks 全开）+ **HTTPS (mod_openssl)**
- 端口: **443 / HTTPS**（80=nginx、21=vsftpd 已占用；原 8080 明文已关闭）
- 数据: `/userdata/webdav/data`（`/userdata` 50G 可用）
- 运行用户: `www-data`(33)，降权启动
- 账号: `webdav` / 密码见本机 `.env`（不入库，板上只存 `{SHA}` 摘要）

## 环境事实（已探测）

- 工具链 `/opt/atk-dlrk356x-toolchain`；sysroot 含 pcre/libxml2/sqlite3/uuid/zlib（含 `.pc`、`pcre-config`、`xml2-config`）
- 板端运行库 `libpcre.so.1` / `libxml2.so.2` / `libsqlite3.so.0` / `libuuid.so.1` / `libz.so.1` / `liblzma.so.5` / `libssl.so.1.1` / `libcrypto.so.1.1` 齐全
- 工具链 sysroot 含 openssl 1.1（头文件 + `libssl.so`/`libcrypto.so` + `openssl.pc`）；板端无 `openssl` 命令，证书须本机生成
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
- [x] T3 `build.sh` 交叉编译完成 → `build/out/sbin/lighttpd`(312K) + `build/out/lib/*.so`(13 个模块)
      - `--with-webdav-props --with-webdav-locks --with-pcre --with-zlib --with-openssl`
      - 依赖: bin→libpcre/libc；mod_webdav→libxml2/libz/liblzma/libsqlite3/libuuid；mod_openssl→libssl/libcrypto（板端全有）
- [x] T4 `conf/lighttpd.conf`：443+TLS / docroot / auth / webdav / 目录列表 / accesslog
- [x] T5 认证文件 `{SHA}`：**必须用 `auth.backend = "htpasswd"`**（`plain` 后端只做明文比较，会 401）
- [x] T6 `deploy.sh`：停服务 → scp → chmod/chown → 重装 S51webdav → 重启 → 端口自检
- [x] T7 板端 `/etc/init.d/S51webdav`（pid: `/userdata/webdav/run/lighttpd.pid`）
- [x] T8 协议验证全部通过（见下方"实测结果"）
- [x] T9 curl 模拟客户端语义通过（PROPFIND/LOCK）；Windows/macOS/手机真机挂载待验证
- [x] T10 reboot 后自动启动 ✅；master RSS ≈ 4.5MB（TLS）
- [x] T11 切换到 HTTPS：启用 `mod_openssl`、自签证书（`conf/gen-cert.sh`）、关闭 8080（2026-11-03）

## 实测结果（2026-11-03）

| 项 | 结果 |
|---|---|
| 未认证访问 | `401` |
| PROPFIND Depth:1 | `207`，返回 DAV multistatus + `supportedlock` |
| MKCOL / PUT / GET / COPY / MOVE / DELETE | `201 / 201 / 200 / 201 / 201 / 204` |
| LOCK / UNLOCK | `200 / 204`（`Lock-Token: <urn:uuid:...>`） |
| 50MB 上传（HTTP，历史） | `201`，36.9s ≈ **1.4MB/s**（Wi-Fi 上行） |
| 50MB 下载（HTTP，历史） | `200`，4.1s ≈ **12.8MB/s**，内容一致 |
| 50MB 上传（HTTPS） | `201`，69.0s ≈ **760KB/s** |
| 50MB 下载（HTTPS） | `200`，13.6s ≈ **3.9MB/s**，内容一致 |
| HTTPS loopback 4 并发 400MB | 6.76s ≈ **59MB/s**，lighttpd 61.4% 单核 |
| 明文 8080 | 已关闭（连接失败） |
| reboot 自启 | 通过：关机停止 → 开机 `server started`，PROPFIND 207 |
| 内存 | lighttpd master `VmRSS ≈ 2.9MB` |

## 资源占用（实测 2026-11-03）

| 场景 | CPU（占单核） | VmRSS | 说明 |
|---|---|---|---|
| 空闲（无请求，HTTPS） | **0%** | **4.5MB** | 1 进程 / 1 线程 |
| Wi-Fi 下 HTTPS 传输 50MB | **34.3%** | 5.3MB 峰值 | 760KB/s ~ 3.9MB/s，瓶颈在 Wi-Fi |
| HTTPS loopback 4 路 400MB | **61.4%** | 4.5MB | 59MB/s，≈96MB/s/核 |
| （历史）明文 loopback 4 路 | 25.6–26.3% | 3.0MB | 310–339MB/s，≈1200MB/s/核 |

- 程序体积：`sbin` 321K + `lib` 217K ≈ **538KB**；配置+认证 5K；sqlite 属性库 20K
- RSS 不随传输大小增长：文件走 `sendfile` 零拷贝，不经用户态缓冲
- 换算：约每 **100MB/s 吞吐消耗 8% 单核**
- 日志随访问量增长（`access.log` 19K 时约 200 次请求），可按需加日志轮转

## 已知坑（踩过）

1. `auth.backend = "plain"` 不支持 `{SHA}`，必须用 `htpasswd` 后端
2. ssh 会话 umask 077 → `/userdata/webdav` 变 700，www-data 无法进入；deploy 里已 `chmod 755`
3. 覆盖运行中的二进制会 `Text file busy`；deploy 先 stop 再 scp
4. `webdav.sqlite-db-name` 要放 www-data 可写目录（用 `run/`，不是 `etc/`）
5. 443 需要 root 绑定：lighttpd 以 root 启动、绑端口后再降权到 www-data
6. 自签证书必须让客户端信任，否则 Windows WebClient / macOS Finder 直接报证书错误
7. TLS 有明显 CPU 开销：loopback 从明文 330MB/s 降到 59MB/s（约 61% 单核）；Wi-Fi 场景不受影响

## 验证命令（预留）

```sh
# 列目录
curl -sk -u user:pass -X PROPFIND -H "Depth: 1" https://192.168.2.5/ | head
# 上传/下载/删除
curl -k -u user:pass -T big.bin https://192.168.2.5/big.bin
curl -k -u user:pass -o big.bin https://192.168.2.5/big.bin
curl -k -u user:pass -X DELETE https://192.168.2.5/big.bin
```

## 回滚

```sh
/etc/init.d/S51webdav stop
rm -f /etc/init.d/S51webdav
rm -rf /userdata/webdav        # 注意先备份 data/
```

## 可选增强

- 公网访问：Cloudflare Tunnel / frp（设备无 TUN、无 nat 表，做不了 NAT 网关）
- nginx 80 端口反代 `/webdav` → `127.0.0.1:8080`（规避非标端口）
- 只读挂载、多用户、目录列表美化

## 风险

- tarball configure 与 buildroot AUTORECONF 差异 → 编译前先确认 `--with-webdav-props/locks` 被识别
- 重刷固件会丢 `/etc/init.d/S51webdav` → 由 `deploy.sh` 重装（或后续做 rootfs overlay 集成）
- `/userdata/webdav/data` 权限必须给 `www-data`，否则 WebDAV 写入报 500/403

## 待定

- [x] 账号密码：`webdav` / 见本机 `.env`（`WEBDAV_PASS`）
- [x] 已允许写入（`webdav.is-readonly = "disable"`）
- [x] 已启用 HTTPS（自签证书 10 年，443；客户端需导入 `conf/cert.pem`）

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

- Windows: 映射网络驱动器 → `https://192.168.2.5/`（先导入 `conf/cert.pem` 到受信任根证书）
- macOS: Finder → 连接服务器 → `https://192.168.2.5/`（钥匙串信任 cert.pem）
- Android: 文件管理器/ES、Solid Explorer 添加 WebDAV
