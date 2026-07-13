# 构建与交付说明

## 分支与触发规则

- `dev` 是开发分支，push 不触发固件构建。
- `master` 是构建分支，push 或合并到该分支后自动构建。
- GitHub Actions 支持手动触发，但只有选择 `master` 时构建 job 才会运行。
- 本项目不自动创建 GitHub Release，只上传 GitHub Actions Artifact。

## 构建配置

所有可变构建参数集中在 `builder/build.env`。当前策略固定 OpenWrt `25.12` 发布系列，构建开始时从 OpenWrt 官方发布目录选择版本号最高的正式 `25.12.x`，不会选择 RC、snapshot 或其他系列。

每次构建都会把解析出的完整版本号写入产物名称。若新版官方 LuCI `package-manager-call` 与已审查版本不一致，构建会停止，必须重新完成 Phase 3 差异审查，不能跳过门禁。

## GitHub 构建

1. 将代码推送到 `dev`，确认 Actions 没有执行固件构建。
2. 审查并将 `dev` 合并到 `master`。
3. 在仓库的 Actions 页面查看 `Build OpenWrt firmware`。
4. 等待构建与 Artifact 上传全部成功。
5. 下载名为 `openwrt-x86-64-efi` 的 Artifact。

也可以在 Actions 页面手动运行工作流，但分支必须选择 `master`。

## 交付文件

以实际解析版本 `25.12.5` 为例，Artifact 应包含：

```text
openwrt-custom-x86-64-efi-25.12.5.img.gz
openwrt-custom-x86-64-efi-25.12.5.img
openwrt-custom-x86-64-efi-25.12.5.vmdk
openwrt-custom-x86-64-efi-25.12.5.sha256sums
```

- `.vmdk` 只用于首次创建虚拟机。
- `.img.gz` 用于 OpenWrt 中的后续 sysupgrade。
- `.img` 是解压后的 raw 磁盘镜像，供检查和转换使用。
- `.sha256sums` 必须同时覆盖上述三个镜像文件。

在 Linux 中验证：

```sh
sha256sum -c openwrt-custom-x86-64-efi-*.sha256sums
qemu-img info openwrt-custom-x86-64-efi-*.vmdk
```

## 本地构建

本地需要 Linux、`qemu-img`、`zstd`、GNU 构建工具及 OpenWrt ImageBuilder 的常规依赖。在仓库根目录运行：

```sh
./builder/build.sh
```

最终文件写入 `dist/`。构建脚本会自动下载和校验官方 ImageBuilder，不接受未通过官方 SHA-256 校验的归档。

仅查看将要使用的稳定版本，不下载 ImageBuilder：

```sh
./builder/build.sh --resolve-version
```

## 常见失败

- 找不到稳定版：检查 OpenWrt 官方发布目录和网络访问。
- ImageBuilder 校验失败：停止使用已下载文件，不要绕过校验。
- LuCI 上游哈希变化：重新核对新版官方脚本并更新 Phase 3 覆盖。
- 目标 IMG.GZ 为零个或多个：检查 ImageBuilder 输出命名，禁止随意选择候选文件。
- VMDK 无法识别：保留日志并停止交付。
- Artifact 上传提示没有文件：以前序构建日志为准，不能把该次运行视为成功。
