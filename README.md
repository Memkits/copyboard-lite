# Copyboard Lite

一个用于验证 [UnionID](https://github.com/worktools/unionid) 的轻量 Copyboard：Rust/HTTP 后端、Calcit.js 前端，界面参考 `topixim/copyboard`。

后端使用 Rust-shaped 语法（`struct`、`field: Type`、`table name: Type { ... }`）声明 schema 和 migration；当前正式 UnionID/unionid-query 0.9.1 在 `Cargo.toml` 与 `Cargo.lock` 精确锁定，便于重现验证结果。本轮不改后端依赖、源码、协议或数据库。

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

## 使用者影响：正式 Calcit 0.30.1

前端 CLI/procs 配对正式 0.30.1，JS-FFI 固定已发布的 0.2.6。请重新安装完整模块图、
生成 JS 并刷新，不混用旧 alpha 缓存。本轮修改前端公开调用写法，不修改 Rust 源码/依赖/lock、
UnionID schema、鉴权、token/Cookie、snippet 字段或部署路径。
CI 的原检查命令补充 fail-fast/pipefail，前序安装、Clippy、类型或弃用门禁失败不会被后续
构建成功掩盖；不新增验证脚本、预算、强转或 concurrently，COS 继续仅使用 action 内置 verify。
不合并、部署前端/后端、发布 tag/npm 或启动生产服务。

清理33处旧Option/count调用，采用公开 `.unwrap` / `.unwrap-or` / `.some?` / `.len`。
其中登录用户名、密码和提交内容的三处DOM取值改用已发布 `browser/element-value`，
让真正的输入值受检为String，不再把DomElementHost当函数调用。
正常输入框和鉴权协议不变；缺失或非String宿主值不再静默当空串，而是更早报告合同错误。
原参数、回调、URL判断、数组验证和后端隔离保持，不新增unsafe或质量预算。

## 历史：此前已合并的前端源码迁移

此前使用 0.30.1-alpha.5 / JS-FFI 0.2.3 配对，将旧 defatom 改为等价 defref，
并明确可见性刷新回调返回 Unit，避免异步调用结果泄漏到事件回调。

前端沿用 js-ffi 类型化浏览器接口。监听文档可见性变化时
直接调用 `document-add-event-listener!`，不再把 `js/document` 当作 DOM 元素。

`yarn dev` 会先编译一次再启动 Vite；需要监听 Calcit 修改时，在独立终端运行
`calcit calcit.cirru -w`，不额外引入并发进程依赖。生产构建使用 `yarn build`。

前端静态资源通过正式 COS action v1.2.0 上传，并由 action 内置能力校验 HTML
引用和公开资源内容，不维护额外 CDN 校验脚本。`VITE_BASE_URL` 设置资源 CDN
前缀；PR 上传路径包含 PR 编号、run id 和 attempt，避免不同预览相互覆盖。
生产服务器前端目录和 Rust 后端部署保持不变。

`yarn check` / CI 检查规范格式、全定义严格类型、完整 strict verify 和弃用调用零门禁，不应用迁移改写。
snippet 数组入口使用 `Array.isArray` 与 `js-cast` 检查，原有内容、ID 和时间字段校验保留。
规范文件为 `calcit.cirru`、`deps.cirru`，不提交旧快照或生成的前端资源。

此前全定义 26/26、完整 strict、不可变安装与生产构建通过；Rust format/check/Clippy 和原有
9 项测试通过。临时 Node 验证真实 URL 判断、数组 kind/身份和未登录 Unit 回调，不添加永久
测试框架或验证脚本。前端没有定义附加测试，不以空测试选择声称测试通过。
实际浏览器未登录界面正常且捕获的 warning/error 为空；合成账户登录与 token 保存仍待授权，
未声称已完成登录后页面、剪贴板写入或持久化浏览器验收。

Snapshot 中旧 `server` entry 仍指向同一浏览器函数，不是 Rust 后端入口，不应使用它启动服务。
删除 entry 的通用接口需求原报 [Calcit #2212](https://github.com/calcit-lang/calcit/issues/2212)，
现已作为重复项关闭并集中到仍开放的 [#2104](https://github.com/calcit-lang/calcit/issues/2104)
（0.31.1 里程碑，并非已发布能力）。等待通用接口后清理，不手改 Snapshot 或新增项目专用重写规则。
CI/前端部署 Actions 使用精确正式 tag，接受可移动 tag 风险；不修改独立 Rust release workflow。

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
