# 构建与分发文档

> 版本：v0.1（2026-05-16）
> 对应技术设计：[02-technical-design.md](./02-technical-design.md)

本文档说明如何在 macOS 上从零搭建构建环境、构建各平台安装包、以及分发。
是技术设计文档第 9 节"Android 第一次构建踩 Gradle / NDK / JDK 版本"风险项的落地文档。

## 1. 范围与现状

| 构建目标 | 状态 | 能否在 macOS 上构建 |
|---|---|---|
| Android（APK / AAB） | ✅ 已打通 | 能 |
| macOS（桌面 .app） | ✅ 已打通 | 能 |
| Web | 可构建，未验证 | 能 |
| Windows / Linux | 需在对应系统上构建 | 否（见 02 文档 6.3 / 6.4）|
| iOS | 未启用（缺签名 / 描述文件配置）| 能，需额外配置 |

开发机：macOS（Apple Silicon，darwin-arm64）。本文档命令均基于 Homebrew 安装的 Flutter。

## 2. 工具链版本

下表是当前已验证可用的版本。**版本号不要凭记忆**，每项都标了"真实来源"——改版本时以来源文件为准。

| 组件 | 版本 | 真实来源 / 安装方式 |
|---|---|---|
| Flutter | 3.38.7（stable） | `flutter --version`；Homebrew |
| Dart | 3.10.7 | 随 Flutter |
| JDK（构建用）| Temurin 17.0.19 | `flutter doctor -v` 的 Java 行 |
| Android cmdline-tools | sdkmanager 20.0 | `brew --cask android-commandlinetools` |
| Android platform-tools | 37.0.0 | `sdkmanager` |
| Android 编译平台 | android-36 | Flutter `FlutterExtension.kt`（`compileSdkVersion = 36`）|
| Android build-tools | 36.0.0 | 同上，匹配 compileSdk |
| Android NDK / CMake | 28.2.13676358 / 3.22.1 | 首次构建自动下载 |
| Gradle | 8.14 | `android/gradle/wrapper/gradle-wrapper.properties` |
| Android Gradle Plugin | 8.11.1 | `android/settings.gradle.kts` |
| Kotlin | 2.2.20 | `android/settings.gradle.kts` |
| compileSdk / targetSdk / minSdk | 36 / 36 / 24 | Flutter 默认值，`android/app/build.gradle.kts` 引用 `flutter.*` |
| Xcode | 26.5 | macOS 构建用 |
| CocoaPods | 1.16.2 | macOS / iOS 构建用 |

> 注：技术设计 6.1 写的"最低 SDK 26"是目标值，当前 `build.gradle.kts` 用 `minSdk = flutter.minSdkVersion`（= 24）。若要强制 26，在 `android/app/build.gradle.kts` 显式写 `minSdk = 26`。

### ⚠️ 关键约束：JDK 版本

**构建只能用 JDK 17（或 21），不能用 JDK 25。** 原因：

- **Gradle 8.14** 最高支持运行在 JDK 24；JDK 25 需要 Gradle 9.1+。
- **AGP 8.11** 官方支持 JDK 17–21。
- Flutter 官方推荐 JDK 17。

这套 Gradle / AGP / Kotlin 版本是 Flutter 3.38.7 脚手架定死、并和 Flutter Gradle 插件一起测过的，不要为了迁就新 JDK 去升级它们。

本机同时装了 JDK 25（留作他用），通过 `flutter config --jdk-dir` 让 Flutter 构建只用 17，两者共存、互不影响。

## 3. 从零搭建构建环境（macOS）

