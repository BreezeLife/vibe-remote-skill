# Vibe Remote

用小米蓝牙遥控器 2 Pro，把语音输入、AI 任务选择和编码窗口切换串成一个工作流。

[English](README.en.md) · [上手指南](docs/SETUP.md) · [完整按键约定](skills/vibe-remote/SKILL.md) · [MIT](LICENSE)

Vibe Remote 是一个 Codex skill，包含语音工具配置指南、受状态约束的按键规划器，以及可执行的本机／SSH tmux 切窗工具。按住麦克风说话，松开保留草稿，检查目标和文字后再确认发送。

实体遥控器的按键和音频由独立桥接软件接收。此仓库不提供蓝牙驱动、后台按键监听器或常驻悬浮窗；安装 skill 后，遥控器不会自动接入 Codex。

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

## 安装

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

GitHub Actions 在 Linux 和 macOS 上运行测试与模板校验。贡献前阅读 [PROJECT.md](PROJECT.md)、[MEMORY.md](MEMORY.md)、[TASKS.md](TASKS.md) 和 [WORKLOG.md](WORKLOG.md)，把新决策和实际验证结果写回记录。不要提交本地状态、凭据、录音或听写内容。

桥接参考：[SayAll](https://github.com/HD838A/remote-mic-app)、[MiCoding](https://github.com/zhangtuansia/MiCoding)、[MiRemoteVoice](https://github.com/VincentKingHsu/MiRemoteVoice)。这些是独立项目，依各自许可与安装说明使用；本仓库未打包其源码或驱动。

## 许可

本仓库原创代码与文档采用 [MIT License](LICENSE)。
