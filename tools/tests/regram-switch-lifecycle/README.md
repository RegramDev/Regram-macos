# 切换请求、列表准备队列与链接预览生命周期

在 macOS 上从仓库根目录运行：

```sh
python3 tools/tests/regram-switch-lifecycle/run.py
python3 tools/tests/regram-switch-lifecycle/run.py --expect-shared-queue
python3 tools/tests/regram-switch-lifecycle/run.py --expect-menu-overflow
```

默认检查提取当前生产 `ChatNavigationRequest`、`LinkHoverPreview`、聊天列表队列工厂及全局资源队列声明，并使用真实 SwiftSignalKit 和 TGUIKit 编译独立 Release/STABLE XCTest 包。还执行生产 `AppMenu.close`、导航待加载控制器取消、菜单定位及上游异步菜单回归，共 33 项。10 项定位测试中包含 864 组尺寸、边缘、显示器坐标和窗口约束组合，均直接调用生产定位函数。

检查覆盖过期查询取消、晚到订阅拒绝、重入取消、导航作用域隔离、阻塞资源队列时前台列表继续处理、不同列表互不阻塞、待加载控制器释放、只关闭所属菜单、晚到预览拒绝、源视图移除和窗口失活。生产列表管线、预览协调器和导航入口的调用位置另外校验，源码指纹写入输出目录的 `manifest.json`。

`--expect-shared-queue` 只在隔离夹具中恢复原来的共享资源队列。两项阻塞检查必须失败，脚本才返回成功；日志保存在 `tests-shared-queue.log`，不会覆盖正常运行的 `tests.log`。这证明检查能够识别队列共用造成的等待，不是实际用户操作延迟的基准。

`--expect-menu-overflow` 只在复制到临时目录的 TGUIKit 中恢复原有顶部定位错误，即把菜单底边放到可用区域的顶边。顶部点击检查必须出现断言失败，编译失败不算有效反例；日志为 `tests-menu-overflow.log`，生产源码不变。

夹具仅创建自身进程内的原生窗口，不操作正在运行的 Regram，不读取账号、聊天、偏好或凭据，也不请求网络。导航引擎查询和真实聊天列表行的完整生成链不在该夹具内；仍需完整 Release 构建以及长期使用反馈。
