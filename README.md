# Copyboard Lite

一个用于验证 [UnionID](https://github.com/worktools/unionid) 的轻量 Copyboard：Rust/HTTP 后端、Calcit.js 前端，界面参考 `topixim/copyboard`。

后端使用 UnionID v0.6 的 Rust-shaped 语法（`struct`、`field: Type`、`table name: Type { ... }`）声明 schema 和 migration；UnionID revision 固定在 `Cargo.toml`，便于重现验证结果。

## 开发

```bash
# 后端，默认 http://127.0.0.1:11030
COPYBOARD_USERS='alice:change-me,bob:another-password' \
COPYBOARD_SECRET='replace-with-at-least-32-random-bytes' \
cargo run

# 另一个终端：前端，默认 http://127.0.0.1:5173
yarn install
yarn dev
```

前端与后端运行在不同端口，后端为 `/health` 和 `/api/snippets` 开启 CORS。

前端使用 Calcit 0.27.0 和 `js-ffi.browser` 的类型化浏览器接口。监听文档可见性变化时
直接调用 `document-add-event-listener!`，不再把 `js/document` 当作 DOM 元素。

`yarn dev` 会先编译一次再启动 Vite；需要监听 Calcit 修改时，在独立终端运行
`calcit calcit.cirru -w`，不额外引入并发进程依赖。生产构建使用 `yarn build`。

前端静态资源通过正式 COS action v1.2.0 上传，并由 action 内置能力校验 HTML
引用和公开资源内容，不维护额外 CDN 校验脚本。`VITE_BASE_URL` 设置资源 CDN
前缀；PR 上传路径包含 PR 编号、run id 和 attempt，避免不同预览相互覆盖。
生产服务器前端目录和 Rust 后端部署保持不变。

鉴权配置缺失或无效时后端会拒绝启动：

- `COPYBOARD_USERS`：逗号分隔的 `用户名:密码`；用户名仅允许 3–32 位字母、数字、`_` 和 `-`。
- `COPYBOARD_SECRET`：至少 32 字节的随机会话签名密钥。

登录后会同时返回签名 Bearer token，并写入 `HttpOnly`、`Secure`、`SameSite=Lax` 的会话 Cookie。会话有效期为三天；每次成功的鉴权请求都会重新签发三天有效期的 Cookie 和 token，实现滑动续期。所有 snippet 查询、创建和删除都会使用会话中的用户名作为 UnionID 数据过滤条件；旧版本的共享数据迁移到不可登录的 `legacy` 所有者。

## 后端独立测试

```bash
cargo test
```

测试覆盖登录、未授权拒绝、用户间读写隔离、CORS 和 UnionID 数据库重开后的持久化。

部署边界、方案对比、备份恢复和上线前缺口见 [部署建议](docs/DEPLOYMENT.md)。

Linux x86_64 发版二进制由 Actions 的 `v*` tag workflow 生成，下载、校验和安装步骤见 [部署建议](docs/DEPLOYMENT.md#从-actions-获取-linux-二进制)。
