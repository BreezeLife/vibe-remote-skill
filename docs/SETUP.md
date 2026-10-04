# 上手指南

> 自 2026-10-04 起，项目优先开发自有 macOS 应用。直接使用请先看
> [原生应用指南](NATIVE-SETUP.md)。下文保留原 skill / 外部桥接配置参考，
> 不再作为本项目的默认安装路径。

你需要一只小米蓝牙遥控器 2 Pro、Python 3.10+、可用的语音输入工具，以及接收遥控器音频与按键的桥接软件。以下以 macOS、SayAll 和豆包 / Typeless 为例。

Vibe Remote 提供 Codex 技能、配置模板、按键意图规划器和 tmux 窗口选择器。桥接软件负责硬件事件；技能帮助 Agent 检查环境、配置工作流并验证目标。安装技能后，遥控器不会自动接入 Agent。完整能力边界见 [README](../README.md)。

## 1. 安装技能

将仓库放在你打算长期保留的目录：

```sh
mkdir -p "$HOME/Projects"
git clone https://github.com/BreezeLife/vibe-remote-skill.git "$HOME/Projects/vibe-remote-skill"
cd "$HOME/Projects/vibe-remote-skill"
python3 scripts/install_skill.py
```

安装器在 `${CODEX_HOME:-$HOME/.codex}/skills/vibe-remote` 建立指向仓库的符号链接，不安装驱动、输入法或后台服务。保留仓库目录，移动或删除它会使链接失效。已有同名技能且来源不同，安装器会拒绝覆盖；先确认现有技能的来源与需要保留的修改，再决定如何迁移。

如果 Codex 尚未识别新技能，重新打开会话。自定义技能目录可使用 `python3 scripts/install_skill.py --destination <技能目录>`；后续的 `VIBE_SKILL_DIR` 也要相应调整。

## 2. 检查环境，创建自己的配置

先进入仓库。配置保存在仓库根目录的 `config.local.json`，该文件已被 Git 忽略；helper 始终使用技能的绝对路径：

```sh
cd "$HOME/Projects/vibe-remote-skill"
VIBE_SKILL_DIR="${CODEX_HOME:-$HOME/.codex}/skills/vibe-remote"
VIBE_CONFIG="$PWD/config.local.json"
python3 "$VIBE_SKILL_DIR/scripts/vibe_remote.py" doctor
python3 "$VIBE_SKILL_DIR/scripts/vibe_remote.py" validate "$VIBE_SKILL_DIR/assets/config.default.json"
```

`doctor` 只检查候选应用、驱动文件和命令是否存在。它不证明系统权限、遥控器音频或 APP 操作已经可用。在 macOS 上可额外运行 `doctor --bluetooth` 查看候选设备连接信息；仍需进行实体测试。

用下面的命令复制模板。目标已存在时会保留原文件：

```sh
cp -n "$VIBE_SKILL_DIR/assets/config.default.json" "$VIBE_CONFIG"
python3 "$VIBE_SKILL_DIR/scripts/vibe_remote.py" validate "$VIBE_CONFIG"
```

模板中的工作区都从 `verified: false` 开始。`valid: true` 只表示格式正确，不表示可以发送草稿。这个 JSON 属于 Vibe Remote，不能直接导入 SayAll、MiCoding 或输入法；桥接软件中的设置要单独完成。

## 3. 让 Codex 按技能完成配置

在 Codex 中输入以下任务，并把目标项目 / 会话名称改为你的实际目标：

```text
$vibe-remote
我已有小米蓝牙遥控器 2 Pro。请先检查当前环境，并使用
此仓库根目录的 config.local.json；如果文件存在，不要覆盖。
我先使用 SayAll + 豆包，目标是当前项目的 Codex APP 会话。
请核对已安装应用、真实快捷键和桥接能力，带我完成音频验证、
目标绑定和实体按键验收。只有实际观察后才标记工作区 verified。
缺少依赖或系统权限时，列出官方入口与我需要完成的步骤。
最后报告已配置、已验证和待办，不记录我的语音内容或凭据。
```

使用 Typeless 时，把语音工具改为 Typeless。使用终端时，说明目标终端、项目、AI CLI；使用 tmux 时，再提供真实 session 名称和已有 SSH 别名。不要把示例里的 `cli-mini` 或 `mini` 当成你已经拥有的远程连接。

