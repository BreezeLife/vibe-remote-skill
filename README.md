# Vibe Remote

用小米蓝牙遥控器 2 Pro，把语音输入、AI 任务选择和编码窗口切换串成一个工作流。

[English](README.en.md) · [上手指南](docs/SETUP.md) · [完整按键约定](skills/vibe-remote/SKILL.md) · [MIT](LICENSE)

Vibe Remote 是我们自己的 macOS 遥控器应用。0.2 开发预览提供直接蓝牙听写、
可视化按键配置，以及 Codex、Claude、WorkBuddy 的工作区绑定与经过检查的输入动作。
无需安装 MiRemote、SayAll 或 BlackHole。
0.2.3 按 Pro 2 实物排列按键，提供三种编程工具默认方案；动作按工作区独立保存，
已学习的实体键值共用。进入「编程工具」添加默认方案，或为已有工作区显式应用。
现有 Codex skill 和 tmux 工具继续保留。

## 原生应用开发预览

需要 macOS 13+ 和 Xcode Command Line Tools：

```sh
bash scripts/test_macos_core.sh
bash scripts/build_macos_app.sh
open "$HOME/Library/Caches/VibeRemote/Build/Vibe Remote.app"
```

普通构建输出到本机缓存目录，不需要管理员权限。日常安装使用 `.pkg`：从 0.2.2 起，
安装器经管理员授权，统一安装到 `/Applications/Vibe Remote.app`。
开发副本与已安装的应用请保持只运行一份；完整安装命令见下方原生应用上手指南。

点击连接与语音授权，按住遥控器语音键说话，松开等待草稿，检查后复制。
默认本机语音识别；所选语言不支持时会提示，可自行选择允许 Apple 在线识别。
音频和草稿不写入本地历史。退出前请复制需要保留的内容。

[原生应用上手指南](docs/NATIVE-SETUP.md) · [设计说明](docs/NATIVE-DESIGN.md)

这是本地构建的开发预览，尚未签名公证发布。真实遥控器、权限和音频识别仍需实机验收。
0.2 使用 Apple Speech，提供单击/长按/可选双击、独占按键校准、工作区内存草稿和
AX 输入/发送/停止适配。工具未提供所需控件或实时状态时，动作会停用并保留草稿。
豆包 / Typeless 虚拟麦克风及 CLI 深度适配仍是后续里程碑。
下面的表格描述保留的 skill 能力，不代表原生应用已执行所有动作。

## 当前能力

| 场景 | 已提供 | 使用前还需确认 |
| --- | --- | --- |
| 豆包输入法 | 按住／释放语音键的配置与流程 | 输入法快捷键、桥接音频和权限 |
| Typeless 等工具 | 成对点按的语音流程、可扩展配置 | 实际快捷键和桥接软件支持 |
| Codex／ChatGPT App | 任务绑定、左右切任务、返回输入框的操作规程 | 当次可观察的任务、窗口与输入框 |
| 终端标签／窗格 | 精确绑定与切换规程 | 终端界面和当前 AI 输入状态 |
| 本机／SSH tmux | 列出窗口、按稳定 ID 切换、确认结果、边界不循环 | 已有 tmux 会话和终端绑定 |
| 按键规划 | JSON 语义动作与发送／停止／重复事件保护 | 外部执行器提供真实状态并执行动作 |

自动化检查覆盖配置、语音时序、发送保护、tmux 命令和安装器。蓝牙音频、实体按键及 GUI 操作需要单独实测，进度见 [TASKS.md](TASKS.md)。

## 安装支持 skill

需要 Git、Python 3.10 或更高版本，以及支持本地 skills 的 Codex。Python 工具仅使用标准库。

```sh
git clone https://github.com/BreezeLife/vibe-remote-skill.git
cd vibe-remote-skill
python3 scripts/install_skill.py
python3 skills/vibe-remote/scripts/vibe_remote.py doctor
```

安装器把 `skills/vibe-remote` 链接到 `~/.codex/skills/vibe-remote`，或 `CODEX_HOME` 指定的 skills 目录。保持仓库目录可用；重复安装同一来源不会更改内容，已有不同来源会被保留并报告冲突。安装到其他目录可使用 `--destination <skills目录>`。

