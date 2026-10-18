# ViewinSDK

[English](README.md) · 简体中文

iOS / Android 布局采集 SDK，与 Viewin macOS 客户端独立维护。

```text
Package.swift          # SwiftPM 入口，无第三方依赖
ios/
  SDK/                 # iOS 接入和 UIKit 采集
  Protocol/            # Swift 共享模型
  Transport/           # Network 长度帧传输
android/               # Android View/XML SDK、可选 Compose 模块、协议、真实 Demo
protocol/              # 跨平台 Schema 和规范样例
examples/ios/          # 真实 UIKit / SwiftUI 宿主 Demo
```

## iOS 接入

SwiftPM 添加 `https://github.com/FeliksLv01/ViewinSDK`，选择 `ViewinSDK` 产品。当前尚未发布版本标签，可暂时选择 `main` 分支，或使用本地路径。

```swift
import ViewinSDK
try Viewin.start() // 127.0.0.1:48721，自动探测能力
// 可选：start(buildType: .debug) 或 .internalRelease，仅用于说明构建类型
// Viewin.stop()
```

最低 iOS 15。通过显式调用启用，Debug 和内部 Release 包均可使用；生产包是否包含或启用由接入方配置决定。当前已实现 UIKit 层级、结构化属性和截图；SwiftUI Debug 逻辑树目前适配 iOS 27，需在首个 SwiftUI 宿主创建前启动；提供已知布局、部分真实 CALayer 纹理关联和宿主合成截图裁剪，不承诺每个逻辑节点都有独立图层截图。Release 同样尝试实际读取，失败时回退 UIKit 宿主。Android View/XML 已有真实采集器和 ADB 连接；Compose 首版提供可选采集模块，Debug 读取 Composition / LayoutInfo / Modifier，Release 无调试数据时降级为 Semantics；无线配对待实现。参见 [Android 接入](android/README.md)。

打开 `examples/ios/ViewinDemo.xcodeproj` 运行 Demo；如修改 project.yml，使用 XcodeGen 重新生成。所有 xcodebuild 输出须通过 xcbeautify。framework / xcframework 分发产物使用 Git LFS。

## 与桌面客户端协同开发

将本仓库命名为 `ViewinSDK`，与桌面仓库放在同一父目录。桌面只依赖 `ViewinProtocol` / `ViewinTransport` 产品，无需引入 iOS 采集代码。它们是共享实现模块，iOS App 不需要额外配置。

- [Schema](protocol/schema/snapshot.schema.json)
- [规范样例](protocol/fixtures/)

Android DTO 的检查入口位于 `android/`；Gradle 测试直接读取本仓库 protocol/fixtures。源码仓库为 [FeliksLv01/ViewinSDK](https://github.com/FeliksLv01/ViewinSDK)，尚未发布版本标签或 Maven 制品。

当前版本的初始化 API 为 `Viewin.start()`，wire 服务标识为 `app.viewin.inspection`；请同步使用改名后的桌面客户端与 SDK。历史快照兼容由桌面客户端负责。

## 手势与控件事件（只读）

UIKit 采集手势 Enabled、Delegate、基础手势类型、成员引用和多个 Target/Action；控件事件使用系统名称并按事件分组，也识别 UIAction。采集不会触发事件或修改 Enabled。UIGestureRecognizer 没有公开 target/action 枚举接口，该部分使用经过字段类型与布局检查的 Objective-C 运行时读取；不支持的布局标记为 unavailable，不将其当作空绑定。SwiftUI Debug 提供可识别的静态手势 modifier；Swift 闭包不伪装成 UIKit Target/Action，不记录触发事件。

在 Demo 的 ViewinDemo scheme 执行测试，可验证多目标手势、成员引用、控件事件和 UIAction 的只读采集；测试目标为 ViewinSDKTests。

## 构建类型与能力

宿主可以通过 `buildType` 声明自己的构建类型；默认 `unknown`，不会通过 SDK 的 DEBUG 标记、签名或包名猜测 App 类型。握手和快照的 `target.buildType` 均报告此声明。它是诊断元数据，不是安全认证。

SwiftUI 采集不以 buildType 或 SDK 的 DEBUG 标记作为开关。iOS 27 上会提前启用调试记录并尝试实际读取；capabilities 由读取结果生成。Debug 模式通常能读取逻辑树，当前 iOS 27 模拟器实际 Release Demo 可读取逻辑树，但部分测试场景返回空树，不能仅根据构建名称保证可用。需在首个 SwiftUI 宿主创建前启动，已有页面不保证补录。当前未验证真机与其他系统版本。

SwiftUI 快照输出可读视图树：合并 ModifiedContent、StaticIf、EmptyModifier、内部样式与解析包装，保留业务 View 和可识别的视图节点。受支持的布局/样式 modifier 作为后续视图的结构化属性组，静态手势作为该节点的事件属性；原始路径保留于属性组标识。内部包装深度与输出视图深度分别设预算，避免样式展开提前截断业务内容。此规则在 SDK 中执行，CLI 和桌面端得到相同结果，历史快照需重新采集。

## SwiftUI 渲染图层关联（iOS 27）

按次读取 Hosting View 渲染器的 `lastList` 与 `viewCache`，将 Display List 渲染项关联到缓存中实际的 CALayer 对象；部分匿名 content 继承上层 identity effect 的标识，`identityScope` 会标明来源。另行读取经过签名检查的 `swiftUI_displayListID`，忽略无效/保留值。未匹配、重复缓存指向不同图层及不支持的运行时结构均不猜测对象地址。读取与输出均有深度/数量预算，不保留跨采集的 CALayer 缓存。

`swiftuiRendering` 节点保存有效 Display List ID、内容类型、图层地址、实测几何和真实 CALayer 子树截图；它们不同于 SwiftUI 逻辑 View。桌面端的渲染分支默认收起并在预览中隐藏，点击属性关联会显示并定位目标，支持反向跳转。CLI 获得相同节点、属性、图片和关系。

当前逻辑树入口在已验证场景未返回 per-View Display List 属性，因此逻辑 View 到渲染项仅在内容类型与窗口几何唯一匹配时生成 `renderedByGeometry`，界面明确标为推断。匹配比较四角坐标，避免相同包围盒的旋转图层错配；同位置的父子链选择最深节点，同级重叠和多个渲染候选不关联。逻辑叶子节点使用匹配图层的真实纹理（明确标注 `geometryInference`），展开和收起使用同一真实叶子图片；其他节点保留标明来源的宿主合成裁切。被替换且无引用的裁切图片不再传输或保留。不会把推断结果标成精确的 Display List 绑定。实际能力见 `swiftui.layerBindings`、`swiftui.layerImages`、`swiftui.logicalLayerImages`；完整 Display List 重放尚未实现。私有缓存布局目前仅验证 iOS 27 模拟器，Debug 和普通 Release Demo 均可用，其他版本/结构回退并报告原因。

SwiftUI 合成裁切仅保存为收起子树的 groupImage；展开时，逻辑容器和具有逻辑子节点的 Hosting View 不重复贴子树截图。成功关联的独立叶子 CALayer 图片可用于展开视图，其余节点保留边框。
