# OpenWrt x86/64 固件构建

本仓库用于通过 GitHub Actions 和 OpenWrt 官方 ImageBuilder 构建定制的 x86/64 固件。

已确定的构建目标：

- 自动选择 OpenWrt `25.12.x` 系列最新正式稳定版（排除 RC）；
- x86/64 `generic` profile；
- ext4 combined EFI 镜像；
- 固定大小的根分区；
- 输出 IMG.GZ、raw IMG、VMDK 和 SHA-256 校验文件；
- sysupgrade 时保存 `/etc/shinra/`；
- 允许通过 LuCI 上传并安装未签名的本地 APK。

所有构建参数统一保存在 `builder/build.env`。当前已完成仓库骨架、Shinra 配置保存文件、LuCI 未签名本地 APK 安装覆盖、ImageBuilder 构建流程、VMDK 转换流程和 GitHub Actions 工作流的本地实现。`dev` 分支的 push 不构建固件；合并到 `master` 后自动构建，也可在 `master` 上手动触发。真实固件构建与运行验收将在 GitHub Actions 中执行。

项目范围、验收条件和实时进度以 [`docs/OpenWrt构建项目执行契约.md`](docs/OpenWrt构建项目执行契约.md) 为准。

- 构建、分支和 Artifact 说明：[`docs/BUILD.md`](docs/BUILD.md)
- 首次部署与升级验收：[`docs/UPGRADE-TEST.md`](docs/UPGRADE-TEST.md)

固件覆盖文件位于 `files/`。其中 `files/etc/sysupgrade.conf` 要求 sysupgrade 保存 `/etc/shinra/`，用于本项目固件之间保留 Shinra 配置。

## 使用原则

- VMDK 只用于首次创建虚拟机；
- 后续升级在 OpenWrt 中上传 IMG.GZ 并保留配置；
- 不使用 VMDK 替换现有系统盘来完成升级；
- 不修改或重新编译 OpenWrt 源码。
