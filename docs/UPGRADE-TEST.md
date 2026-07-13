# 首次部署与升级验收

## 安全与使用边界

- VMDK 只用于首次创建新的虚拟机。
- 已运行的系统必须通过 LuCI 或 `sysupgrade` 上传本项目的 `.img.gz` 升级。
- 禁止用新 VMDK 替换现有系统盘来冒充升级，这不会验证配置保留流程。
- 未签名 APK 可以执行 root 权限安装脚本，只安装来源可信且已经审查的文件。

## 首次部署检查

1. 校验 Artifact 中的 SHA-256 清单。
2. 用 VMDK 创建 EFI 启动的虚拟机，不要转换成 BIOS 启动。
3. 启动后确认 OpenWrt 版本、网络和 LuCI 正常。
4. 使用 `df -h`、`lsblk` 或 `block info` 确认根分区约为 500 MiB。
5. 确认 `/etc/sysupgrade.conf` 包含且仅按项目约定保存 `/etc/shinra/`。

## Shinra 配置保留测试

安装 Shinra 后创建具有明确内容、权限和所有者的测试文件：

```sh
mkdir -p /etc/shinra
printf '%s\n' 'shinra-upgrade-test' > /etc/shinra/upgrade-test.conf
chmod 600 /etc/shinra/upgrade-test.conf
sha256sum /etc/shinra/upgrade-test.conf
stat /etc/shinra/upgrade-test.conf
```

升级前运行：

```sh
sysupgrade -l | grep -F '/etc/shinra/upgrade-test.conf'
```

没有输出时必须停止升级并排查。不得使用 `sysupgrade -n`。

## 使用 IMG.GZ 升级

LuCI 路径：系统 → 备份/升级 → 刷写新的固件。上传本项目生成的 ext4 combined EFI `.img.gz`，确认启用“保留配置”。

SSH 方式：

```sh
sysupgrade /tmp/openwrt-custom-x86-64-efi-<version>.img.gz
```

升级完成后再次记录测试文件的 SHA-256、权限和所有者，并与升级前结果逐项比较。重新安装 Shinra 后再次检查，确认安装过程没有覆盖已有配置。

## LuCI 未签名 APK 对照测试

准备一个仅用于测试、内容已知且未签名的本地 APK。必须使用同一个文件完成以下两组测试：

1. 在未修改的官方 25.12.x 固件或临时移除 `--allow-untrusted` 的对照环境中，通过 LuCI 上传安装，预期失败。
2. 在本项目固件中通过 LuCI 上传安装，预期成功。
3. 确认软件源更新、升级、删除包和官方签名验证未发生额外变化。

LuCI 故障时可以通过 SSH 回退：

```sh
apk add --allow-untrusted /tmp/test-package.apk
```

该命令只是故障回退方式，不能替代 LuCI 功能验收。

## 验收记录

每次正式升级至少记录：

- 旧版本和新版本；
- IMG.GZ SHA-256；
- EFI 启动结果；
- 根分区大小；
- 升级前 `sysupgrade -l` 结果；
- Shinra 测试文件升级前后的 SHA-256、权限和所有者；
- 重新安装 Shinra 后的配置结果；
- LuCI 未签名 APK 成功测试与未修改环境失败对照；
- 网络和 LuCI 基本功能结果。
