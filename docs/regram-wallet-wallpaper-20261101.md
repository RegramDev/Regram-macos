# 2026-11-01 钱包验证更新与聊天壁纸缩放修复

在 `fb81a8c8` 的双架构发布准备上，合入上游 `55830942ca3976462407dc92bfe1faad9ed68dda`。本次 283393 发布累计同步 18 项上游更新。

## 钱包确认

上游在读取受保护的钱包凭据前显式执行生物识别策略，并将允许复用验证的时长设为零。成功时使用同一个 LAContext 读取凭据，替换并失效旧会话；取消、拒绝或凭据读取失败时保留原会话，清理 LAContext，并在主线程返回结果。Regram 的钱包命名空间和钥匙串隔离保持原样。

`tools/tests/wallet-biometric-confirmation/run.py` 提取当前生产回调和结果枚举，使用真实 SwiftSignalKit Queue 与 Atomic。6 项 Release/STABLE 回归通过，覆盖确认顺序、禁止复用、成功、拒绝、凭据失败及后台返回。LocalAuthentication 和钥匙串使用隔离替身，不读取真实钱包。

## 聊天照片壁纸

原有应用路径先按固定的 1040:1580 竖向比例裁剪图片，再由聊天窗口等比铺满。例如 1600×900 横图先只保留中间约 592×900 区域，宽聊天窗口随后再放大这一部分，造成明显二次放大。

现在应用照片时保留完整原图，按原始比例限制缓存尺寸，不放大小图；保存到资源和媒体描述中的尺寸取自实际输出图片。同时移除普通照片在绘制时强制使用至少 500 点高度的逻辑，短窗口按真实大小铺满。图案壁纸继续使用既有的最小高度及平铺行为。

照片继续等比铺满窗口，因此窗口与图片比例不同时仍会裁去窗口外的部分。旧版本已经裁剪并保存的壁纸不包含丢失的边缘，需要重新选择原图一次。

实际 WallpaperUI 模块的 4 项像素回归检查横图、竖图、方图和小图的输出尺寸及左／中／右内容，全部通过。实际 BackgroundView 的 5 项布局回归检查短窗口、1×／2× 图像、宽图、竖图、窗口缩放和图案兼容，全部通过。原有图片降采样 4 项及提示气泡 3 项也通过。

完整富文本编辑器 689 项、共享核心 538 项和音乐加载 51 项再次通过，均使用 Release/STABLE。

壁纸原生回归命令：

```sh
python3 tools/tests/regram-chat-regressions/run.py --package WallpaperUI --filter WallpaperImageFramingTests
python3 tools/tests/regram-chat-regressions/run.py --package TGUIKit --scratch-path packages/TGUIKit/.build --filter 'WallpaperBackgroundLayoutTests|ImageDownsamplingTests|TooltipGeometryTests'
```

首次布局测试只遍历根图层，未找到 AppKit 尚未挂入根图层树的子视图图层。测试改为遍历实际视图和各自图层并按身份去重后全部通过，没有为了测试暴露生产内部字段。

证据目录为 `/tmp/regram-upstream-8ae5b3a3-20261101`，最终发布记录在 `/Users/yuki/Downloads/Regram/v13.1.0-283393/verification`。本次修复前后原有父仓库 31 个本地文件、核心子模块 77 个本地文件摘要保持一致。
