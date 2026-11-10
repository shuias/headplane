# Headplane

> 为 [Headscale](https://headscale.net) 提供功能完整的 Web 管理界面

[English](./README.md) | **简体中文**

<picture>
    <source
        media="(prefers-color-scheme: dark)"
        srcset="./docs/assets/preview-dark.png"
    >
    <source
        media="(prefers-color-scheme: light)"
        srcset="./docs/assets/preview-light.png"
    >
    <img
        alt="界面预览"
        src="./docs/assets/preview-dark.png"
    >
</picture>

Headscale 是 Tailscale 的社区自托管实现，基于 WireGuard 组网。它本身不带 Web
界面，Headplane 正为此而存在：可以在浏览器里管理节点、网络和 ACL。Headplane
以对齐 Tailscale 官方控制台为目标，是目前功能最完整的 Headscale 界面之一。

## 功能

- 节点管理：过期时间、子网路由、名称与所有者
- ACL 与标签（tag）配置，用于策略下发
- 支持 OpenID Connect（OIDC）单点登录
- 编辑 DNS 设置并自动下发到 Headscale
- 直接修改 Headscale 的运行配置

## 本地部署（本仓库）

本仓库 fork 自 [tale/headplane](https://github.com/tale/headplane)，并附带一套
可独立运行的 Docker Compose 环境：Headplane + Headscale + Dex（本地 OIDC 提供方）
+ Traefik。适合在单机上验证 OIDC 登录以及 Headplane 与 Headscale 的集成。

### 服务组成

| 服务       | 容器名                | 镜像                              | 对外端口           | 作用                              |
| ---------- | --------------------- | --------------------------------- | ------------------ | --------------------------------- |
| traefik    | `headplane-traefik`   | `traefik:v3.2`                    | `8082`、`8081`     | 统一入口，按路径分流              |
| dex        | `headplane-dex`       | `ghcr.io/dexidp/dex:v2.41.1`      | 内部 `5556`        | 为 Headplane 与 Headscale 签发令牌 |
| headscale  | `headscale`           | `headscale/headscale:0.29.3`      | 内部 `8080`        | 控制服务器                        |
| headplane  | `headplane`           | `ghcr.io/tale/headplane:latest`   | 内部 `3000`        | Web 界面，挂载在 `/admin`         |
| nginx-auth | `headplane-nginx-auth`| `nginx:1.27-alpine`               | 无                 | 可选的 Basic Auth 边车，默认停用   |

`8082` 端口上的分流规则：

| 路径                                     | 后端      |
| ---------------------------------------- | --------- |
| `/admin` 及 `/admin/**`                  | Headplane |
| `/.well-known/**`、`/dex/**`、`/oidc/**` | Dex       |
| 其余路径                                 | Headscale |

### 前置条件

- Docker 26 及以上，Compose v2/v5
- 主机与浏览器都能把 `dex.local` 解析到 `127.0.0.1`：

  ```sh
  sudo sh -c 'echo "127.0.0.1 dex.local" >> /etc/hosts'
  ```

  容器内部不需要这份 hosts 记录：Compose 已为 Headplane 与 Headscale 把
  `dex.local` 映射到 `host-gateway`，因此 OIDC 发现请求在容器内同样可用。

### 首次启动

1. 生成本地密钥文件与 `.env` 模板：

   ```sh
   ./scripts/bootstrap-secrets.sh
   ```

2. 补齐脚本提示缺失的内容：

   - `secrets/headplane_headscale_api_key`：栈启动后执行
     `docker exec headscale headscale apikeys create`，把输出的 key 写入该文件。
   - `.env`：两个客户端密钥（需与 `secrets/` 中对应文件一致），以及两个演示
     用户的 bcrypt 密码哈希。

3. 启动：

   ```sh
   docker compose up -d
   docker compose ps
   ```

4. 打开 <http://dex.local:8082/admin/login>，用 `alice@example.com` / `secret123`
   登录，首个 OIDC 用户自动成为 Owner。

### 登录链路

```text
浏览器 ──> Traefik :8082 ──> Headplane :3000 (/admin)
               │                    │
               ├──> Dex :5556       │ OIDC 授权码 + PKCE
               │    (issuer/JWKS)   │
               └──> Headscale :8080 │ API Key（用户、节点、ACL）
```

浏览器通过 Dex 完成认证，Headplane 再用长期 API Key 访问 Headscale。OIDC 回调
后，Headplane 会拉取 Headscale 用户列表，按 OIDC `sub` 建立关联，使两侧指向同
一个身份。

以下四处取值必须逐字一致，否则会出现跳转循环或 `invalid_client`：

| 配置项         | 位置                                                                                                  |
| -------------- | ----------------------------------------------------------------------------------------------------- |
| Issuer         | `dex/config.yaml` 的 `issuer`、`config.yaml` 的 `oidc.issuer`、`headscale/config.yaml` 的 `oidc.issuer` |
| 面板回调地址   | `dex/config.yaml` 的 `headplane-client.redirectURIs`，由 `server.base_url` + `/admin/oidc/callback` 拼出 |
| 控制面回调地址 | `dex/config.yaml` 的 `headscale-client.redirectURIs`，由 `oidc.public_base_url` + `/oidc/callback` 拼出 |
| Cookie 安全标记 | 入口为纯 HTTP 时必须 `server.cookie_secure: false`                                                      |

经过反向代理时，`X-Forwarded-Proto`、`X-Forwarded-Host`、`X-Forwarded-Port`
必须反映浏览器看到的源站；`compose.yaml` 已在 Headplane 路由上设置。

### 配置与密钥

入库的只有描述性配置，凭据一律不入库。

| 文件                           | 是否入库 | 内容                                          |
| ------------------------------ | -------- | --------------------------------------------- |
| `compose.yaml`                 | 是       | 服务、路由、挂载                              |
| `config.yaml`                  | 是       | Headplane 配置，通过 `/run/secrets/*` 取值     |
| `headscale/config.yaml`        | 是       | Headscale 配置，通过 `/run/secrets/*` 取值     |
| `dex/config.yaml`              | 是       | Dex 客户端与用户，仅引用环境变量名             |
| `.env.example`                 | 是       | Dex 密钥与密码哈希的变量名                     |
| `scripts/bootstrap-secrets.sh` | 是       | 生成本地密钥文件                              |
| `.env`                         | 否       | Dex 客户端密钥与 bcrypt 哈希                   |
| `secrets/`                     | 否       | Cookie 签名密钥、Headscale API Key、OIDC 密钥  |
| `dex-data/`、`headplane-data/` | 否       | SQLite 数据库                                 |
| `traefik/users.htpasswd`       | 否       | Basic Auth 文件（`users.htpasswd.example` 入库）|

Headplane 与 Headscale 通过 `*_path` 选项读取密钥文件，Dex 通过 `secretEnv` 与
`hashFromEnv` 读取环境变量。任何敏感值都不应写入入库文件。

### 日常运维

```sh
docker compose ps                     # 状态与健康
docker compose logs -f headplane      # 跟踪单个服务日志
docker compose restart headplane      # 重启单个服务
docker compose pull && docker compose up -d   # 更新镜像

docker exec headscale headscale users list
docker exec headscale headscale nodes list
docker exec headscale headscale apikeys create
```

健康检查：

```sh
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8082/.well-known/openid-configuration
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8082/admin/login
docker inspect headplane --format '{{.State.Health.Status}}'
```

需要备份 `dex-data/`、`headplane-data/`、`.cache/headscale/` 与 `secrets/`。
轮换密钥时，写入新值（文件或 `.env`）后重建相关服务；`cookie_secret` 变化会让
现有会话全部失效。

### 故障排查

| 现象                                          | 原因                                                       | 处理                                              |
| --------------------------------------------- | ---------------------------------------------------------- | ------------------------------------------------- |
| Headplane `unhealthy`、健康检查返回 500        | 启动时 Headscale 或 Dex 不可达，健康检查依赖 Headscale      | 先修好 Headscale / Dex，再看 `docker logs headplane` |
| `cannot specify static passwords without enabling password db` | Dex 使用 `staticPasswords` 时必须开启密码库 | 在 `dex/config.yaml` 设置 `enablePasswordDB: true` |
| Headscale 反复崩溃，报 `dial tcp [::1]:8082`  | Issuer 用了 `localhost`，容器内无法回连宿主机              | 三份配置统一改为共享主机名 `dex.local`             |
| 登录后反复跳回 `/login`                        | `base_url`、issuer、回调地址或 `cookie_secure` 不一致       | 按上文四行逐项核对                                |
| 换取令牌时报 `invalid_client`                  | `.env` 中的客户端密钥与 `secrets/` 不一致                   | 改为一致后重建 Dex 与 Headplane                   |
| 发现文档返回 404                              | Traefik 路由优先级被改乱                                    | 优先级应为 Headplane 200、Dex 150、Headscale 100  |
| `nginx-auth` 持续重启                          | 可选边车使用了占位配置                                      | 已设为 `restart: "no"`，需要时再显式启用           |

### 与上游同步

```sh
git fetch upstream
git merge upstream/main
```

`origin` 指向本仓库，`upstream` 指向 `tale/headplane`。

## 文档

安装与配置细节见[官方网站](https://headplane.net)。本仓库特有的部署说明见本文件
以及生成的《headplane运维及操作手册.html》。

## 版本管理

Headplane 自 v0.6.0 起采用[语义化版本](https://semver.org/)。预发布构建位于
`next` 标签，在发布 PR 进入测试阶段时更新。

## 参与贡献

欢迎提交建议、缺陷报告与功能请求，请先开 issue，并参阅
[贡献指南](./.github/CONTRIBUTING.md)。

---

<picture>
    <source
        media="(prefers-color-scheme: dark)"
        srcset="./docs/assets/acls-dark.png"
    >
    <source
        media="(prefers-color-scheme: light)"
        srcset="./docs/assets/acls-light.png"
    >
    <img
        alt="ACL 配置"
        src="./docs/assets/acls-dark.png"
    >
</picture>

<picture>
    <source
        media="(prefers-color-scheme: dark)"
        srcset="./docs/assets/machine-dark.png"
    >
    <source
        media="(prefers-color-scheme: light)"
        srcset="./docs/assets/machine-light.png"
    >
    <img
        alt="节点管理"
        src="./docs/assets/machine-dark.png"
    >
</picture>

> Copyright (c) 2025 Aarnav Tale