Agent 能通过当前可用的电脑操作工具观察 APP，并使用 helper 检查配置及切换 tmux 窗口。若没有这些工具，它会提供手动操作步骤。安装驱动、授予 macOS 隐私权限和实体按键操作，需要你按对应软件的流程完成。

## 4. 先打通音频，再设置按键

按 [SayAll 官方说明](https://github.com/HD838A/remote-mic-app#首次使用)安装适合你机器的版本，同时长按遥控器“主页 + 菜单”进入配对，在 macOS 蓝牙设置中连接设备。按用途授予 SayAll 蓝牙、输入监控和辅助功能权限；授权后完全退出并重新打开应用。

在 SayAll“连接与语音”中选择实际存在的 `MiRemoteV 2ch`，语音输入工具也选同一设备。先用 QuickTime“新建音频录制”检查输入电平：远离 Mac 麦克风，对遥控器说话，确认声音来自遥控器。只看到设备名或蓝牙已连接，不能代替这一步。[音频与触发方式说明](https://github.com/HD838A/remote-mic-app#使用语音输入)

| 工具 | 核对本机快捷键 | SayAll“语音键模拟 Fn 点按” | 实体操作 |
| --- | --- | --- | --- |
| 豆包 | Fn 长按 | 关闭 | 按住语音键说话，松开结束并保留草稿 |
| Typeless | Fn 点按开始 / 再点按结束 | 开启 | 仍然按住语音键说话；桥接在开始和音频排空结束时各发一次 Fn 点按 |

Typeless 模式仍需要按住遥控器语音键，松开后硬件停止发送音频。切换语音工具时，要同时调整桥接预设和配置的 `voice_provider`，仅修改 JSON 不会改变 SayAll 的行为。以本机实际快捷键为准。[官方兼容说明](https://github.com/HD838A/remote-mic-app#typeless-兼容)

其他桥接软件可按各自说明接入：[MiCoding](https://github.com/zhangtuansia/MiCoding)提供单独的 Typeless F20 配置，但其 README 仍注明遥控器音频解码参数待校准，听写可能使用 Mac / 耳机 / USB 麦克风；[MiRemoteVoice](https://github.com/VincentKingHsu/MiRemoteVoice)提供另一条音频桥接路径，当前官方入口为源码预览版，安装要求与手势不同。不要将这些方案的按键设置混用。

普通按键在桥接软件内手动配置，每个原始按键只交给一个映射工具。先保留音量行为，配置你已测试的滚动和聚焦动作。能否执行精确任务切换、工作区选择等复合动作，取决于桥接软件实际提供的动作或另行实现的调度器。

## 5. 绑定实际工作区

### Codex / ChatGPT APP

让 Agent 观察实际应用与窗口，再记录项目 / 会话的明确标识和输入框位置。配置中的 `app_bundle_id`、`window_title`、`task_anchor` 都要来自这台机器；APP 显示名称不能替代 Bundle ID。确认屏幕上确实是该目标后，才将绑定标记为已验证。

`task_anchor` 是绑定信息，本身不会驱动 APP。左右切换需要通过当前看到的任务列表或已核对快捷键完成，并在切换后重新确认目标。预览页不会改变 AI 绑定；Home 应返回原 APP、原会话和输入框。任务被改名、关闭或无法区分时，先修复绑定。详细流程见 [APP 适配说明](../skills/vibe-remote/references/app-tasks.md)。

### 原生终端或 tmux

原生终端可以直接绑定现有标签页 / 分屏，不必安装 tmux。每次切换后确认终端、主机、项目和 AI 提示区；终端窗口标题不能证明其中是等待输入的 AI。先测试该 CLI 能保留多行听写草稿，再接入语音；普通 shell 或未知进程必须阻止发送与中断。

tmux 路径需要已安装 tmux、已存在且当前终端已连接的 session。在用户配置中填写真实 `tmux_session`；本地 `host` 为 `null`，远程为已经可用的 SSH 别名。新绑定保持 `verified: false`，观察确认后再启用。helper 不会创建 session、启动 AI、配置 SSH 或连接未附着的客户端。

完成绑定验证后，可运行：

```sh
python3 "$VIBE_SKILL_DIR/scripts/vibe_remote.py" windows "$VIBE_CONFIG" --workspace cli-local
python3 "$VIBE_SKILL_DIR/scripts/vibe_remote.py" switch "$VIBE_CONFIG" --workspace cli-local --direction next
python3 "$VIBE_SKILL_DIR/scripts/vibe_remote.py" switch "$VIBE_CONFIG" --workspace cli-local --direction previous
```

`windows` 给出当前 session 的稳定窗口 ID。需要指定窗口时，用该次实际输出的 ID 执行 `switch … --window <窗口ID>`。选择器精确匹配 session，并在切换后检查活动窗口；到达边界不会循环。它把该 session 的所有窗口纳入范围，建议为编码准备独立 session。返回的 `visible_gui_verified: false` 表示还要确认屏幕显示的客户端就是该 session。[CLI 适配说明](../skills/vibe-remote/references/cli-windows.md)

## 6. 建立最小可用遥控流程

以下是技能约定的意图。桥接软件有对应动作时才进行映射；仅有静态快捷键时，任务感知与状态检查仍需 Agent 或配套调度器。

| 按键 | 意图 |
| --- | --- |
| 语音键按住 / 松开 | 采音 / 完成草稿，松开不发送 |
| OK 单击 | 选择器内确认；AI 输入框内检查草稿后发送一次 |
| 左 / 右 | 上一个 / 下一个已登记任务或窗口 |
| 上 / 下 | 滚动输出；选择器内移动选项 |
| Home | 返回绑定的 AI 输入框 |
| Back 单击 / 长按 | 返回或取消当前听写段 / 停止已确认正在运行的 AI |
| 电源 | 打开工作区选择入口 |
| 菜单单击 / 长按 | 动作入口 / 截取窗口后检查附件 |
| TV 单击 | 打开绑定预览 |
| 音量 | 保留系统音量行为 |

先用一个 APP 工作区验收，再加第二个任务或 CLI 工作区。不要将 OK 全局映射为 Enter、将 Back 长按全局映射为 Ctrl+C；这些快捷键无法自行检查目标和 AI 状态。发送和停止动作都只能执行一次，长按重复只用于滚动和音量。

至少完成以下实体测试，并分别记录通过或待测：

- 确认录音来自遥控器，而非 Mac 麦克风。
- 按住语音键说话，松开后文本仍是未发送草稿；原有草稿得到保留。
- 目标 AI 输入框内按一次 OK，只提交一次；选择器内按 OK 只确认选项。
- 切换任务 / 窗口，检查可见目的地；打开预览后，Home 回到原绑定。
- AI 运行时长按 Back，只停止已确认的那个任务。
- 断开遥控器、焦点未知、目标缺失、处于 shell、语音仍在排空时，不发送、不盲目中断。

## 排障与完成判据

| 现象 | 下一步 |
| --- | --- |
| 找不到 `$vibe-remote` | 检查安装输出、技能链接及源仓库目录；重新打开 Codex 会话 |
| 蓝牙连接但没有声音 | 先检查桥接软件和实际输入设备，再做录音对照；不要只调整 AI APP |
| 语音开始后立即停止、松开后仍未结束 | 核对豆包 / Typeless 实际快捷键、Fn 模拟开关以及重复映射 |
| 普通按键不响应 | 检查桥接的输入监控 / 辅助功能权限，重启桥接，再用其按键测试确认事件 |
| helper 报绑定未验证 | 保留阻止状态，实际观察目标后补全绑定；不要为消除错误盲改 `verified` |
| tmux / SSH 失败 | 检查命令是否存在、真实 session 与已有 SSH 别名；确认终端附着到同一 session |
| tmux 切换无法验证 | 先检查当前窗口，不要盲目重复；helper 已尝试过选择 |
| APP 返回到错误会话 | 重新观察窗口和任务标识，修复绑定；激活 APP 不等于选中任务 |

软件单元测试验证规划与选择逻辑，不证明蓝牙、音频、输入法或 GUI 已经完成验收。完整检查表见 [acceptance.md](../skills/vibe-remote/references/acceptance.md)。

本包不提供常驻浮层、软件指针、自动硬件事件到 Agent 的调度、CLI 图像传输或跨机器配置同步。`plan` 只输出语义动作，不监听按键、不注入快捷键；调用它时的状态必须来自当时的连接和界面观察，不能从保存的配置推断。没有桥接支持的动作应留作待办。

把验证后的设置、设备 / 软件版本和剩余事项记在自己的项目记录中；公开反馈只提交必要的脱敏信息，不提交个人配置、凭据、音频或听写全文。第三方设置会变化，升级后重新核对其官方说明。以上桥接资料核对于 2026-10-02。
