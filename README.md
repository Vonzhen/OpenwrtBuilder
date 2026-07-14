# OpenWrt x86/64 固件构建

本仓库用于通过 GitHub Actions 和 OpenWrt 官方 ImageBuilder 构建定制的 x86/64 固件。

已确定的构建目标：

- 自动选择 OpenWrt `25.12.x` 系列最新正式稳定版（排除 RC）；
- x86/64 `generic` profile；
- ext4 combined EFI 镜像；
- 固定大小的根分区；
- 输出 IMG.GZ、raw IMG、VMDK 和 SHA-256 校验文件；
- 软件包集合严格跟随同版本 OpenWrt 官方 x86/64 manifest；
- 使用签名自定义 APK 仓库，不允许跳过签名验证；
- 首次启动的默认 LAN 管理地址为 `10.10.11.1/24`；
- sysupgrade 保留官方配置、Shinra 配置、自定义仓库和公钥。

所有构建参数统一保存在 `builder/build.env`。`dev` 分支的 push 不构建固件；合并到 `master` 后自动构建，也可在 `master` 上手动触发。

详细执行契约、构建说明和升级验收文档保存在本地 `docs/`，不上传到 GitHub 仓库。

固件覆盖文件位于 `files/`。自定义仓库使用内置公钥完成标准 APK 签名验证。升级只保留第三方包配置，不保留第三方程序本体；升级后可从签名仓库手动重新安装并继续使用原配置。

## 使用原则

- VMDK 只用于首次创建虚拟机；
- 后续升级在 OpenWrt 中上传 IMG.GZ 并保留配置；
- 不使用 VMDK 替换现有系统盘来完成升级；
- VMware 建议使用两块网卡：`eth0` 作为 LAN，`eth1` 通过 NAT/DHCP 作为 WAN；
- 不修改或重新编译 OpenWrt 源码。
