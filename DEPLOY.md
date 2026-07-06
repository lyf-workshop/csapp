# CS:APP 云服务器部署指南

在云服务器上跑 code-server（网页版 VS Code），任何设备用浏览器就能做 CS:APP 实验。

## 最终架构

```
任何设备浏览器  ──https://<公网IP>:7777 (自签证书, 加密)──▶  code-server 容器
                                                              (labs 挂在 /home/csapp/project)
```

- 直连公网 IP + 7777 端口，自签证书走 HTTPS（首次访问点一次"继续前往"）。
- 不用域名、不用备案、不用 nginx/Caddy 反代、不用 Let's Encrypt。
- 为什么是这套方案（踩坑记录）见文末「设计说明」。

---

## 一、前提

- 一台 Linux 云服务器（本文以**阿里云大陆 ECS** 为例，其它厂商同理）。
- 有公网 IP，能 SSH 登录。
- 一个 GitHub 账号（用来 clone 你自己的 fork）。

---

## 二、部署步骤

### 1. 安装 Docker

```bash
docker --version || curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER      # 免 sudo 用 docker，需重新登录一次生效
```

> 退出并重新 SSH 登录，让 docker 用户组生效。

### 2. 配置 Docker 镜像加速器（大陆必需，否则拉不动镜像）

阿里云用户：登录 https://cr.console.aliyun.com/ →「镜像工具 → 镜像加速器」拿到你的专属地址
（形如 `https://xxxxxx.mirror.aliyuncs.com`），填到下面第一行：

```bash
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json >/dev/null <<'EOF'
{
  "registry-mirrors": [
    "https://你的ID.mirror.aliyuncs.com",
    "https://docker.m.daocloud.io",
    "https://dockerproxy.net"
  ]
}
EOF
sudo systemctl daemon-reload
sudo systemctl restart docker

docker info | grep -A3 "Registry Mirrors"   # 确认生效
```

### 3. 拉取仓库

```bash
git clone https://github.com/lyf-workshop/csapp.git
cd csapp
```

### 4. 设置登录密码

```bash
cp .env.example .env
nano .env          # 把 CSAPP_PASSWORD 改成一个足够强的密码
```

> `.env` 已被 `.gitignore` 排除，不会进 git，安全。

### 5. 阿里云安全组放行端口

控制台 → 安全组 → 添加**入站规则：TCP 7777**，来源 `0.0.0.0/0`
（想更安全就只填你常用网络的公网 IP 段）。

### 6. 构建并启动

```bash
docker compose up -d --build          # 首次构建较慢（拉基础镜像 + 装扩展），耐心等
docker compose logs --tail=15 csapp
```

看到这两行即成功：

```
HTTPS server listening on https://0.0.0.0:7777/
- Using certificate for HTTPS: .../localhost.crt
```

本地自测（`-k` 忽略自签证书，返回 302 即正常）：

```bash
curl -k -I https://127.0.0.1:7777
```

### 7. 浏览器访问

打开 **`https://<你的公网IP>:7777`**（注意是 **https**）：

1. 弹"连接不是私密"→「高级」→「继续前往」（自签证书，正常现象，点一次即可）。
2. 输入 `.env` 里的密码。
3. 进入网页版 VS Code，`/home/csapp/project` 就是仓库里的 `labs`。

每台新设备重复"过一次证书警告 + 输密码"即可。

---

## 三、日常维护

| 操作 | 命令 |
|------|------|
| 查看日志 | `docker compose logs -f csapp` |
| 重启 | `docker compose restart` |
| 停止 | `docker compose down` |
| 更新配置后重启 | `git pull && docker compose up -d` |
| 改了 Dockerfile 后重建 | `git pull && docker compose up -d --build` |
| 跟进原作者更新 | `git fetch upstream && git merge upstream/main && git push` |

**数据在哪**：
- 你的实验代码：仓库里的 `labs/` 目录（直接编辑/备份它即可）。
- code-server 设置/扩展/自签证书：Docker 命名卷 `csapp_csapp-userdata`（重启不丢）。

---

## 四、常见问题

**拉镜像超时 `failed to resolve reference docker.io/...`**
→ 镜像加速器没配好，回到步骤 2。

**构建卡在从 github.com 下载 code-server / cpptools**
→ GitHub 代理失效了。在 `.env` 里换一个：`GH_PROXY=https://ghfast.top/`（或 `https://ghproxy.net/`），再 `docker compose up -d --build`。

**浏览器 `ERR_SSL_PROTOCOL_ERROR` / `此网站无法提供安全连接`**
→ code-server 没走 HTTPS。查 `docker compose logs csapp`：应是 `HTTPS server listening`，若是 `HTTP server listening` 说明 `deploy/config.yaml` 没挂进去（确认它存在且 `cert: true`），然后 `docker compose up -d --force-recreate`。

**用 `http://IP:7777` 打不开**
→ 必须用 **https**，code-server 现在只讲 HTTPS。

**端口 7777 连不上**
→ 阿里云安全组没放行 7777（步骤 5），或用了 `http` 而非 `https`。

**`git pull` 报 `local changes would be overwritten`**
→ 服务器上有本地改动挡路。若不需要保留：`git reset --hard origin/main` 再 pull。

---

## 五、设计说明（为什么不用域名 + Let's Encrypt）

这套方案是为**阿里云大陆 + 无自有域名 + 未备案**的场景专门设计的：

- **阿里云拦截未备案域名的 80 端口**：Let's Encrypt 的 HTTP-01 验证要访问 80 端口，会被阿里云边缘改写成 403 → 证书申请必失败。
- 没有自有域名，sslip.io 之类也不受自己控制 → DNS-01 验证同样走不通。
- 阿里云的这个拦截**只针对 80 端口的域名访问**，纯 IP + 非标准端口（7777）不受影响。

所以最省心的选择就是：**非标准端口 + code-server 自签 HTTPS**——加密到位、端口不会被封、无需域名和备案。代价仅是每台设备首次访问点一次证书警告。

> 若将来做了 ICP 备案、或有了自有域名，可改用 Let's Encrypt + nginx 反代获得无警告的正式证书（历史提交里有过对应配置可参考）。
