## 这是用来提取 B 站直播间弹幕等信息的 Godot 插件。

## 插件安装：
- 克隆/下载本仓库文件
- 复制本仓库文件夹到你的项目目录的 addons 文件夹下

## 简要说明：
BiliveAPI 管理 HTTP 的 API 请求，包括获取直播间真实 ID、用户信息、用户头像等。
BiliveClient 管理 WebSocket 客户端，处理直播服务器的广播消息。
BiliveObserver 使用以上两个节点完成直播间信息的获取、解析，并发送相应的信号。

> 也可以不使用 BiliveObserver 节点，直接通过 BiliveAPI 和 BiliveClient 实现你自己的直播弹幕处理逻辑。  
> live_api.json 存储了一部分用户信息和直播信息的 API。我这里只用到了获取直播间信息和获取用户信息和头像的 API。
