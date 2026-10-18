# ViewinSDK

iOS / Android 布局采集 SDK，与 Viewin macOS 客户端独立维护。

```text
Package.swift          # SwiftPM 入口，无第三方依赖
ios/
  SDK/                 # iOS 接入和 UIKit 采集
  Protocol/            # Swift 共享模型
  Transport/           # Network 长度帧传输
android/               # Gradle 工程，目前仅协议 DTO
protocol/              # 跨平台 Schema 和规范样例
examples/ios/          # 真实 UIKit / SwiftUI 宿主 Demo
```

## iOS 接入

SwiftPM 添加本仓库，选择 `ViewinSDK` 产品。当前尚未配置远程地址或版本标签，本地开发可直接选择此目录。

```swift
import ViewinSDK
try Viewin.start() // 127.0.0.1:48721
// Viewin.stop()
```

最低 iOS 15。通过显式调用启用，Debug 和内部 Release 包均可使用；生产包是否包含或启用由接入方配置决定。当前已实现 UIKit 层级、结构化属性和截图；SwiftUI 仅采集 UIKit 宿主视图，逻辑树待实现。Android 尚无真实 View/Compose 采集器。USB 与无线配对待实现。

打开 `examples/ios/ViewinDemo.xcodeproj` 运行 Demo；如修改 project.yml，使用 XcodeGen 重新生成。所有 xcodebuild 输出须通过 xcbeautify。framework / xcframework 分发产物使用 Git LFS。

## 与桌面客户端协同开发

将本仓库命名为 `ViewinSDK`，与桌面仓库放在同一父目录。桌面只依赖 `ViewinProtocol` / `ViewinTransport` 产品，无需引入 iOS 采集代码。它们是共享实现模块，iOS App 不需要额外配置。

- [Schema](protocol/schema/snapshot.schema.json)
- [规范样例](protocol/fixtures/)

Android DTO 的检查入口位于 `android/`；Gradle 测试直接读取本仓库 protocol/fixtures。尚未建立远程仓库或发布 SDK 版本。

当前版本的初始化 API 为 `Viewin.start()`，wire 服务标识为 `app.viewin.inspection`；请同步使用改名后的桌面客户端与 SDK。历史快照兼容由桌面客户端负责。

## 手势与控件事件（只读）

UIKit 采集手势 Enabled、Delegate、基础手势类型、成员引用和多个 Target/Action；控件事件使用系统名称并按事件分组，也识别 UIAction。采集不会触发事件或修改 Enabled。UIGestureRecognizer 没有公开 target/action 枚举接口，该部分使用经过字段类型与布局检查的 Objective-C 运行时读取；不支持的布局标记为 unavailable，不将其当作空绑定。SwiftUI 逻辑手势尚未接入。

在 Demo 的 ViewinDemo scheme 执行测试，可验证多目标手势、成员引用、控件事件和 UIAction 的只读采集；测试目标为 ViewinSDKTests。
