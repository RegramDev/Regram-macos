# 钱包显式生物识别确认回归

```sh
python3 tools/tests/wallet-biometric-confirmation/run.py
```

运行器从当前 `WalletUIIntegration.swift` 提取完整的生物识别回调，从 `WalletAuthorizeController.swift` 提取验证结果枚举，在 Release/STABLE 下执行 6 个用例。输入源码摘要保存在输出目录的 `manifest.json`。

用例覆盖关闭生物识别、确认前不读取凭据、禁止复用旧验证、成功后替换并失效旧会话、拒绝或凭据失败时保留原会话、上下文释放以及主线程单次回调。使用真实 SwiftSignalKit Atomic 和 Queue；LocalAuthentication 提示与钥匙串由隔离替身接收调用，不访问任何钱包或账号数据。
