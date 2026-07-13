# OpenWrt 构建项目执行契约

状态：执行中；步骤 7–8 已完成，步骤 3–6 等待真实构建与运行验收
契约版本：1.2
日期：2026-07-13

## 1. 项目目标

在本地建立一个可上传到 GitHub 的仓库，通过 GitHub Actions 使用官方 OpenWrt ImageBuilder 构建 x86/64 固件。

最终提供：

- 500 MiB 根分区的 ext4 combined EFI IMG 压缩固件；
- 从同一 IMG 转换得到的 VMDK 首次部署磁盘；
- SHA-256 校验文件；
- 能够确保本项目固件后续通过 sysupgrade 升级时保留 `/etc/shinra/` 的配置保存规则。
- LuCI“系统 → 软件包”允许上传并安装未签名的本地 APK。

## 2. 已确认决策

| 项目 | 决策 |
|---|---|
| 上游来源 | 仅使用 OpenWrt 官方发布的 ImageBuilder |
| 版本策略 | 自动选择 `25.12.x` 系列版本号最高的正式稳定版，排除 RC 和其他系列 |
| 构建平台 | GitHub Actions，Linux runner |
| 分支策略 | `dev` 用于开发且永不构建；合并到 `master` 后由 push 自动构建，手动构建也只允许 `master` |
| 目标平台 | `x86/64` |
| Profile | `generic` |
| 文件系统 | ext4 |
| 启动方式 | EFI，使用 combined EFI 镜像 |
| 根分区大小 | `ROOTFS_PARTSIZE=500`，单位 MiB |
| IMG | 保留官方构建产生的 `.img.gz`，并可保留解压后的 `.img` |
| VMDK | 使用 `qemu-img` 从同一个 raw IMG 转换 |
| ISO | 不构建 |
| Shinra 程序 | 不内置，升级后另行安装 |
| Shinra 配置 | sysupgrade 保留 `/etc/shinra/` |
| 未签名 APK | 构建时覆盖 LuCI 包管理调用脚本，仅为安装动作加入 `--allow-untrusted` |
| OpenWrt 源码 | 不修改、不重新编译；使用 ImageBuilder `FILES` 覆盖层定制运行时文件 |
| 适用升级范围 | 只保证本项目构建的固件之间升级 |
| 发布方式 | GitHub Actions Artifact；以后可增加 GitHub Release |

## 3. 明确不在本项目范围内

- 不构建或修改 OpenWrt 源码；允许在 ImageBuilder 覆盖层中替换已解析稳定版本的 LuCI 运行时脚本；
- 不自行编译 OpenWrt 软件包；
- 不内置或自动下载 Shinra、sing-box、NPC；
- 不解决其他第三方固件首次迁移到本固件时的配置保存；
- 不制作 ISO、Live CD 或安装器；
- 不自动扩展根分区到虚拟硬盘全部容量；
- 不自动发布到 GitHub，除非用户后续明确要求推送或创建发布。

## 4. 版本与供应链约束

1. 配置文件必须锁定 OpenWrt 发布系列为 `25.12`；构建开始时从官方发布目录自动解析版本号最高的 `25.12.x` 正式版，禁止选择 RC、snapshot 或其他系列。
2. 每次构建必须在日志和产物名称中记录实际解析出的完整版本号，以便追溯该次构建。
3. ImageBuilder 必须从 `downloads.openwrt.org` 官方地址下载。
4. 构建前必须使用同一版本官方 `sha256sums` 校验 ImageBuilder。
5. 已解析版本的官方 LuCI 脚本必须通过 Phase 3 上游哈希和最小差异门禁；上游发生变化时构建必须停止并要求重新审查。
6. GitHub Actions 的第三方 Action 必须锁定到明确版本；能不用第三方 Action 时不使用。
7. 构建产物必须生成 SHA-256 校验文件。
8. 自动解析到新的补丁版本后，必须重新完成完整构建和升级验证；门禁失败时不得自动绕过。

