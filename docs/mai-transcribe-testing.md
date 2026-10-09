# MAI Transcribe 接入与真实服务测试

测试日期：2026-10-09。开发分支：`codex/mai-transcribe-streaming`。

## 范围与安全

实测使用设置中的现有 Azure 凭据，读取后仅保留在内存中，不打印 Key。通过 macOS `say` 的 Tingting 和 Samantha 生成短中文、英文音频，转换为 16kHz 单声道 PCM16 WAV。

测试脚本复用生产 `MAITranscribeBatchClient` 和 `MAITranscribeSpeechProvider`，不读取或上传历史录音、不调用麦克风、不操作剪贴板、不修改用户设置、不创建部署。实测会产生服务按量费用，临时音频与程序在结束时删除。本轮在用户明确授权后，通过 Azure CLI 单独创建了下述流式部署，未更改其他部署。

## MAI-Transcribe-2 非流式

在现有 `swedencentral` 区域资源调用 Speech Fast Transcription：

- 路径：`/speechtotext/transcriptions:transcribe?api-version=2025-10-15`
- 认证：`Ocp-Apim-Subscription-Key`
- `enhancedMode.enabled=true`，`enhancedMode.model=MAI-Transcribe-2`
- `modelOptions.timestamps=none`，分别验证 `verbatim` 与 `clean`

| 用例 | 结果 | 请求至完整最终文本耗时 |
| --- | --- | --- |
| 中文、自动语言、Verbatim | 通过 | 2.45 秒 |
| 英文、`en` 提示、Clean | 通过 | 0.68 秒 |
| 中文、`zh` 提示、术语列表 | 通过 | 0.40 秒 |
| 英文、自动语言、Verbatim | 通过 | 0.44 秒 |

中文最终文本：`你好，这是语音输入测试，微软模型正在识别中文。`

英文最终文本：`Hello, this is an Azure speech recognition test. The weather is clear today.`

耗时仅是这些合成短音频的单次测量，不是模型排名、稳定延迟保证或麦克风到粘贴的端到端延迟。上述用例验证参数被服务接受和最终文本匹配音频，不代表覆盖所有语言或证明 Clean 对填充词的清理效果。

## MAI-Transcribe-2-Streaming

真实 WebSocket 已连接到现有 Foundry 资源并收到服务端响应。第一次配置按微软文档发送 `language:null`，服务网关返回语言类型错误；生产代码与回归测试现已改为自动语言时省略该字段。

创建部署前继续真实请求，中文用例配置超时，英文用例收到 `PCM input rate must be 24000, or 16000 for MAI transcription`。这些请求没有得到 `session.updated` 和完整的转写结果，不能将其或协议单元测试视为真实转写成功。

随后通过 Azure CLI 只读检查确认资源没有 MAI Transcribe 部署。用户批准创建后，在现有 `swedencentral` Foundry 资源创建：

- 部署名称：`mai-transcribe-2-streaming`（与应用默认部署名称一致）
- 模型：`MAI-Transcribe-2-Streaming`
- 模型版本：`2026-08-06`
- SKU：`GlobalStandard`，capacity `1`
- Azure 返回状态：`Succeeded`

部署就绪后再次运行生产 Provider 的真实服务测试：

```bash
./scripts/test-mai-transcribe-live.sh streaming
```

| 用例 | 结果 | 连接开始至最终文本耗时（包含按实时速度发送音频） |
| --- | --- | --- |
| 中文、自动语言 | 通过 | 8.24 秒 |
| 英文、自动语言 | 通过 | 7.67 秒 |

两个用例均完成 `session.updated` 握手，持续输出多个实时部分结果，并在显式提交后收到 `completed` 的完整最终文本。最终文本分别与上述中文、英文合成音频一致，测试退出码为 `0`。先前的配置超时和采样率错误在创建部署后未再出现。

上述流式耗时包含连接配置、以 20 ms 帧按实时速度发送音频以及等待最终结果，不是纯推理时间，不能与非流式上传耗时直接比较，也不包含真实麦克风采集或粘贴。应用中的 MAI Endpoint 和 Key 尚未自动写入；使用时仍需在设置中填写该 Foundry 资源地址和对应 Key。

## 回归入口

```bash
./scripts/test-mai-transcribe.sh
./scripts/test-azure-refinement.sh
./scripts/test-mai-transcribe-live.sh all
```

`test-mai-transcribe.sh` 覆盖配置和认证、原始音频转换、预览后缀替换、顺序提交、延迟最终结果、multipart、HTTP 错误、响应解析、超时与取消；`test-azure-refinement.sh` 检查原有 Azure Speech 精修行为。

本轮两组离线回归均通过；运行 XcodeGen、`pod install` 后，使用 `.xcworkspace` 的 Debug 与 Release 构建均成功（`CODE_SIGNING_ALLOWED=NO`）。菜单栏图标存在未分配图片的原有资源警告，本次未修改该资源。

随后根据用户手动测试请求，重新构建 x86_64 / arm64 双架构 Release，并使用本地 ad-hoc 签名，保留 Sandbox、麦克风与网络客户端 entitlements。签名校验通过后退出旧版，将原 app 移至 `~/Library/Application Support/OpenTypeless/AppBackups/` 的时间戳子目录，替换 `/Applications/OpenTypeless.app` 并重新启动。已校验安装后的签名、可执行文件与构建产物一致，以及新进程从 `/Applications/OpenTypeless.app` 启动。未改动用户设置或历史数据。

初次手动测试安装沿用 `0.3.0` / build `3`。用户随后确认手动测试通过，并要求完成 GitHub 上线；本轮开发已结束，发布版本更新为 `0.4.0` / build `4`，同步更新应用内版本历史及中英文 README 版本标记。

最终 `0.4.0` 发布构建重新通过 MAI 与 Azure Speech 精修离线回归、四项非流式及两项流式真实 Azure 测试，以及 Workspace Debug/Release 构建。双架构 Release 采用本地 ad-hoc 签名（关闭额外基础 entitlements 注入），签名校验通过。发布说明见 `docs/releases/v0.4.0.md`。

本机 `/Applications/OpenTypeless.app` 已同步更新为 `0.4.0` / build `4` 并重新启动，保留原测试包备份及现有设置、历史数据。已确认安装 bundle、发布构建和应用内版本历史的版本号一致。GitHub 安装包使用同一 Release 产物，并提供 SHA-256 校验文件。

替换 app bundle 后，手动测试前应在「系统设置 > 隐私与安全性 > 辅助功能」移除旧 OpenTypeless 条目，重新添加 `/Applications/OpenTypeless.app` 并启用，再重启应用；否则识别成功后可能无法粘贴到光标处。没有自动修改 macOS 安全设置。

## 官方参考

- [MAI Transcribe 非流式模型与参数](https://learn.microsoft.com/azure/ai-services/speech-service/mai-transcribe)
- [MAI Streaming Realtime 协议与部署要求](https://learn.microsoft.com/azure/ai-services/speech-service/mai-transcribe-2-streaming-realtime)
- [Speech Fast Transcription REST API](https://learn.microsoft.com/rest/api/speechtotext/transcriptions/transcribe?view=rest-speechtotext-2025-10-15)