前置：已安装 [Homebrew](https://brew.sh)。

### 3.1 Flutter SDK（所有平台公共）

```bash
brew install --cask flutter
flutter --version   # 确认 3.38.x stable
```

### 3.2 Android 构建环境

#### 步骤 1 — 安装 JDK 17

二选一：

```bash
# 方案 A：免密码（装到 Homebrew 目录）
brew install openjdk@17
#   JDK 路径：/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home

# 方案 B：需输一次管理员密码（.pkg 安装器，装到系统 JVM 目录）
brew install --cask temurin@17
#   JDK 路径：/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home
```

> 本机当前用方案 B（Temurin 17）。查所有已装 JDK：`/usr/libexec/java_home -V`。

#### 步骤 2 — 安装 Android 命令行工具

```bash
brew install --cask android-commandlinetools
```

装到 `/opt/homebrew/share/android-commandlinetools`，这就是 **Android SDK 根目录**；`sdkmanager` 会被链接进 PATH。

#### 步骤 3 — 安装 SDK 组件

```bash
sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0"
```

- `platform-tools` 提供 `adb`。
- `platforms;android-36` + `build-tools;36.0.0` 对应 Flutter 的 `compileSdkVersion = 36`。
- **NDK 与 CMake 不用手动装** —— 首次 `flutter build apk` 会自动下载。

#### 步骤 4 — 让 Flutter 指向 SDK 和 JDK

```bash
flutter config --android-sdk /opt/homebrew/share/android-commandlinetools
flutter config --jdk-dir <步骤 1 选定的 JDK 路径>
```

#### 步骤 5 — 接受 SDK 许可证

```bash
flutter doctor --android-licenses   # 全部输入 y
```

#### 步骤 6 —（可选）把 adb 加入 PATH

`android-commandlinetools` 只把 `sdkmanager` 链接进 PATH，`adb` 没有。要直接用 `adb`，在 `~/.zshrc` 追加：

```bash
export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"
export PATH="$PATH:$ANDROID_HOME/platform-tools"
```

### 3.3 macOS 桌面构建环境

`flutter build macos` 需要**完整版 Xcode**（仅装命令行工具不够）。

```bash
# 1. 从 App Store 安装完整版 Xcode
# 2. 指向 Xcode 并接受许可
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
xcodebuild -runFirstLaunch
# 3. 安装 CocoaPods
brew install cocoapods
```

macOS 沙盒与文件访问权限（entitlements）见技术设计 6.2。

### 3.4 验证

```bash
flutter doctor -v
```

期望 Android 与 Xcode 两项为 `[✓]`：

```
[✓] Android toolchain - develop for Android devices (Android SDK version 36.0.0)
    • Platform android-36, build-tools 36.0.0
    • Java version OpenJDK Runtime Environment Temurin-17.x
    • All Android licenses accepted.
[✓] Xcode - develop for iOS and macOS
```

## 4. 构建

所有构建命令在**项目根目录**执行。`flutter build` 默认产出 release 模式。

### 4.1 Android

| 命令 | 产物 | 用途 |
|---|---|---|
| `flutter build apk` | `build/app/outputs/flutter-apk/app-release.apk` | 单个全架构 APK（~60 MB）|
| `flutter build apk --split-per-abi` | `build/app/outputs/flutter-apk/app-<abi>-release.apk` | 按架构拆分，每个 ~20 MB |
| `flutter build appbundle` | `build/app/outputs/bundle/release/app-release.aab` | 上架 Google Play |

`<abi>` 取值：`armeabi-v7a`（老 32 位）/ `arm64-v8a`（现代手机，主流）/ `x86_64`（模拟器）。

> **首次构建较慢**：会下载 Gradle 8.14、AGP / Kotlin 依赖、NDK、CMake，约几百 MB。之后走缓存。

### 4.2 macOS

```bash
flutter build macos
```

产物：`build/macos/Build/Products/Release/search_reader.app`
（应用名取自 `macos/Runner/Configs/AppInfo.xcconfig` 的 `PRODUCT_NAME`）。

### 4.3 构建模式

| 模式 | 标志 | 说明 |
|---|---|---|
| debug | `--debug` | 带断点 / 热重载，体积大、运行慢 |
| profile | `--profile` | 接近 release 的性能 + 可做性能分析 |
| release | `--release`（`build` 默认）| 上线包，开 AOT 编译与优化 |

### 4.4 清理

构建异常、或切换 Flutter 版本后：

```bash
flutter clean && flutter pub get
```

## 5. 签名

### 5.1 现状

`android/app/build.gradle.kts` 里 release 构建目前用 **debug 密钥**签名：

```kotlin
buildTypes {
    release {
        signingConfig = signingConfigs.getByName("debug")  // TODO: 换正式签名
    }
}
```

证书 DN 为 `CN=Android Debug`。debug 签名的 release APK 能在任意 Android 手机上正常安装运行——**自用、小范围分发足够**。

### 5.2 何时需要正式签名

- 上架 Google Play / 国内应用商店 —— **必须**。
- 长期分发：debug 密钥每台机器不同，换机重新构建会因签名不一致导致**无法覆盖安装**。

### 5.3 切换到正式签名（按需，当前未做）

**步骤 1**　生成 keystore（妥善保管，丢失则无法再更新已上架应用）：

```bash
keytool -genkey -v -keystore ~/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

**步骤 2**　新建 `android/key.properties`（**不要提交进 git**）：

```properties
storePassword=<密码>
keyPassword=<密码>
keyAlias=upload
storeFile=/Users/<你>/upload-keystore.jks
```

**步骤 3**　修改 `android/app/build.gradle.kts`：

```kotlin
import java.util.Properties

// 文件顶部：读取 key.properties
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    // ...
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}
```

**步骤 4**　在 `android/.gitignore` 追加 `key.properties` 与 `*.jks`。

### 5.4 macOS 签名

自用直接运行 `.app` 即可。要分发给别人且不走 App Store，需要 Apple Developer 账号做 codesign + 公证（notarization），否则对方会被 Gatekeeper 拦截。当前未配置。

## 6. 分发

### 6.1 Android

**自用 / 小范围**：

- 把 APK 传到手机（隔空投送、网盘、数据线），点击安装；需在系统设置允许"安装未知来源应用"。
- 或用 adb：`adb install build/app/outputs/flutter-apk/app-release.apk`（手机开 USB 调试 + 连数据线）。
- 用 `--split-per-abi` 分包时，现代手机选 `app-arm64-v8a-release.apk`。

**应用商店**：上传 `app-release.aab`（需先完成 5.3 正式签名）。

### 6.2 macOS

- 自用：双击 `search_reader.app` 运行；首次可能需在"系统设置 → 隐私与安全性"放行。
- 分发：压缩成 `.zip` 或打 `.dmg`。非 App Store 分发要做公证（见 5.4），否则对方需手动右键打开。

## 7. 常见问题排查

| 现象 | 原因 | 解决 |
|---|---|---|
| Gradle 启动报 "Unsupported class file major version" / JVM 版本错误 | 用了 JDK 25 等过新版本 | `flutter config --jdk-dir` 指向 JDK 17 |
| `flutter doctor` 显示了 SDK 路径却报 "Unable to locate Android SDK" | SDK 里没装任何 platform / build-tools | `sdkmanager "platforms;android-36" "build-tools;36.0.0"` |
| 构建报 license not accepted | 未接受 SDK 许可证 | `flutter doctor --android-licenses` |
| `brew install --cask temurin@17` 报 sudo / 需要密码 | cask 用 .pkg 安装器，需管理员密码 | 在交互终端里手动执行，或改用 `brew install openjdk@17` |
| 首次构建长时间卡住 | 在拉 Gradle / 依赖 / NDK | 正常，耐心等；网络差时配代理（`gradle.properties` 加 `systemProp.http.proxyHost` 等）|
| `adb: command not found` | platform-tools 未加入 PATH | 见 3.2 步骤 6 |

## 8. 日常构建速查

环境搭好后，改完代码日常只需：

```bash
flutter pub get                 # 依赖有变动时
flutter analyze                 # 提交前必须无 error（见 02 文档第 10 节）
flutter build apk               # Android 安装包
flutter build macos             # macOS 桌面包
```