## 5. 计划中的仓库结构

```text
.
├── .github/
│   └── workflows/
│       └── build-openwrt.yml
├── builder/
│   ├── build.env
│   └── build.sh
├── files/
│   ├── etc/
│   │   └── sysupgrade.conf
│   └── usr/
│       └── libexec/
│           └── package-manager-call
├── scripts/
│   └── convert-vmdk.sh
├── docs/
│   ├── OpenWrt构建项目执行契约.md
│   ├── BUILD.md
│   └── UPGRADE-TEST.md
├── .gitignore
└── README.md
```

实际实现允许合并过短的脚本，但不得把版本、目标、分区大小等关键参数散落在多个文件中。

## 6. 构建契约

构建流程必须按以下顺序执行：

1. 读取唯一配置源中的 OpenWrt 发布系列、target、subtarget、profile 和根分区大小；
2. 从官方发布目录解析该系列版本号最高的正式稳定版；
3. 下载该版本官方 x86/64 ImageBuilder、校验清单和 `feeds.buildinfo`；
4. 校验 ImageBuilder SHA-256，不匹配立即失败；
5. 根据 `feeds.buildinfo` 核对官方 LuCI 提交，并验证覆盖脚本只有获准的一处修改；
6. 解压 ImageBuilder；
7. 使用 `PROFILE=generic`、`FILES=.../files`、`ROOTFS_PARTSIZE=500` 生成镜像；
8. 定位 ext4 combined EFI `.img.gz`，匹配不到或匹配多个都必须失败；
9. 解压一份 raw IMG；
10. 从 raw IMG 转换 VMDK；
11. 对最终交付文件生成 SHA-256；
12. 上传为 GitHub Actions Artifact。

不得把 VMDK 作为后续 sysupgrade 上传文件。VMDK 只用于首次创建虚拟机，系统内升级使用 `.img.gz`。

## 7. LuCI 未签名 APK 安装契约

本项目不修改或编译 OpenWrt/LuCI 源码，也不要求用户在每次安装固件后手工修改系统文件。采用 ImageBuilder 的 `FILES` 覆盖层，在固件中预置：

```text
/usr/libexec/package-manager-call
```

该文件必须来源于构建时解析出的 OpenWrt 版本对应的官方 LuCI 文件，只允许对 APK 的“安装本地包”路径加入：

```text
--allow-untrusted
```

预期修改与以下语义等价：

```text
action="add"
→
action="add --allow-untrusted"
```

但实现不得仅凭这段示例进行字符串替换。必须先检查锁定版本官方脚本的真实参数拼接方式，再制作最小变更；若官方脚本结构不匹配预期，构建必须失败并要求重新审查。

约束如下：

- 只影响 LuCI 上传本地 APK 的安装动作；
- 不给软件源更新、系统升级、删除包等其他操作附加该参数；
- 不修改 `apk` 全局信任配置；
- 不删除或替换官方仓库签名校验；
- 覆盖后的文件权限必须与官方文件一致并保持可执行；
- 每次自动解析到新的 OpenWrt 版本都必须重新与该版本官方脚本对比，禁止静默沿用不匹配的旧脚本；
- 必须同时保留 SSH 命令安装作为故障回退方式。

该功能意味着任何能够登录 LuCI 并获得软件包安装权限的管理员，都可以安装未签名且能以 root 权限执行安装脚本的 APK。这是本项目明确接受的安全取舍，不代表这些 APK 可信。

## 8. Shinra 配置保存契约

每一版固件必须内置：

```text
/etc/sysupgrade.conf
```

其中至少包含：

```text
/etc/shinra/
```

如后续确认 Shinra 使用 `/etc/config/shinra`，再将该路径加入保存清单；没有证据前不扩大保存范围。

升级时必须：

