# Viewin Android

Android API 29+。当前没有发布 Maven 坐标；仓库内 Demo 直接依赖本地模块，其他宿主可将 viewin-sdk 和 viewin-protocol 作为本地 Gradle 模块接入。

在 Application.onCreate 中显式启动，Debug 和内部 Release 均可用：

```kotlin
implementation(project(":viewin-sdk"))

Viewin.start(this, buildType = if (BuildConfig.DEBUG)
    Viewin.BuildType.DEBUG else Viewin.BuildType.INTERNAL_RELEASE)
// Viewin.stop()
```

SDK 默认仅监听 `127.0.0.1:48721`。只在收到请求时采集，Activity 生命周期只保留弱引用；stop 释放监听器、客户端和生命周期观察。未知构建类型只根据宿主 FLAG_DEBUGGABLE 识别 Debug，不猜测是否为内部 Release。

Mac 上通过 Android Studio 或 `adb start-server` 启动本机 ADB 服务，USB 设备授权调试。桌面客户端直接与本机 ADB 服务通信，兼容 App Sandbox，不启动外部程序。Viewin App 和 `viewin --list` 按需查找已授权设备/模拟器，为 48721…48726 建立或复用 ADB 转发，无需打开 Mac App 即可使用 CLI。也可手动执行 `adb -s SERIAL forward tcp:48731 tcp:48721` 后用 `viewin --port 48731 --output android.viewin`。

支持 View/XML 实际层级、dp 坐标与变换四角、可见性、resource ID、文本与颜色、布局参数、padding/margin、滚动、控件状态、列表位置（AdapterView 和 AndroidX RecyclerView），以及公开的点击 Listener 存在状态。不会执行 Listener。不提供 XML 文件/行号及 Listener 源码跳转；resource ID 用于识别节点。

RecyclerView 使用可选的公开 API 反射桥接，SDK 不额外依赖 RecyclerView；宿主已使用 AndroidX RecyclerView 时自动识别。容器展示 Adapter、LayoutManager、itemCount、Stable IDs、已挂载 item 数量、滚动与布局状态；Linear/Grid/StaggeredGrid 展示方向、反向布局及对应布局参数。item 根节点展示 ViewHolder、Binding Adapter、absolute/binding/layout position、itemViewType、recyclable 和 Int64 itemId；侧边栏显示 absolute position，ConcatAdapter 的子 Adapter 位置单独保留。未启用 Stable IDs 或 NO_POSITION 等无效状态标记 unavailable，不生成假值。只读取已挂载 item，不创建或滚动离屏 item，不写入宿主 tag，也不执行回调或读取业务模型。所需的反射入口通过 SDK consumer R8 规则保留；自定义 Adapter/ViewHolder 类型显示实际运行时名称，混淆后名称可能变短。已用 RecyclerView 1.4.0、ConcatAdapter 和开启 R8 的内部 Release Demo 验证。

Demo 提供 100 条 ConcatAdapter 数据、Stable IDs 开关、Linear/Grid 切换和删除首项，便于检查复用后位置与 ID 的更新。

图片使用软件 `View.draw`。收起使用完整子树图片；展开时容器只有背景，叶子为自身图片，不隐藏或移动子 View。自绘容器、前景、阴影、SurfaceView/TextureView 及部分硬件特效不能保证完整呈现。每图最长 1400 px，最多 512 份去重图片、128 MB 图片数据、5000 节点、127 层和约 8 秒遍历预算；超出时标记 partial，不作为完整采集返回。

Dialog 可在 show 后调用 `Viewin.registerWindow(dialog.window!!)`，dismiss 时 unregisterWindow。不读取系统私有 WindowManager 列表。示例已演示。

Compose 宿主选择可选模块 `viewin-compose`（已包含 `viewin-sdk`）；非 Compose 宿主继续仅依赖 `viewin-sdk`。Compose 模块使用 Compose UI / tooling-data 1.10.6，并沿用现有 `Viewin.start` 和 ADB/协议，不需要 Android Studio 注入 Agent、源码插件或每个组件手动添加 Modifier。启动应在 Application.onCreate、首次 setContent 之前。Debug 会提前开启 Inspector 数据收集；不对已创建的 Composition 执行 hot reload。

Debug 优先通过 Composition tooling 与 LayoutInfo 获取实际已布局节点，合并没有独立布局的调用包装层，在检查器保留 Call Chain、参数、Modifier 和未合并 Semantics。内部 Release 无 Composition 数据时降级为 Semantics：可读文字、testTag、角色、状态、语义操作和布局，但不保证装饰节点、完整组件名或 Modifier 参数。操作只读，不执行回调。LazyColumn 只导出已放置且激活的节点，不主动滚动或创建离屏 item。

Compose 图片目前是宿主软件合成图裁切，只供收起的子树使用；展开容器仅显示边框，尚无独立绘制层图片，不宣称完整 3D 渲染拆层。Dialog/Popup 独立窗口沿用显式注册窗口方式，尚无自动跨窗口关联。Compose 内嵌 AndroidView 的原生分支仍由 View 采集器导出，尚未重挂到对应 Composable 节点。版本兼容范围需要随实测扩展；缺失信息通过 capabilities 和 partial 原因明确报告。

Android Studio 的 Gradle JDK 选择内置 JDK；终端的 `JAVA_HOME` 指向同一个 JDK，不在仓库下载或保存 Java。

运行 `./gradlew :demo:assembleDebug :demo:assembleRelease :viewin-protocol:test`。使用 Android Studio 自带 JDK / Android SDK 36。构建固定 Gradle 9.3.1 + AGP 9.1.1，兼容当前内置 JDK 25；字节码目标为 Java 17，不要求另装 Java 17。Release Demo 启用 R8 并使用开发签名，仅用于内部验证，不能作为正式发布包。

参考 CodeLocator 的 View 遍历、结构化字段及分层绘制思路，独立实现 Viewin 协议和 SDK，无 CodeLocator 运行依赖或源码拷贝。
