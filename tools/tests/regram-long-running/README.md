# 长时间运行的任务生命周期回归

运行：

```sh
python3 tools/tests/regram-long-running/run.py
python3 tools/tests/regram-long-running/run.py --expect-old-behavior --output /tmp/regram-long-running-before-20261029
```

测试使用仓库当前 SwiftSignalKit 源码，在临时 SwiftPM 工程以 Release/STABLE 运行，不操作已登录账号。默认产物在 `/tmp/regram-long-running-20261029`；`manifest.json` 记录参与检查的生产源码指纹。

覆盖内容：

- 首次准备和前台历史按原顺序交付；隐藏时连续 5,000 次历史更新只保留最新快照，重新显示时恢复；隐藏之前排队的旧世代更新不能恢复耗时渲染。
- 隐藏页面的展示状态变化不触发历史条目构建，独立对话互不阻塞，取消订阅后丢弃已排队更新。
- 历史渲染订阅不会强持有已移出的控制器所有者；释放所有者后取消订阅，不再收到后续消息。
- 隐藏聊天列表不启动 Story 预加载；已有订阅及资源在隐藏时取消；取消前已排到主线程的旧资源结果不能重新启动预加载。
- 远端预览分页的 50 毫秒续页任务在取消或被替代后不启动新网络请求，不结束同一个来源键的新请求；正常分页仍完成。
- 隐藏时取消滚动后延迟工作；快速返回页面也不能让旧工作恢复执行。

`ChatHistoryRenderGate.swift` 和 `ChatListVisibleStoryResources.swift` 完整复制自生产源码。分页测试直接提取 `isCurrentRemoteRequest` 和 `loadRemotePage`，替换账号、消息和网络边界，保留实际 Signal、MetaDisposable、串行队列、超时与续页定时器。历史测试重现控制器的队列、世代检查和生命周期顺序；释放测试从生产闭包提取捕获方式与 currentRanks 回写，在受控所有者中检查订阅持有关系；滚动测试用受控 DispatchWorkItem 检查相同取消规则。脚本还检查控制器接入点，完整 AppKit 控制器由应用 Release 构建验证。

负对照只在临时测试源码恢复旧策略：隐藏历史仍逐条交付、渲染闭包强捕获所有者、Story 只检查偏好、分页只检查来源键、滚动工作不检查可见性也不在隐藏时取消。11 项针对性测试必须全部失败，脚本才判定负对照有效。它不代表构建或运行完整旧版应用。

这些测试证明指定路径的取消、顺序和排队边界，不测量真实账号长时间运行的 CPU、内存或切换耗时，也不覆盖所有账户同步任务。