- 使用 LuCI 的“保留配置”升级，或使用不带 `-n` 的 `sysupgrade`；
- 上传本项目生成的 ext4 combined EFI `.img.gz`；
- 升级前确认 `sysupgrade -l` 输出包含 Shinra 配置文件；
- 升级后重新安装 Shinra；
- 依赖 Shinra 自身“检测到 `/etc/shinra` 已存在则不覆盖”的行为。

## 9. 分步执行计划与验收条件

### 步骤 0：冻结契约

状态：**已完成**

验收条件：目标、范围、格式、分区大小和配置保存方式已写入本文档。

### 步骤 1：建立仓库骨架与集中配置

状态：**已完成**

工作内容：建立目录、README、忽略规则和 `builder/build.env`。

验收条件：所有可变参数都有唯一配置来源；仓库中没有固件二进制或临时构建目录。

### 步骤 2：加入 Shinra sysupgrade 保存规则

状态：**已完成**

工作内容：建立 `files/etc/sysupgrade.conf`，写入 `/etc/shinra/`。

验收条件：文件路径与内容准确；通过 `FILES` 注入镜像和镜像内验证归入步骤 4 的构建验收。

### 步骤 3：加入 LuCI 未签名 APK 安装支持

状态：**执行中（本地实现与静态验证已完成，等待固件内运行验收）**

工作内容：取得当前稳定版本对应的官方 `package-manager-call`，核对真实调用结构，制作最小修改并放入 ImageBuilder 覆盖层。

验收条件：

- 与官方原文件的差异仅包含安装动作所需的 `--allow-untrusted`；
- 脚本语法和可执行权限正确；
- 普通官方仓库操作不受影响；
- LuCI 上传未签名测试 APK 可以安装；
- 去掉 `--allow-untrusted` 后同一个未签名测试包应安装失败，用于证明测试有效。

### 步骤 4：实现官方 ImageBuilder 构建脚本

状态：**执行中（本地实现与静态验证已完成，尚未真实构建）**

工作内容：下载、校验、解压并调用 ImageBuilder，设置 `ROOTFS_PARTSIZE=500`。

验收条件：错误均能导致非零退出；生成且只生成目标 ext4 combined EFI 固件匹配结果。

### 步骤 5：实现 VMDK 转换与校验文件

状态：**执行中（本地实现与模拟验证已完成，等待真实构建验收）**

工作内容：解压 raw IMG，以 `qemu-img` 转换 VMDK并生成 SHA-256。

验收条件：`qemu-img info` 能识别 VMDK；IMG、IMG.GZ、VMDK 均进入校验清单。

### 步骤 6：实现 GitHub Actions 工作流

状态：**执行中（本地实现与静态验证已完成，等待 GitHub 首次运行）**

工作内容：安装必要工具、运行统一构建脚本、上传 Artifact。

验收条件：工作流支持手动触发；构建逻辑不在 YAML 和本地脚本中重复实现；失败不会上传伪成功产物。

### 步骤 7：补齐使用与升级测试文档

状态：**已完成**

工作内容：记录首次用 VMDK 部署、LuCI/SSH 上传 IMG.GZ 升级、Shinra 配置验证方法。

验收条件：文档明确禁止用替换 VMDK 的方式代替 sysupgrade。

### 步骤 8：本地静态验证

状态：**已完成**

工作内容：检查脚本语法、路径、参数传递、工作流 YAML 和产物选择逻辑。

验收条件：本地可执行检查全部通过；如本机环境不具备 Linux ImageBuilder 条件，清楚记录未执行项，不能声称完整构建成功。

### 步骤 9：GitHub 首次真实构建

状态：**等待仓库上传后执行**

工作内容：用户将代码上传 GitHub 后手动运行工作流。

验收条件：Actions 成功；Artifact 中包含预期 IMG.GZ、IMG、VMDK 和 SHA-256；无意外格式。

### 步骤 10：虚拟机启动与跨版本升级验收

状态：**等待真实构建后执行**

工作内容：以 VMDK 首次启动，创建 Shinra 测试配置，再用下一次 IMG.GZ 执行保留配置升级。

