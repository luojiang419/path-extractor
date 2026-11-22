# 路径提取器

Windows 桌面版路径提取工具，基于 Flutter 构建。

## 仓库内容

- `path_extractor_browser/`：Flutter 桌面应用源码
- `installer/`：Inno Setup 安装包脚本与构建辅助脚本
- `.github/workflows/`：GitHub Actions 发布流程

## 发布流程

1. 更新 `path_extractor_browser/pubspec.yaml` 中的 `version`
2. 提交并推送 `main`
3. 创建并推送 `vX.Y.Z` tag
4. GitHub Actions 自动执行测试、构建、打包并发布 GitHub Release

## 自动更新

客户端启动后会检查 GitHub Release 的 `latest.json` 清单；若发现新版本，会下载最新安装包并提示关闭程序后安装。
