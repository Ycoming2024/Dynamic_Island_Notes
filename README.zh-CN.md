# Notes Bridge (简体中文)

Notes Bridge 是一个跨平台笔记与提醒项目。

## 技术栈

- 客户端: Flutter (Windows、Android)
- 服务端: NestJS + Prisma + SQLite
- 通知: 本地通知 + Windows 自定义灵动岛样式浮层

## 目录结构

- `apps/flutter_app`: Flutter 客户端
- `server`: 后端 API 与数据层
- `docs`: 额外文档（schema/部署说明）
- `run_build_windows.bat`: Windows 一键打包
- `run_android_apk.bat`: Android APK 一键打包

## 隐私与开源处理

此开源版本已做脱敏处理:

- 不包含私有 `.env`
- 不包含运行缓存/构建产物
- 已移除个人域名与品牌信息，改为通用占位值

## 快速开始

### 1) 启动后端

```bash
cd server
cp .env.example .env
npm ci
npx prisma generate
npm run build
npm run start:prod
```

本地默认 API 地址: `http://127.0.0.1:3000`
默认前缀: `/v1`

### 2) 运行 Flutter (Windows)

```bash
cd apps/flutter_app
flutter pub get
flutter run -d windows --dart-define=API_BASE_URL=http://127.0.0.1:3000 --dart-define=API_PREFIX=/v1
```

### 3) 运行 Flutter (Android)

```bash
flutter run -d android --dart-define=API_BASE_URL=http://10.0.2.2:3000 --dart-define=API_PREFIX=/v1
```

## 打包

在仓库根目录执行:

- Windows: `run_build_windows.bat`
- Android APK: `run_android_apk.bat`

脚本中的 API 默认值可按需修改。

## 许可证

MIT，详见 `LICENSE`。