验收条件：

- 系统显示根分区约为 500 MiB；
- EFI 正常启动；
- 升级前 `sysupgrade -l` 可见 `/etc/shinra` 文件；
- 升级后 `/etc/shinra` 内容、权限和所有者保持一致；
- 重新安装 Shinra 后配置未被覆盖；
- OpenWrt 网络与 LuCI 正常。

## 10. 进度更新规则

从开始实现代码起，每完成一个步骤必须同时完成三项动作：

1. 将本文档对应步骤从“待开始”改为“已完成”；
2. 在下方进度记录中追加日期、结果、验证证据和遗留问题；
3. 在对话中向用户报告已完成内容、验证结果和下一步。

步骤尚未通过验收时不得标记完成。若受外部条件限制，只能标记为“受阻”并记录原因。

## 11. 停止与失败条件

发生以下任一情况必须停止当前步骤，不得静默绕过：

- 官方 ImageBuilder 校验失败；
- 指定的 OpenWrt 官方版本或 x86/64 ImageBuilder 不存在；
- ImageBuilder 未生成 ext4 combined EFI 镜像；
- 目标镜像匹配到多个候选文件；
- raw IMG 或 VMDK 无法识别；
- 根分区不是约定的 500 MiB；
- 构建出的固件未包含 `/etc/sysupgrade.conf` 或缺少 `/etc/shinra/`；
- 锁定版本官方 `package-manager-call` 的结构与补丁预期不一致；
- 覆盖文件与官方原文件存在超出允许安装未签名 APK 范围的差异；
- LuCI 未签名 APK 安装测试或对照测试结果不符合预期；
- sysupgrade 备份列表中没有实际 Shinra 配置；
- 升级后 Shinra 配置内容或权限发生非预期变化。

## 12. 进度记录

