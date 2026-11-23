# cosmNotes

**中文** | [English](README.en.md)

一个用原生 Swift 和 SwiftUI 编写的 macOS 桌面便签应用，无第三方依赖。

cosmNotes 是「StickyNotes 大神的迭代版」，基于 simony3 开发的 StickyNotes v2.2.0。仓库和应用包均保留原版 MIT 许可及版权声明。[StickyNotes v2.2.0](https://github.com/simony3/StickyNotes/tree/v2.2.0)

## 截图

<table>
  <tr>
    <td align="center"><b>📝 文字便签</b><br><sub>Markdown 渲染 · 玻璃拟态</sub></td>
    <td align="center"><b>✅ 待办事项</b><br><sub>打勾自动划掉</sub></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/note-text.png" width="330" alt="文字便签: Markdown 预览效果"></td>
    <td><img src="docs/screenshots/note-todo.png" width="310" alt="待办事项便签"></td>
  </tr>
</table>

<b>🕰 历史便签</b> —— 删除的便签按日期归档, 随时回顾每天做了什么, 可一键恢复<br>
<img src="docs/screenshots/history.png" width="480" alt="历史便签: 按日期分组回顾">

<br><b>📏 折叠便签 + 屏幕边缘吸附</b> —— 一键折叠成一行标题条 (待办自动带完成进度);
拖到屏幕左/右边缘自动吸附, 贴边端被"切平", 松手平滑归位并伴随触控板触感反馈<br>
<img src="docs/screenshots/capsule-todo-snapped.png" width="190" alt="吸附左边缘的待办折叠条, 带 2/4 进度, 左端切平"><br>
<img src="docs/screenshots/capsule-text-snapped.png" width="112" alt="吸附左边缘的文字便签折叠条"><br>
<img src="docs/screenshots/capsule-free.png" width="135" alt="未吸附的折叠条, 两端圆角胶囊形">

## 功能

- **两种便签类型**
  - 📝 **文字便签**：支持 Markdown（标题、列表、待办语法、引用、粗体/斜体/行内代码、分割线），一键切换编辑/预览
  - ✅ **待办事项**：逐条添加待办，点勾选框完成后自动划掉，支持编辑、删除单条
- **三种窗口模式**（每张便签独立设置）
  - 📌 置顶悬浮 —— 永远盖在其他窗口上
  - 🪟 普通窗口 —— 和普通应用一样
  - 🖥 贴在桌面 —— 沉到桌面层，像小组件一样贴着壁纸，不遮挡任何操作
- **历史便签**：删除的便签自动按日期归档，按天分组回顾过去做了什么，可一键恢复
- **折叠便签**：一键收起成一行标题条，标题取自第一行内容且永不省略，待办便签带完成进度（如 `2/4`），折叠状态重启后保持
- **边缘吸附**：折叠条拖近屏幕左/右边缘自动吸平，贴边端圆角变直角（被屏幕"切割"的效果），带触控板触感反馈，松手平滑归位
- **预览里直接打勾**：文字便签预览模式下，`- [ ]` 渲染出的方框可直接点击勾选/取消，原文自动同步
- **荧光笔**：像真的荧光笔一样拖动涂抹重点，文字/待办便签都支持；模式内退格键逐字擦除，荧光色随便签主题自动搭配；高亮持久保存、编辑文字时自动跟随移动、预览模式下同样可见
- **AI 集成（MCP）**：内置 MCP 服务器，Codex / Claude 等 AI 助手可直接新建、修改、删除、移动、折叠和恢复便签（见下文）
- **五种柔和配色**：莫兰迪色系的柠檬黄 / 蜜桃粉 / 薄荷绿 / 天空蓝 / 丁香紫
- **玻璃拟态设计**：磨砂半透明背景、渐变玻璃边框、衬线体标题
- **自动保存**：停止输入 1 秒后自动写盘，位置、大小、颜色、模式全部记住
- **开机自启**：菜单栏一键开关
- **不打扰**：不占 Dock，安静地住在菜单栏；无边框圆角卡片设计

## 安装

需要 macOS 14 或更新版本。下载 ZIP 并解压，将 `cosmNotes.app` 拖入「应用程序」。ZIP 包支持 Apple Silicon 和 Intel Mac，采用临时签名。[下载最新版](https://github.com/Cosmofang/cosmNotes-app/releases/latest)

也可以安装 Xcode Command Line Tools（`xcode-select --install`）后在本机编译。

```bash
git clone https://github.com/Cosmofang/cosmNotes-app.git
cd cosmNotes-app
./build.sh
```

`build.sh` 会生成带临时签名的 `build/cosmNotes.app`。

### 软件更新

cosmNotes 启动时及运行期间每四小时检查 GitHub Releases。发现新版后，菜单栏会显示下载提示。也可以点「检查更新…」立即检查。点「下载更新」获取 ZIP。解压后退出旧版，再把新应用拖入「应用程序」完成更新。

## 使用

展开工作时间轴后，点击右上角太阳和月亮开关的任意位置，即可在浅色和深色外观之间切换。便签、月历和表单会一起切换，重新打开应用时会恢复上次选择。macOS 26 起支持原生 Liquid Glass 控件。

### 工作时间轴

从菜单栏选择「工作时间轴」或「新增工作…」。每条工作需要标题和截止日期，概要选填。

工作时间轴默认以普通窗口显示。点击标题栏的图钉开启或取消窗口置顶，应用会记住这个设置。也可以用标题栏按钮收起或展开时间轴。

时间轴的月历用项目配色标记截止日，单独一天显示圆点，同一项目连续的截止日连成线。点月份标题右侧的箭头可收拢月历。可翻月查看，点日期筛选当天的工作，点「全部日期」清除筛选。新增或编辑工作时，点「截止日期」打开月历选日。

按住月份标题旁的拖动把手，向下拖可把月历放到项目列表下方，向上拖可移回上方。应用会记住月历的位置。

展开时可拖动窗口的边缘或角落调整大小。收起再展开或下次打开 App 时，时间轴会恢复上次调整的大小。

时间轴顶部的项目色块按名称宽度排列，放不下就换行。点项目旁边的铅笔可改名和换色。把工作的标题拖到项目名上即可归类，拖到「未归类」可移出项目。点击项目名查看该项目的工作，也可在新增或编辑表单选择项目。

点击「全部工作」可查看项目树。按住项目右侧的三横线上下拖动，周围条目会让开，虚线框标出放下的位置。顶部项目色块会同步调整，应用会记住顺序。点项目行展开或收起其中的工作，每个项目可以独立展开。项目都收起时，点列表底部的「添加项目」可创建项目。展开项目或单独查看项目时，从工作列表底部的「添加工作」打开表单，项目会自动选中。「未归类」列表底部的「新增工作」会预选「未归类」。

点击工作标题可展开或收起下方的概要。已有备注会显示为概要。点击「添加概要」或工作的铅笔即可填写和修改。

点工作右侧的图钉可将它移到最上方的「已置顶」组，再点一次恢复按日期分组。未手动排序的待办工作默认按截止日期从近到远排列，逾期工作排在其他未置顶工作前。截止当天仍在「今天」，过了当天才算逾期。已置顶的工作勾选后也会进入「已完成」，恢复为待完成时回到「已置顶」。

按住工作右侧的三横线，可以在同一项目的同一分组内上下拖动。松手后会保存顺序，重启后仍可查看。

### 桌面便签

| 操作 | 方法 |
|---|---|
| 新建便签 | 菜单栏 📝 图标，或便签顶栏 **+**（都会让你选类型） |
| 移动 | 按住便签任意位置拖动 |
| 调整大小 | 拖拽便签边缘。待办便签默认按内容自动定大小（最长一条单行放下，超过 360pt 换行）；手动拖过的方向以你拖的为准，右键 →"恢复自动适配大小"可还原 |
| 换颜色 / 切换窗口模式 | 鼠标悬停在便签顶栏（便签较窄时收进"···"菜单） |
| 编辑 / 预览 | 顶栏 ✏️ / 👁 按钮 |
| 折叠 / 展开 | 顶栏最右侧折叠按钮 |
| 贴边吸附 | 拖动折叠条靠近屏幕左/右边缘（16pt 内自动吸附，拖离恢复） |
| 待办打勾 | 待办便签点方框；文字便签预览模式下点 `- [ ]` 方框同样有效 |
| 荧光笔 | 顶栏荧光笔按钮或 `⌘⇧H` 进入模式：拖过文字上色、单击只放光标、退格逐字擦除、Esc 退出；右键菜单可擦除所选/清空全部高亮 |
| 删除便签 | 顶栏左上角 ✕（会归档进历史，可找回） |
| 查看/恢复历史便签 | 菜单栏 →"历史便签" |
| 召唤所有便签 | 点 app 图标 |

### Markdown 速查（文字便签）

```markdown
# 大标题   ## 中标题   ### 小标题
- 无序列表
- [ ] 待办   - [x] 已完成
> 引用
**粗体** *斜体* `代码`
---
```

## AI 集成（MCP）

应用附带一个使用 Python 3 标准库的 MCP 服务器。接入 Codex 后，可以说「用 cosmNotes 新增工作『整理周报』，截止 2026-11-20」。写盘后 Codex 会收到工作标题、截止日期和记录 ID。[MCP](https://modelcontextprotocol.io/)

**提供的工具：**

| 工具 | 说明 |
|---|---|
| `create_work` | 在工作时间轴新增工作。传入 `title` 和 `due_date`（`YYYY-MM-DD`），可用 `notes` 填写概要。 |
| `create_note` | 创建便签（类型 / 颜色 / 窗口模式 / 折叠等全参数，可直接指定要涂荧光和加粗的词） |
| `update_note` | 按 id 修改内容、颜色、窗口模式、预览和折叠状态，也能重设荧光/加粗标记 |
| `delete_note` | 删除便签（非空内容自动进入历史） |
| `move_resize_note` | 移动便签或调整窗口大小（给待办便签指定宽/高后，该方向不再自动适配） |
| `list_notes` / `list_history` | 读取当前便签和历史归档（含操作所需 id） |
| `restore_note` | 将历史归档恢复成便签 |
| `delete_history_item` | 彻底删除指定历史记录 |
| `show_all_notes` / `show_history` | 唤起所有便签或打开历史窗口 |

标记按「文字内容」指定而不是下标：`highlight: ["重点"]` 会把便签里每一处"重点"都涂上荧光，`bold` 同理；传 `[]` 表示清空。只用 `update_note` 改正文时，原有的荧光和加粗会按标过的字自动在新内容里找回来，不会因为 AI 改了一句话就全丢。

日常修改由 cosmNotes 接收并保存。批量迁移或恢复数据时，为 MCP 进程设置 `COSMNOTES_ENABLE_ADMIN_TOOLS=1` 可启用 `admin_export_data` 和 `admin_overwrite_data`。覆盖数据需要匹配当前数据版本并显式确认。

在 Codex 桌面版使用时，将以下配置追加到 `~/.codex/config.toml`。

```toml
[mcp_servers.cosmnotes]
command = "python3"
args = ["/Applications/cosmNotes.app/Contents/Resources/mcp/cosmnotes_mcp.py"]
```

在 Claude Code 中注册 MCP 服务器。

```bash
claude mcp add cosmnotes -- python3 /Applications/cosmNotes.app/Contents/Resources/mcp/cosmnotes_mcp.py
```

重启客户端后 AI 即可看到上述工具。

## 数据存储

便签、历史、工作和项目保存在 `~/Library/Application Support/cosmNotes/` 下的 `notes.json`、`history.json`、`work-items.json` 和 `work-projects.json`，均为明文 JSON。

隔离测试时，在启动应用前退出当前运行的 cosmNotes，并为应用和 MCP 进程指定相同的 `COSMNOTES_DATA_DIR`。从源码运行 MCP 脚本时，可用 `COSMNOTES_APP_PATH` 指定测试用的应用包。

## 项目结构

```
Sources/StickyNotes/
├── main.swift          # 入口, NSApplication 启动, 隐藏编辑菜单(快捷键支持)
├── AppIdentity.swift   # 应用标识、偏好设置和数据目录
├── AppDelegate.swift   # 菜单栏、便签窗口管理、类型选择、URL 接口
├── Note.swift          # 数据模型 + JSON 持久化 + 待办条目读写 + 历史归档
├── NoteView.swift      # SwiftUI 界面: 便签视图、待办清单、Markdown 渲染、折叠条
├── HistoryView.swift   # 历史便签窗口: 按日期分组、恢复、彻底删除
├── WorkTimeline.swift  # 工作时间轴窗口和编辑表单
└── NoteWindow.swift    # 无边框窗口、三种层级模式、折叠与边缘吸附
Sources/CosmNotesWork/  # 工作数据、日期分组、保存和本地请求
mcp/
└── cosmnotes_mcp.py    # MCP 服务器: AI 客户端控制便签的入口
```

## 共同迭代

从公开仓库的 `main` 开分支提交 Pull Request。没有写权限时，可以先 Fork 再提交 Pull Request。GitHub Actions 会编译应用并检查工作保存、窗口几何和版本识别。[公开仓库](https://github.com/Cosmofang/cosmNotes-app)

发布新版本时，更新 `Resources/Info.plist` 的版本号和构建号。给合入的提交推送对应的 `vMAJOR.MINOR.PATCH` 标签，GitHub Actions 就会生成通用 ZIP 和 SHA-256 校验文件并发布到 Releases。

## License

[MIT](LICENSE)
