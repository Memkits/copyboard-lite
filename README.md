# Copyboard Lite

一个用于验证 [UnionID](https://github.com/worktools/unionid) 的轻量 Copyboard：Rust/HTTP 后端、Calcit.js 前端，界面参考 `topixim/copyboard`。

## 开发

```bash
# 后端，默认 http://127.0.0.1:11030
cargo run

# 另一个终端：前端，默认 http://127.0.0.1:5173
yarn install
yarn compile
yarn dev
```

前端与后端运行在不同端口，后端为 `/health` 和 `/api/snippets` 开启 CORS。

## 后端独立测试

```bash
cargo test
```

测试覆盖 HTTP 创建、查询、CORS 和 UnionID 数据库重开后的持久化。