| 日期 | 步骤 | 状态 | 验证证据或备注 |
|---|---|---|---|
| 2026-07-13 | 步骤 0：冻结契约 | 已完成 | 已确定官方 ImageBuilder、x86/64、EFI、ext4、500 MiB、IMG.GZ + VMDK、保留 `/etc/shinra/`；ISO 已排除 |
| 2026-07-13 | 契约变更 1.1 | 已完成 | 增加 LuCI 上传未签名 APK 支持；采用 ImageBuilder 覆盖层，不修改 OpenWrt 源码，不在安装后手工修改 |
| 2026-07-13 | 步骤 1：仓库骨架与集中配置 | 已完成 | 已建立 README、忽略规则、预定目录和 `builder/build.env`；构建参数各自仅定义一次；锁定的官方 25.12.5 x86/64 ImageBuilder 下载目录已确认存在；仓库内固件二进制数量为 0 |
| 2026-07-13 | 仓库迁移至 `D:\ProgramData\OpenwrtBuilder` | 已完成 | 自动迁移受权限限制未能执行，用户已手动将仓库迁移到目标目录；后续工作以该目录为准 |
| 2026-07-13 | 契约纳入版本管理 | 已完成 | 执行契约已从被忽略的 `outputs/` 移至 `docs/`，README 已增加契约入口 |
| 2026-07-13 | Git 初始化 | 已完成 | 已在目标目录初始化 Git 仓库，默认分支按用户要求调整为 `master`；尚未创建首次提交或配置远程仓库 |
| 2026-07-13 | 步骤 2：Shinra sysupgrade 保存规则 | 已完成 | 已建立 `files/etc/sysupgrade.conf`，内容严格为 `/etc/shinra/`；README 已说明其用途；待步骤 4 通过 ImageBuilder `FILES` 参数注入并做镜像内验证 |
| 2026-07-13 | 步骤 3：LuCI 未签名 APK 支持 | 执行中 | 25.12.5 官方 `feeds.buildinfo` 将 LuCI 锁定到提交 `128a7812f4be233c5dd7f7466f534fd888785caf`；官方脚本 SHA-256 为 `3cb9f991ce4ca92ef4c394ae663e513e3154ac9984806118cc061c735c2eb1f5`。覆盖文件与官方原文仅有 `action="add"` 改为 `action="add --allow-untrusted"` 一处语义差异；Shell 语法与 LF 换行已通过静态检查。真实未签名 APK 安装及去掉参数后的失败对照测试须等待固件构建后执行，步骤暂不标记完成 |
| 2026-07-13 | 契约变更 1.2 | 已完成 | 版本策略改为固定 `25.12` 发布系列并自动选择最高稳定补丁版；排除 RC、snapshot 和其他系列；实际完整版本写入日志与产物名，LuCI 上游门禁继续强制执行 |
| 2026-07-13 | 步骤 4：ImageBuilder 构建脚本 | 执行中 | 已实现版本解析、官方文件下载、ImageBuilder SHA-256 校验、LuCI 上游一致性门禁、解压、ImageBuilder 参数传递和唯一镜像选择；Shell 语法、LF 换行及模拟版本解析通过。按照 dev 分支不构建的约束，尚未下载 ImageBuilder 或执行真实构建，因此暂不标记完成 |
| 2026-07-13 | 步骤 5：VMDK 与校验文件 | 执行中 | 已实现 IMG.GZ 完整性检查、raw IMG 解压与识别、`qemu-img` VMDK 转换与识别，以及 IMG.GZ、IMG、VMDK 三项 SHA-256 清单；已使用模拟 `qemu-img` 跑通全流程并通过 `sha256sum -c`。真实 VMDK 格式仍须在 master 构建中用真实 `qemu-img` 验收，步骤暂不标记完成 |
| 2026-07-13 | 步骤 6：GitHub Actions | 执行中 | 已实现 `master` push 和手动触发入口，job 额外限制为 `refs/heads/master`，因此 `dev` 不会构建；工作流安装依赖后只调用统一的 `builder/build.sh`，产物不存在时上传步骤失败。官方 `actions/checkout` v7.0.0 与 `actions/upload-artifact` v7.0.1 均锁定完整提交 SHA。尚未在 GitHub 运行，步骤暂不标记完成 |
| 2026-07-13 | 步骤 7：使用与升级文档 | 已完成 | 已建立 `docs/BUILD.md` 和 `docs/UPGRADE-TEST.md`；覆盖 dev/master 规则、Artifact、VMDK 首次部署、IMG.GZ sysupgrade、禁止替换 VMDK、Shinra 内容/权限/所有者核对、LuCI 未签名 APK 成功与失败对照及 SSH 回退方式 |
| 2026-07-13 | 步骤 8：本地静态验证 | 已完成 | actionlint 1.7.12 检查工作流通过；ShellCheck 0.11.0 检查自有构建与转换脚本通过；三个 Shell 文件语法通过；模拟版本解析正确排除 RC 并选择最高补丁版；无稳定版本和输入缺失均按预期失败；模拟 IMG.GZ→IMG→VMDK 与三项 SHA-256 校验通过；LuCI 覆盖与官方原文仅一处允许差异；Action 完整 SHA、LF 换行、Git 差异和 sysupgrade 路径检查通过。本机未执行真实 ImageBuilder、真实 qemu-img、固件启动、LuCI APK 或 sysupgrade 测试，这些分别保留给步骤 9–10，未宣称完整构建成功 |

## 13. 完成定义

只有同时满足以下条件，项目才可宣布完成：

- 本地仓库结构和构建代码完整；
- GitHub Actions 至少完成一次真实构建；
- 交付格式和 SHA-256 正确；
- VMDK 能以 EFI 启动；
- 根分区大小验证通过；
- 至少完成一次本项目固件到下一版的 sysupgrade；
- Shinra 配置在升级前后验证一致；
- LuCI 可以上传并安装未签名 APK，且修改范围通过官方文件差异审查；
- README 和升级测试文档足以让用户重复整个过程。
