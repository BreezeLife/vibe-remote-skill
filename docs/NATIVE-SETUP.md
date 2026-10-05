# 使用自研 Vibe Remote

这是我们自己的 macOS 开发预览版，直接通过蓝牙读取小米遥控器的 ATVV 音频。
不需要安装 MiRemote、SayAll、BlackHole 或其他桥接应用。首版使用 Apple 语音识别，
豆包 / Typeless 的虚拟麦克风以及通用遥控器按键映射尚未实现。

## 安装包

`.pkg` 安装到当前用户的 `~/Applications/Vibe Remote.app`，无需管理员权限。
先复制需要保留的草稿并退出应用，再双击安装包按提示安装；安装器要求关闭运行中的
Vibe Remote。安装后从上述目录打开应用，保持只运行一份。

本次生成的是 **0.1.1 / Apple Silicon（arm64）/ macOS 13+** 开发包。
应用使用本地 ad-hoc 签名，安装包尚未 Developer ID 签名或 Apple 公证。
安装不自动授予蓝牙或语音识别权限，也不安装其他桥接程序或驱动。

开发者可在仓库根目录生成当前机器架构的安装包和 SHA-256 文件：

```sh
bash scripts/package_macos_app.sh
```

默认输出到 `build/packages/`。可用 `VIBE_PACKAGE_OUTPUT_DIR` 指定其他目录，例如：

```sh
VIBE_PACKAGE_OUTPUT_DIR="$HOME/Downloads" bash scripts/package_macos_app.sh
installer -pkg "$HOME/Downloads/VibeRemote-0.1.1-arm64.pkg" -target CurrentUserHomeDirectory
open "$HOME/Applications/Vibe Remote.app"
```

重建时若同名包或校验文件已存在，脚本会拒绝覆盖；选择新的输出目录即可。
打包先在本地临时目录构建，再校验唯一安装域及解包后的签名。安装器禁止重定位到
历史工作目录副本，拒绝覆盖不同 Bundle ID，并检查已有应用版本，避免降级。
用户域、退出要求与最低系统版本采用 [Apple Installer Distribution 配置](https://developer.apple.com/library/archive/documentation/DeveloperTools/Reference/DistributionDefinitionRef/Chapters/Distribution_XML_Ref.html)。

## 从源码构建与打开

需要 macOS 13+ 和 Xcode Command Line Tools；在仓库根目录执行：

```sh
bash scripts/test_macos_core.sh
bash scripts/test_macos_speech.sh
bash scripts/test_macos_model.sh
bash scripts/build_macos_app.sh
open "$HOME/Applications/Vibe Remote.app"
```

脚本将本机架构的 `.app` 构建到 `~/Applications/Vibe Remote.app`，使用本地 ad-hoc 签名，
尚未 Developer ID 签名或公证。构建器只更新带有自身构建标记的产物；已有其他同名应用
会被保留并报错。可用 `VIBE_OUTPUT_DIR` 指定输出目录，请选择不受 iCloud 同步的位置。
iCloud / File Provider 会在签名后重新附加 Finder 元数据，因此不应在同步目录运行 `.app`。
构建不安装驱动、不修改系统音频设备、不申请辅助功能权限。为保证隐私权限关联稳定，
请从同一目录启动同一份 app，更新前复制需要保留的草稿并退出所有旧版；
重编译后 macOS 可能需要重新授权。不要直接 `swift run`
来做权限验收，完整 app bundle 才包含用途说明和稳定的 bundle ID。

## 第一次使用

1. 在 macOS 蓝牙设置中配对并唤醒小米蓝牙语音遥控器 2 Pro。若其他遥控器桥接应用
   正在运行，先退出它，以免争用连接。
2. 打开 **Vibe Remote**，点击 **连接遥控器**，允许系统蓝牙授权。等待界面显示
   ATVV 协议就绪；仅“连接中”或系统已配对不代表音频可用。
3. 点击 **启用语音识别**，在系统提示中允许。已授权时显示 **语音识别已授权**，
   应用每次开始收音时重新查询实际权限。默认识别语言是普通话，且要求本机识别。
4. 按住遥控器语音键说话，观察音量条、音频时长和草稿。松开后等待“草稿已保留”。
5. 审阅并编辑文字，再点击 **复制草稿**。到目标 AI 输入框粘贴，确认目标后自行发送。

本机不支持所选语言离线识别时，应用会提示且保留已有草稿。你可以更换语言，或显式勾选
**允许 Apple 在线识别** 后重试；在线模式允许音频交给 Apple 语音服务。应用不保存录音
或转写历史，草稿只在内存中，退出前请复制需要保留的文字。

## 操作边界

- 松开语音键会结束音频，等待最终识别；不会向任何应用自动发送。
- 一段听写完成后，下一段追加到已有草稿。取消只撤销当前这段，保留此前文字。
- 正常松开语音键可继续下一次听写；手动点击取消/结束后，本版会断开连接，以避免
  同一次长按的重复事件重新启动录音。再次点击连接后继续。
- 0.1.1 起，权限或识别失败会在连接区域显示具体原因，继续显示收到的音频时长与音量，
  保留蓝牙连接。此时标注「收音中 · 未转写」；松开语音键后处理提示，再按住重试。
  同一次按住期间不会自动重启识别，也不会自动切换为在线识别。
- 收音或等待识别期间，编辑和复制暂时停用，避免后续结果覆盖手工修改。
- 断连会结束收音；如果没有最终结果，会保留收到的部分文字并提示。可检查后手动修订。
- 本版只消费 ATVV 语音控制。其他遥控器按键没有由本应用接管，仍可能触发 macOS 默认行为。
- 本版没有工作区自动切换、粘贴或发送动作，也不暴露豆包可选择的虚拟麦克风。

## 排障与验收

连接不到：检查系统蓝牙、唤醒遥控器、断开后重连。本应用先检索已连接的 ATVV/HID
候选，再扫描广告；只有确认遥控器协议才会进入就绪状态。不要仅依据之前的连接记录。

没有文字：先看音量与收到的音频时长，再看语音授权/语言支持。若只有音频没有转写，
这代表音频链路与识别链路的状态不同，不能据此认定蓝牙无效。权限被拒绝后，去
系统设置 → 隐私与安全性 → 蓝牙 / 语音识别允许 Vibe Remote，再重试或重开 app。

一按语音键就显示「已手动停止」：0.1.0 会把识别启动失败误当作手动停止，主动断连。
请更新到窗口右上角标明 **0.1.1** 的版本，并确保只有一份 Vibe Remote 在运行。
新版会展示识别错误，便于区分权限、语言支持和音频问题。主动点击取消/结束仍需重连；
连续 8 秒未收到有效音频或单段达到 90 秒也会停止，但会明确显示超时原因。

实机验收至少覆盖：连续两次按住/松开、取消并保留旧草稿、收音时断连、显式复制、
离线模式不支持时提示、在线模式只在勾选后启用。软件测试结果与实机进度见 [TASKS](../TASKS.md)。

开发测试：本机仅装 Command Line Tools 时使用上述测试脚本；完整 Xcode 环境也可运行
`swift test --package-path apps/macos --disable-sandbox`，两种方式执行同一组核心测试。
`test_macos_model.sh` 使用 fake 服务运行真实模型的按键、权限、识别失败和草稿回归，
不创建真实蓝牙连接或识别器，不弹系统授权，不接触剪贴板。
