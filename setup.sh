#!/usr/bin/env bash
# CS:APP 一键部署脚本。在克隆下来的仓库根目录执行： ./setup.sh
# 自动完成：装 Docker、配镜像加速器、设密码、构建启动。
# 详见 DEPLOY.md。
set -eu

cd "$(dirname "$0")"

echo "==> CS:APP 一键部署"

# 选择 docker 命令前缀（当前用户不在 docker 组则用 sudo）
if docker info >/dev/null 2>&1; then
  DOCKER="docker"
else
  DOCKER="sudo docker"
fi

# 1. 安装 Docker
if ! command -v docker >/dev/null 2>&1; then
  echo "==> 未检测到 Docker，正在安装..."
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER" || true
  DOCKER="sudo docker"
  echo "   Docker 已安装。（重新登录一次后可免 sudo 使用 docker）"
fi

# 2. 配置镜像加速器（大陆必需）
if [ ! -f /etc/docker/daemon.json ]; then
  echo "==> 未配置 Docker 镜像加速器。"
  echo "    阿里云用户可在 https://cr.console.aliyun.com/ →镜像加速器 获取专属地址。"
  read -rp "    输入加速器地址(https://xxx.mirror.aliyuncs.com，回车跳过): " MIRROR
  if [ -n "${MIRROR:-}" ]; then
    sudo mkdir -p /etc/docker
    sudo tee /etc/docker/daemon.json >/dev/null <<EOF
{
  "registry-mirrors": [
    "$MIRROR",
    "https://docker.m.daocloud.io",
    "https://dockerproxy.net"
  ]
}
EOF
    sudo systemctl daemon-reload
    sudo systemctl restart docker
    echo "   镜像加速器已配置。"
  fi
fi

# 3. 设置登录密码 -> .env
if [ ! -f .env ]; then
  read -rsp "==> 设置 code-server 登录密码(回车则自动生成随机密码): " PW; echo
  if [ -z "${PW:-}" ]; then
    PW="$(openssl rand -hex 8)"
    echo "   已生成随机密码: $PW"
  fi
  echo "CSAPP_PASSWORD=$PW" > .env
  echo "   已写入 .env"
fi

# 4. 构建并启动
echo "==> 构建并启动容器（首次较慢，请耐心等待）..."
$DOCKER compose up -d --build

# 5. 收尾提示
IP="$(curl -s --max-time 5 ifconfig.me || echo '<你的公网IP>')"
cat <<EOF

======================================================
部署完成 ✅

访问地址:  https://$IP:7777      （注意是 https）
登录密码:  见 .env 文件

还需手动完成：
  * 阿里云安全组放行入站 TCP 7777
  * 浏览器首次访问点「高级 → 继续前往」（自签证书，正常现象）

常用命令：
  $DOCKER compose logs -f csapp     查看日志
  $DOCKER compose restart           重启
======================================================
EOF
