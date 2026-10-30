# 自定义 View

> M3 交付，其中渲染器与组件目录可与 M1 并行开发。本篇定义插件页面的注册、显示、状态、渲染器、组件目录和 UI 协议。任务进度只在[实施任务](README.md#实施任务)维护。

## 注册与显示

插件注册“人物整理”独立页面：

```js
export function apply(context) {
  context.views.register({
    id: "character-organizer",
    title: "人物整理",
    location: "plugin.page",
    source: "views/character-organizer.json",
    actions: {
      refresh: (data, event, call) => loadCharacters(context, data),
      save: (data, event, call) => saveCharacters(context, data),
    },
  });
}
```

- `plugin.page` 是独立插件页面位置，入口显示在宿主导航中。M3 只开放这一个位置；侧栏、人物详情面板、编辑器菜单等位置列入[后续迭代](README.md#后续迭代)。
- `source` 相对于插件目录，Host 校验资源属于当前插件。插件 ID 与页面 ID 共同作为页面身份。
- `source` 文件是一组 A2UI 消息（创建界面、更新组件、更新数据），格式见 [UI 协议与版本](#ui-协议与版本)。界面 ID 由 Host 分配，文件中的界面 ID 会被替换。
- action 处理函数收到当前页面数据快照和事件，返回一组数据更新 `[{ "path": "/characters", "value": [...] }]`，语义与 A2UI 的“更新数据”消息相同。
- 通知、确认框和选择器通过 `context.ui` 提供，不必为临时交互注册完整页面。

```text
views.register
  → 注册表保存页面归属和描述
  → 宿主导航显示“人物整理”

用户打开页面
  → PluginSurfaceHost 挂载页面
  → 读取 source 中的 A2UI 消息，交给渲染器建立界面和页面数据
  → 渲染器按组件目录构建 Flutter 组件

用户点击页面按钮
  → 渲染器把 action 交给该界面的事件处理方（插件页面即插件）
  → Host 新建运行时，调用对应 action，传入页面数据快照和事件
  → action 按需调用 Host API，返回数据更新
  → 渲染器应用更新，刷新相关组件
```

## 页面状态

插件运行时每次执行后关闭（见[运行时模型](architecture.md#运行时模型)），所以页面状态由 Host 持有：

- 每个页面实例有自己的 DataModel，保存草稿、选中项等界面状态，不镜像到全局 Riverpod，见 [ADR-0011](../../adr/0011-plugin-ui-state-boundary-datamodel-riverpod.md)。
- action 收到页面数据快照，返回按路径的数据更新；渲染器应用后刷新。同一页面的 action 按顺序执行，前一个返回后再执行下一个。
- 业务数据通过 Host API 读写，宿主继续通过自己的状态管理观察业务变化。
- 关闭一个页面不影响同插件的其他页面；页面关闭后返回的 action 结果直接丢弃。
- 插件停用时关闭它的全部页面。
- 页面含未保存编辑时，关闭前由 Host 弹出确认。

## 渲染器与组件目录

渲染分两层：

| 层 | 实现 | 职责 |
| --- | --- | --- |
| 协议层 | `a2ui_core`（纯 Dart，不依赖 Flutter） | 解析与校验 A2UI 消息（创建界面、更新组件、更新数据、删除界面），维护页面数据模型，解析 `path` 绑定与表达式，按组件目录的 JSON Schema 校验界面 |
| Flutter 层 | 自行实现 | 组件目录中每个组件的 builder；把扁平组件组装为 Widget 树，数据变化时只刷新受影响的组件；把组件上的 `action` 交给该界面注册的事件处理方 |

事件处理方可以替换，渲染器不关心处理方是谁：插件页面交给插件 action，以后 AI 生成的界面交给 Agent。

依赖选择：

- 不引入 `genui`。它标注为 “highly experimental”，正在拆分重写，且面向 AI 在对话中生成界面；插件页面是固定界面描述加插件处理事件，组件目录无论如何都要包装项目自己的组件。
- 引入 `a2ui_core` 作为协议层。它由官方 A2UI 仓库维护，支持 A2UI v0.9 与 v1.0，协议细节与官方一致，以后 AI 生成界面时也用它解析和校验模型输出。
- `a2ui_core` 仍是 0.x，更新频繁：锁定版本；只在渲染器内部使用，插件只认 `reveric-ui-v1`，接触不到它的 Dart 类型；它出现破坏性变化时只改渲染器内的适配代码。引入前按 `.agents/rules/local-dependencies.md` 处理。
- 官方 Flutter 渲染包（`a2ui_flutter`）发布并稳定后，可再评估是否替换 Flutter 层；界面格式一致，替换不影响插件。
- 所用 A2UI 版本在 T-14 开工时确定，优先 v1.0，选定后写回本节和 [UI 协议与版本](#ui-协议与版本)。

组件目录的每个条目包含：组件名称、一句用途说明、属性 JSON Schema、Flutter builder、支持的数据绑定属性和事件。属性 Schema 用于校验界面描述，用途说明和 Schema 以后也用于生成让 AI 绘制界面的提示词，所以两者都必须完整。

组件实现包装项目已有 Widget，沿用主题、间距、字体、输入框和操作菜单。首批组件：

| 类别 | 组件 |
| --- | --- |
| 布局 | Column、Row、间距、滚动容器 |
| 展示 | Text、Markdown、Icon、加载状态 |
| 交互 | Button、TextField、Select、Switch |

- 人物选择器、章节选择器等业务组件按需求增加。
- 普通编辑表单必须整体存活，使用 `SingleChildScrollView + Column` 等非惰性布局，不能因为界面来自 JSON 而绕过表单生命周期和校验规则。
- 界面描述必须经过组件白名单、属性 Schema、层级和数量校验；页面报错显示局部错误状态，不影响宿主页面。
- 内置插件的 View 同样使用 A2UI 消息和组件目录，不直接提供 Flutter Widget。

T-14 中先确定首批组件各自的属性与事件 Schema、界面的层级和数量上限，完成后补入本节。

## 自定义工具卡片

M3 起，插件注册工具时可以提供 `display.view`，指向一份界面描述，用同一套渲染器和组件目录渲染工具结果；工具结果作为只读页面数据传入，卡片不触发 action。未提供时继续使用[通用插件卡片](tools.md#工具卡片)。

- 历史卡片始终用当前安装的插件版本中的界面描述渲染。插件更新后，旧调用的结果交给新版本的界面描述显示，插件自己负责兼容旧结果的字段。
- 插件已卸载、已停用、新版本不再提供 `display.view`，或界面描述渲染失败时，退回通用卡片，按调用时保存的 `display` 显示。插件声明 `display.view` 时应同时填写 `summaryArg`、`result`、`resultPath`，保证退回后仍可读。

## UI 协议与版本

- 对外 UI 协议名为 `reveric-ui-v1`，写在清单的 `uiProtocol` 中，对应 T-14 选定的 A2UI 版本的消息与组件格式，加上本项目的组件目录。
- 不扩展 A2UI 协议本身：消息类型、属性写法、`path` 绑定、`action` 都按选定的 A2UI 版本。可以自定义的只有组件目录，这是 A2UI 允许的。这样插件页面与以后 AI 生成的界面使用同一种格式、同一个渲染器和同一套组件。
- A2UI 升级时由渲染器跟进；能兼容旧格式时 `reveric-ui-v1` 不变，不能兼容时新增 `reveric-ui-v2`，渲染器同时支持两版，见 [ADR-0007](../../adr/0007-plugin-runtime-fjs-a2ui.md)。
- UI 协议与宿主业务 API 分别版本化。每个组件的属性和事件都属于契约，只新增兼容能力时不升版本。
- 暂不把 WebView、动态 Dart 执行、任意原生库加载或独立进程扩展纳入范围。
