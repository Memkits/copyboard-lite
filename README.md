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
yarn compile
yarn dev
```

前端与后端运行在不同端口，后端为 `/health` 和 `/api/snippets` 开启 CORS。

鉴权配置缺失或无效时后端会拒绝启动：

- `COPYBOARD_USERS`：逗号分隔的 `用户名:密码`；用户名仅允许 3–32 位字母、数字、`_` 和 `-`。
- `COPYBOARD_SECRET`：至少 32 字节的随机会话签名密钥。

登录后返回 24 小时有效的签名 Bearer token。所有 snippet 查询、创建和删除都会使用 token 中的用户名作为 UnionID 数据过滤条件；旧版本的共享数据迁移到不可登录的 `legacy` 所有者。

## 后端独立测试

```bash
cargo test
```

测试覆盖登录、未授权拒绝、用户间读写隔离、CORS 和 UnionID 数据库重开后的持久化。
