# 部署建议

Copyboard Lite 把 UnionID 作为嵌入式数据库使用。当前适合单机、单写入实例和约一万行的日常工作集；数据库文件必须位于持久磁盘，并且同一时刻只能由一个应用实例持有。

## 推荐顺序

| 方案 | 适用场景 | 关键约束 |
| --- | --- | --- |
| 单台 Linux 主机 + systemd + 反向代理 | 个人、小团队、最低运维复杂度；首选 | 后端只监听 loopback；Caddy/Nginx 终止 TLS；数据库和备份使用独立目录 |
| Docker/Podman Compose 单实例 | 希望镜像化交付 | 只运行一个后端副本；把 `/data` 挂载到本地持久卷；不要把数据库放在容器可写层 |
| 支持持久磁盘的 PaaS 单实例 | 希望托管构建和 TLS | 必须确认实例重启后磁盘仍保留、只能单副本挂载、能够停机备份和恢复演练 |

不推荐把后端部署到无持久磁盘的 serverless/edge runtime，也不要直接扩成多个共享同一 redb 文件的副本。需要高可用或水平扩容时，应先重新设计数据层，而不是复制当前进程。

## 推荐拓扑

```text
browser -- HTTPS --> reverse proxy
                       |-- /          --> static frontend
                       `-- /api,/health --> copyboard-lite:11030 (loopback)
                                                   |
                                                   `-- /var/lib/copyboard-lite/copyboard.redb
```

生产环境优先使用同源反向代理，减少 CORS 和 token 暴露面。当前前端 API 地址仍固定为本机开发地址，在远程部署前应增加构建期或运行期 API base 配置；在完成该项前，不应把现有前端产物直接当作远程生产构建。

## 运行要求

- 使用专用、无登录权限的操作系统用户运行后端；数据库目录只允许该用户读写。
- `COPYBOARD_USERS` 放入部署平台的 secret 配置，不写入镜像或仓库。它目前包含明文配置密码，访问权限应与数据库凭据相同。
- `COPYBOARD_SECRET` 使用至少 32 字节的随机值，并在所有正常重启间保持稳定；轮换会让现有登录 token 失效。
- 后端仅监听 `127.0.0.1` 或受限内部网络，由反向代理提供 TLS、请求大小限制、速率限制和访问日志。
- `/health` 当前只是进程存活检查，不执行数据库读写；可以用于 liveness，不应单独作为数据层 readiness 证明。
- 保持单后端副本。滚动发布应先停止旧实例、确认进程退出并释放 redb 锁，再启动新实例。

## 数据与备份

不要在应用运行时直接复制 `.redb` 文件。保守流程是：停止后端，使用同版本 UnionID 对数据库执行 `check`，生成 logical backup，验证恢复到一个新路径，然后再启动应用。备份文件必须复制到与应用主机故障域不同的位置。

建议至少定期演练以下恢复目标：

1. 在临时目录恢复 logical backup。
2. 用当前 Copyboard Lite 版本打开恢复库。
3. 登录测试用户并验证列表、创建、删除和重开。
4. 再次执行 UnionID 完整检查。

数据量增长、UnionID revision 变更或 schema migration 上线前，都应先在生产数据库副本执行同样的检查和应用读写测试。

## 上线前缺口

- 前端 API base 可配置化，并收紧生产 CORS origin。
- 为进程增加显式优雅关闭，确保停止接流后等待在途请求完成。
- 增加数据库 readiness 检查、结构化日志和基础指标。
- 提供可复现的 systemd 单元或 Compose 文件，以及备份/恢复脚本。

建议先完成这些项目，再选择具体平台。对于当前规模，单台 Linux 主机配 systemd 和反向代理是最简单、最符合 UnionID 运行边界的方案。

## 从 Actions 获取 Linux 二进制

仓库的 Release workflow 使用 `ubuntu-22.04` 构建 `x86_64-unknown-linux-gnu` release binary，并同时发布压缩包和 SHA-256 文件。创建版本 tag 后自动发布：

```bash
git tag v0.1.1
git push origin v0.1.1
```

在目标 VM 上下载并校验：

```bash
release=v0.1.1
base="https://github.com/Memkits/copyboard-lite/releases/download/${release}"
curl -fL -o copyboard-lite.tar.gz "${base}/copyboard-lite-linux-x86_64.tar.gz"
curl -fL -o copyboard-lite.tar.gz.sha256 "${base}/copyboard-lite-linux-x86_64.tar.gz.sha256"
sha256sum -c copyboard-lite.tar.gz.sha256
tar -xzf copyboard-lite.tar.gz
install -Dm755 copyboard-lite /usr/local/bin/copyboard-lite
```

构建基线固定为 Ubuntu 22.04，以兼容同代或更新的 glibc。目标机器首次部署前仍应执行 `cat /etc/os-release` 和 `ldd --version`；如果目标 glibc 低于构建环境，不能直接运行该包，应改用更旧的构建基线或增加 musl 构建。Release workflow 的 `workflow_dispatch` 只生成 Actions artifact；只有推送 `v*` tag 才发布 GitHub Release。
