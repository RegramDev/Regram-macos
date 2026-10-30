# 长期运行的任务与对象释放回归

在仓库根目录执行，使用优化编译与 STABLE。信号库产物可先用 RegramCore 或 RegramServices 的 Release 测试生成。

```sh
swift test --package-path packages/RegramServices -c release -Xswiftc -DSTABLE --jobs 2
python3 tools/tests/regram-endurance/run-limiter.py --cycles 1000
python3 tools/tests/regram-endurance/run-transcription.py --cycles 2000
python3 tools/tests/regram-long-running/run.py
```

`run-limiter.py` 直接提取完整生产请求限制器，链接实际 SwiftSignalKit。保持三个请求在运行，分批创建和取消等待请求；每批结束队列必须归零。随后验证并发上限、先入先出、运行中取消、提供方失败、同步完成和恢复接收新请求。反射仅用于读取私有队列与计数。1000 轮为 100000 个取消请求，并非 1000 小时的实机测试。

`run-transcription.py` 提取生产语音识别入口、任务管理器、任务键、令牌与错误类型，链接实际 SwiftSignalKit。消息、账号、数据库与识别是内存夹具。每次读取不存在的消息后，历史仍可重试，但原始消息对象必须释放；最后提供当前消息，确认重试重新读取数据库并完成。设置也是纯内存替身，不触碰真实偏好域。它检查相同闭包的持有关系，不是完整 Postbox 消息的内存占用测量。

两种运行器将生产输入哈希、生成源码、编译日志与结果写入输出目录。可用 `--source` 指向保存的修复前文件；负对照必须先编译成功，再因对应断言失败。`--products` 可指定另一套实际 SwiftSignalKit Release 产物。

RegramServices 的 `RegramTaskRetentionTests` 验证 400 个受控并发任务完成或失败后，不依赖下次请求就执行历史清退，并验证清退时释放捕获对象、保留运行任务及最新重试。另一项执行 500 轮双账号休眠、恢复、取消、成功／失败、旧回调与账号清退，总共启动 2000 个受控请求；每轮结束工作数归零且负载对象释放。

所有夹具均不发送聊天消息，不读取真实账号、凭据或聊天数据，不调用真实翻译、识别服务。测试中的清退仅针对内存任务管理器。

## 实机只读趋势

```sh
python3 tools/regram-endurance-monitor.py --samples 30 --interval 60
```

读取已运行的 `/Applications/Regram.app` 的进程资源计数；未运行时只记录，不启动应用。包括 physical footprint、驻留内存、线程、累计 CPU 原始计数、唤醒、换页与磁盘累计量，以及系统内存压力和交换空间。CPU 计数没有转换为百分比。进程路径、启动标识与可执行文件 UUID 用于分段，不能把重启后的下降当成泄漏修复证据。

默认输出为 `~/Library/Logs/RegramPerformance/endurance/metrics.jsonl`，最多保留 2048 条记录，每次原子替换，文件锁避免重叠采集。单次最多 60 个样本、间隔最多 60 秒，进程结束后不留下常驻采集服务。工具不读取账号内容，不操作界面，不变更设置。

内存单次上升或线程瞬时增加不能直接判为泄漏。应结合相同进程、相近使用场景、缓存回落、系统压力和对象释放回归判读；这里没有有效实屏 FPS，也不把快速循环称为全天使用验收。
