# AILearningOS 服务端与 Cloudflare Tunnel 部署手册 (Windows 11)

本手册专为无公网 IP 的 Windows 11 物理机设计，通过 Cloudflare Tunnel 实现内网穿透，并将后端的 API 服务暴露给手机端使用。

## 第一阶段：启动后端 API 服务

目前我们的服务端是一个 Dart Shelf 应用。为了让它在后台稳定运行，建议将其编译为可执行文件（`.exe`）。

### 1. 编译服务端程序
打开 **PowerShell**，进入项目后端的目录：
```powershell
cd C:\Users\GeorgeGao\Documents\ChatGPT\AI-自学OS\server
dart compile exe bin/server.dart -o ai_os_server.exe
```

### 2. 运行服务端
双击运行生成的 `ai_os_server.exe`，或者在 PowerShell 中运行：
```powershell
.\ai_os_server.exe
```
> **提示**：控制台应输出 `Server listening on port 8080`，此时请**保持该窗口打开**（后续可配置为 Windows 开机自启服务，目前先手动保持运行用于测试）。

---

## 第二阶段：配置 Cloudflare Tunnel (cloudflared)

### 1. 准备工作
确保你的 `cloudflared.exe` 放置在 `C:\cloudflared\` 目录下。
**⚠️ 注意：必须以“管理员身份”运行 PowerShell 进行以下操作。**

打开 **管理员 PowerShell**，进入目录：
```powershell
cd C:\cloudflared\
```

### 2. 登录 Cloudflare 账号
```powershell
.\cloudflared.exe tunnel login
```
* 执行后会自动打开浏览器，请选择包含 `georgehan0514.top` 的域名并授权。
* 授权成功后，会在 `C:\Users\GeorgeGao\.cloudflared\` 生成一个证书文件 `cert.pem`。

### 3. 创建隧道 (Tunnel)
我们给隧道起个名字，比如 `ai-os-tunnel`：
```powershell
.\cloudflared.exe tunnel create ai-os-tunnel
```
* 成功后，终端会输出一串 **UUID**（格式类似于 `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`），以及一个 `.json` 凭据文件的路径。
* **请把这个 UUID 复制记录下来，下一步会用到。**

### 4. 绑定 API 域名 (DNS 路由)
将你的子域名 `api.georgehan0514.top` 绑定到刚才创建的隧道：
```powershell
.\cloudflared.exe tunnel route dns ai-os-tunnel api.georgehan0514.top
```

### 5. 编写配置文件 (config.yml)
在 `C:\cloudflared\` 目录下，新建一个文本文件，命名为 `config.yml`，填入以下内容（**注意替换其中的 `<你的隧道UUID>` 为刚才记录的 UUID**）：

```yaml
tunnel: <你的隧道UUID>
credentials-file: C:\Users\GeorgeGao\.cloudflared\<你的隧道UUID>.json

ingress:
  # 将域名请求转发到本地的 8080 端口 (Dart 服务端)
  - hostname: api.georgehan0514.top
    service: http://localhost:8080
  
  # 兜底规则，所有不匹配的请求返回 404
  - service: http_status:404
```

### 6. 测试运行隧道
```powershell
.\cloudflared.exe tunnel --config C:\cloudflared\config.yml run
```
* 如果控制台输出 `Registered tunnel connection`，且没有报 `ERR` 级别的错误，说明隧道已经成功连通。

---

## 第三阶段：验证与注册为系统服务

### 1. 手机端/外网验证
在保持 `ai_os_server.exe` 和 `cloudflared` 都在运行的情况下，关闭手机的 Wi-Fi（使用 5G/4G 流量），在手机浏览器中访问：
👉 `https://api.georgehan0514.top/health`
* 如果页面显示 `OK`，恭喜你，内外网彻底打通！

### 2. 注册为 Windows 系统服务 (可选，强烈推荐)
为了避免每次重启电脑都要手动敲命令，我们可以把 Cloudflare 隧道注册为 Windows 的后台服务。

在刚才的 **管理员 PowerShell** 中，先按 `Ctrl + C` 停止正在运行的隧道，然后执行：
```powershell
.\cloudflared.exe service install
```
修改注册表的启动参数（指向你的 config.yml）：
1. 按 `Win + R` 输入 `regedit` 打开注册表。
2. 导航到：`HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Cloudflared`
3. 找到 `ImagePath`，将其修改为：
   `C:\cloudflared\cloudflared.exe --config C:\cloudflared\config.yml tunnel run`
4. 打开 Windows 的“服务”管理器 (`services.msc`)，找到 `Cloudflared agent`，右键点击“启动”。

至此，只要你的 Windows 物理机开机，API 服务就能在外网被手机正常访问了！