在 Codex 新会话中输入：

```text
$vibe-remote 我已有小米蓝牙遥控器 2 Pro。先检查本机环境，
配置豆包输入法，绑定当前 Codex 项目，并按验收清单逐项验证。
```

需要 Typeless 或 CLI 时，明确写出输入工具和目标终端／已有 tmux 会话。完整配对、桥接、任务绑定和排障步骤见 [上手指南](docs/SETUP.md)。

## 本地配置与命令

首次使用时复制模板；如果已有 `config.local.json`，直接编辑已有文件。该配置属于本 skill，不能直接导入 SayAll 或 MiCoding。

```sh
cp -n skills/vibe-remote/assets/config.default.json config.local.json
python3 skills/vibe-remote/scripts/vibe_remote.py validate config.local.json
```

模板中的工作区均为 `verified: false`。看到真实目标并确认绑定后才改为 `true`；APP 需记录 `window_title` 和 `task_anchor`，tmux 需填写已有的精确会话名。配置校验成功仅代表格式有效。

| 命令 | 用途 |
| --- | --- |
| `doctor [--bluetooth]` | 只读检查依赖；蓝牙扫描仅支持 macOS |
| `validate <config>` | 校验配置结构 |
| `plan <config> --workspace <id> --state <state.json> --button <button> --gesture <gesture>` | 返回动作规划，始终 `executes: false` |
| `windows <config> --workspace <id>` | 读取绑定的 tmux 会话窗口 |
| `switch <config> --workspace <id> --direction next` | 切到下一 tmux 窗口并核对结果 |
| `switch <config> --workspace <id> --window @3` | 切到该会话中已发现的稳定窗口 ID |

`plan` 的状态必须来自当前运行环境。配置中的任务名称不能证明焦点正确；未知录音状态、Shell 输入或目标不匹配会阻止发送。tmux 工具不创建会话、不启动 AI、不输入命令；服务端切换成功也需单独确认屏幕上的终端已附着到该会话。

## 按键约定

| 按键 | 意图 |
| --- | --- |
| 麦克风按住／松开 | 开始听写／结束并保留草稿 |
| 电源 | 选择已登记的工作区 |
| 左／右 | 上一个／下一个 APP 任务或 CLI 窗口 |
| 上／下 | 滚动输出，或移动选择项 |
| OK | 确认选择；在已确认的 AI 输入框发送草稿 |
| 返回单击／长按 | 返回或取消听写片段／停止已识别的 AI 任务 |
| 主页 | 返回绑定的 AI 输入框 |
| 菜单单击／长按 | 操作菜单／截图并检查附件 |
| TV 单击／长按 | 打开登记的预览／请求可选指针功能 |
| 音量 | 保持系统音量行为 |

截图、指针、选择器等是执行器应遵循的意图约定，部分依赖 companion app。只映射桥接软件实际支持的动作；不默认设置双击，发送与停止不可重复触发。

## 开发与验证

```sh
python3 -m unittest discover -s tests -v
python3 skills/vibe-remote/scripts/vibe_remote.py validate skills/vibe-remote/assets/config.default.json
```

GitHub Actions 检查原生应用构建，并在 Linux 和 macOS 上运行 Python 测试与模板校验。贡献前阅读 [PROJECT.md](PROJECT.md)、[MEMORY.md](MEMORY.md)、[TASKS.md](TASKS.md) 和 [WORKLOG.md](WORKLOG.md)，把新决策和实际验证结果写回记录。不要提交本地状态、凭据、录音或听写内容。

协议参考：[MiRemoteVoice](https://github.com/VincentKingHsu/MiRemoteVoice)。原生应用适配了其 MIT 协议代码，完整归属与许可见 [第三方声明](apps/macos/THIRD_PARTY_NOTICES.md)。本仓库不打包第三方应用或 BlackHole 衍生驱动。

## 许可

本仓库原创代码与文档采用 [MIT License](LICENSE)。
