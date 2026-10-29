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

## 使用者影响：Respo + Respo UI 界面

前端改为 Respo 组件树（`app.schema`、`app.updater`、`app.comp`、`app.lite`），按钮、输入框和文本框统一使用
Respo UI 0.9.0（`comp-button` 及 `respo-ui.css`），主题色通过 `assets/main.css` 中的 `--rui-*` 变量覆盖为原有紫色。
`index.html` 只保留 `#app` 挂载点。工具链升级为 Calcit 0.32.1 / `@calcit/procs` 0.32.1，依赖 Respo 0.17.1、JS-FFI 0.2.9；
Respo UI 引用的 `cirru-color`、`copy-text-to-clipboard`、`dayjs` 作为前端依赖加入。

超过约 6 行（或 360 字）的内容默认折叠并淡出，点击内容或“展开”后最多显示 520px（不超过 60vh），
其余部分在条目内部滚动，“收起”恢复折叠。

鉴权行为不变：token 与用户名保存在 localStorage，每次请求带 Bearer header 并保存 `x-copyboard-token` 续期，
只在 401 时退出；页面重新可见、获得焦点或恢复联网时自动刷新。Rust 后端、协议和数据库不变。

## 历史：正式 Calcit 0.32.0

前端 CLI/procs 配对正式 0.32.0，JS-FFI 固定已发布的 0.2.8。请安装完整模块图、
重新生成 JS 并刷新。本次将类型标注迁为 quoted 类型表达式；24 个定义的 schema 保持。
Rust 源码、依赖和 lock、UnionID schema、鉴权、token/Cookie、snippet 字段与部署路径不变。

使用 0.32.0 的官方 `config unset entry --entry server` 删除误指向浏览器函数的旧入口。
后端一直由 Cargo 启动；前端仍使用默认 JS entry。不要使用 `calcit --entry server` 启动后端。
原全定义、完整 strict、弃用零门禁、Rust format/Clippy/tests 及构建命令保持；
不增加验证脚本、预算、强转或 concurrently。COS 继续仅使用 action 内置校验。

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
