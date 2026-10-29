# 聊天列表滚动后的轻量任务

```sh
python3 tools/tests/regram-list-scroll/run.py
python3 tools/tests/regram-list-scroll/run.py --expect-immediate --output /tmp/regram-list-scroll-before-20261029
```

以真实 SwiftSignalKit 和生产 `ChatListScrollUpdates.swift` 在 Release/STABLE 运行 8 项回归。验证 500 次连续可见行变化只在停稳后处理最新视口、隐藏和销毁取消待处理任务、返回页面恢复、连续两轮滚动各刷新一次，以及重复可见性通知不重复启动任务。

负对照只在临时源码恢复立即刷新策略，4 项指定反例必须全部失败。它不运行完整旧客户端。

文件在 `/tmp/regram-list-scroll-20261029`，包括日志和源码指纹。这是任务调度回归，不是实际账号的帧率测量。
