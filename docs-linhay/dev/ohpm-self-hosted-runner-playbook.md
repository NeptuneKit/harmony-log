# NeptuneKit 组织级 Self-hosted Runner + OHPM 自动发布实施文档

更新时间：2026-04-01
适用仓库：`NeptuneKit/harmony-log`
目标读者：接手实施的 Codex / DevOps / 发布维护者

## 1. 目标

在 GitHub Actions 中使用组织级 Self-hosted Mac mini Runner，稳定发布 Harmony HAR 包到 OHPM，规避 GitHub Hosted Runner 下 `ohpm publish` 的环境兼容问题。

## 2. 背景结论（已验证）

1. 本机发布可成功（进入 OHPM 审核）。
2. GitHub Hosted Runner（含 `macos-latest`）可跑到发布步骤，但稳定报错：
   - `ohpm ERROR: The "paths[1]" argument must be of type string. Received undefined`
3. 因此本项目发布通道优先切换为组织级 Self-hosted Runner。

## 3. 范围与原则

1. Runner 放在 `NeptuneKit` 组织级，而非单仓库级。
2. 使用独立 Runner Group 控制仓库访问。
3. 发布仅使用专用标签命中，避免被其他 workflow 误占用。
4. 凭据全部走 GitHub Secrets，不入仓库。

## 4. 组织级 Runner 部署（Mac mini）

### 4.1 下载并解压 Runner

```bash
mkdir -p ~/actions-runner && cd ~/actions-runner
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
  PKG=actions-runner-osx-arm64.tar.gz
else
  PKG=actions-runner-osx-x64.tar.gz
fi
curl -L -o "$PKG" "https://github.com/actions/runner/releases/latest/download/$PKG"
tar xzf "$PKG"
```

### 4.2 在组织后台获取注册命令

路径：`NeptuneKit -> Settings -> Actions -> Runners -> New self-hosted runner`

复制页面给出的 `config.sh` 注册命令（带一次性 token）。

### 4.3 注册为组织级 Runner（推荐标签）

```bash
cd ~/actions-runner
./config.sh \
  --url https://github.com/organizations/NeptuneKit \
  --token <ORG_RUNNER_TOKEN> \
  --name macmini-ohpm-01 \
  --labels macmini,ohpm,publish
```

### 4.4 安装为后台服务

```bash
cd ~/actions-runner
sudo ./svc.sh install
sudo ./svc.sh start
```

### 4.5 验证状态

在组织页面确认 `macmini-ohpm-01` 状态为 `Idle`。

## 5. Runner Group 配置

1. 新建 Group：`ohpm-publish`
2. 把 `macmini-ohpm-01` 加入此 Group。
3. Group 权限设为 `Selected repositories`。
4. 至少授权：`NeptuneKit/harmony-log`

## 6. Mac mini 的 Harmony/OHPM 环境准备

## 6.1 安装 Harmony CLI

确保机器具备可用 `ohpm`，并尽量固定版本。

```bash
which ohpm
ohpm -v
```

### 6.2 发布配置（本机验证）

```bash
ohpm config set key_path /Users/<runner-user>/.ohpm/publish_key.pem
ohpm config set publish_id <PUBLISH_ID>
ohpm config set registry https://ohpm.openharmony.cn/ohpm/
ohpm config set publish_registry https://ohpm.openharmony.cn/ohpm/
```

## 7. GitHub Secrets 要求（仓库级）

在 `NeptuneKit/harmony-log` 配置以下 Secrets：

1. `OHPM_PRIVATE_KEY_PEM`
2. `OHPM_KEY_PASSPHRASE`
3. `OHPM_PUBLISH_ID`
4. `OHPM_AUTH_TOKEN`（建议，readWrite）

说明：`OHPM_AUTH_TOKEN` 非理论必需，但在 CI 中可作为稳定兜底认证。

## 8. Workflow 实施要求（给执行 Codex）

需要修改：

1. `.github/workflows/publish-ohpm-manual.yml`
2. `.github/workflows/publish-ohpm.yml`

要求：

1. 发布 Job 使用：

```yaml
runs-on: [self-hosted, macmini, ohpm, publish]
```

2. 保留发布前 HAR 修复逻辑：
   - 注入 `LICENSE`
   - 注入 `readme.md`
   - 注入 `changelog.md`
   - 清理 `._*` 文件
3. 保留 `publish_registry` 配置写入。
4. 保留可选 `OHPM_AUTH_TOKEN` 写入：
   - key: `//ohpm.openharmony.cn/ohpm/:_auth`
5. 保留日志错误识别（出现 `ohpm ERROR` 即失败）。

## 9. 首次验收流程

### 9.1 触发方式

触发 `Publish To OHPM (Manual)`，参数建议：

1. `version=1.0.0`（或新版本）
2. `dry_run=false`
3. `force_rebuild_har=false`（优先复用已验证 HAR）

### 9.2 通过标准（DoD）

1. Job 在 self-hosted runner 上执行。
2. `Publish HAR to OHPM` 步骤成功。
3. 日志出现提交成功/进入审核提示。
4. OHPM 后台可见该版本审核状态。
5. workflow 状态为 `success`。

## 10. 常见故障排查

1. Runner 离线：

```bash
cd ~/actions-runner
sudo ./svc.sh status
sudo ./svc.sh start
```

2. 发布卡认证：检查 Secrets 是否完整、是否有换行污染。
3. 包校验失败（license/readme/changelog）：检查 HAR 注入脚本是否执行。
4. `paths[1]` 异常：优先确认是否误跑到 Hosted Runner；确认 `OHPM_AUTH_TOKEN` 已配置。

## 11. 回滚策略

1. CI 临时不可用时，使用本机发布命令作为兜底：

```bash
ohpm publish dist/harmony_log.har --publish_registry https://ohpm.openharmony.cn/ohpm/
```

2. 保留 workflow 历史，不删脚本，按最小改动回滚 `runs-on`。

## 12. 交接清单（执行完成后必须回传）

1. 实际使用的 runner 名称与标签。
2. workflow run URL。
3. 发布步骤关键日志摘录。
4. 最终结果（成功/失败 + 原因）。
5. 若失败，下一步最小修复项（不超过 3 条）。

## 13. 变更记录模板

```markdown
## [YYYY-MM-DD] <执行人>
- 变更：
- 影响范围：
- 验证：
- 风险：
- 回滚点：
```
