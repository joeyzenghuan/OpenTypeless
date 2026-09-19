# Azure 实时识别笔记：Recognizing、Recognized 与 PostRefinement

整理日期：2026-09-19。对应 OpenTypeless 0.3.0（build 3），Microsoft Speech SDK 1.51.2。

## 1. 开关 Post 后，Azure 分别返回什么？

两种模式使用相同的事件接口。差别在于最终文本如何产生，而不是多出一类事件。

| 事件与结果原因 | Post 关闭：标准识别 | Post 开启：最终精修 |
| --- | --- | --- |
| `Recognizing` / `RecognizingSpeech` | 当前语音段的中间假设，可能反复变化 | 同样提供低延迟的中间假设 |
| `Recognized` / `RecognizedSpeech` | 当前语音段的标准最终文本 | 当前语音段经第二遍识别后的最终文本 |
| `Recognized` / `NoMatch` | 没有得到可用识别结果，不能当作成功的 final | 同左 |
| `SessionStopped` | 整个识别会话已结束 | 同左 |

原生 Speech SDK 不用字面上的 `[done]` 标签表达完成。`Recognized` 表示**一个语音段**完成，`SessionStopped` 表示**整次会话**结束。连续识别中，一次录音可以收到多次 `Recognized`。

标准最终文本本来就可能改字、补标点、调整格式，因此关闭 Post 后也值得展示“中间 → 最终”的变化。但这些变化本身不能证明标准模式额外调用了大语言模型。

微软对 PostRefinement 的描述是：第二遍识别与实时流并行运行，利用更完整的音频上下文，替换每段的最终结果；中间结果保持低延迟。它并非必须等整次录音停止后才开始工作。SDK **不会为同一段分别提供一份标准 final 和一份 Post final**，也没有额外的“精修完成”事件。

因此，App 上下两行展示的是“实时预览”和“当前模式的最终结果”。这个对照能让用户看到最终定稿的变化，但不能把所有变化都归功于 Post。要单独评估 Post 的收益，需要对同一份音频分别运行标准和 Post 模式。短句可能完全相同；本次少量测试不能推导整体准确率提升幅度。

`TrueText` 是同一个后处理属性的另一个值，用于标点、大小写等显示格式处理，不能与 `PostRefinement` 同时设置。当前 App 关闭 Post 时使用标准默认配置，没有显式启用 `TrueText`。

## 2. 中间文本是整段假设，不是增量 token

例如当前这一句可能依次收到：

```text
Recognizing: 看一
Recognizing: 看一下
Recognizing: 看一下有什么亮点
Recognized:  看一下有什么亮点。
```

每次 `Recognizing` 应替换这一段的草稿，不能把四次回调直接拼成“看一看一下看一下有什么亮点……”。如果还有之前已经完成的句子，应保留之前的句子，只更新当前段。

在 Swift SDK 中，两种事件都可以从 `event.result.text` 读取文本；还应检查 `reason`，以及 `offset`、`duration` 等信息。App 通过 SDK 对象处理结果，下面的 JSON 用于解释底层结果属性，不是 App 自定义的网络协议。

本轮对同一份合成语音的实际 SDK 回调做了记录，删去 ID 等字段后如下。

两种模式均出现的中间结果：

```json
{"Text":"看一下有什么亮点","Offset":700000,"Duration":16400000}
```

标准模式的最终结果（simple 格式）：

```json
{"RecognitionStatus":"Success","DisplayText":"看一下有什么亮点。","Offset":700000,"Duration":16400000}
```

Post 模式的最终结果：

```json
{"RecognitionStatus":"Success","DisplayText":"看一下有什么亮点。","Offset":1100000,"Duration":26000000}
```

这些是实测样例，不是每次回调都固定具有相同时间值的契约。详细输出模式还可能提供候选结果、置信度等信息，当前 App 的这条路径不依赖这些扩展字段。

`Offset` 和 `Duration` 的单位是 100 纳秒，即 10,000,000 ticks = 1 秒，描述音频时间位置与长度，**不是网络等待时间或精修耗时**。中间到最终结果的起点可能变化，结果 ID 也可能变化，因此不能仅凭相同 ID 或完全相等的 offset 匹配一段。

## 3. 说两句话，中间停顿两秒

假设一次按住快捷键期间说：

```text
A：看一下有什么亮点。
（停顿两秒）
B：第二句话，请检查最终精修是否完整。
```

连续识别通常形成两个语音段，仍然属于一次会话。两种模式的示意顺序相同：

```text
SessionStarted
  Recognizing(A) × 多次
  Recognized(A)        ← 标准 final 或 Post final
  Recognizing(B) × 多次
  Recognized(B)        ← 标准 final 或 Post final
SessionStopped
```

这不是固定的到达顺序承诺：如果 A 的最终结果较慢，B 的中间结果可能先到；各段中间回调次数也不固定。两秒停顿通常足以分段，但具体由服务的静音检测和配置决定，不保证每次按两秒切分。微软文档将 500ms 描述为常见的默认分段静音时长；本 App 没有覆盖分段静音超时参数。

本轮把两句合成语音之间插入两秒静音，分别测试标准和 Post，均收到两段最终结果，组合文本一致：

```text
看一下有什么亮点。第二句话，请检查最终精修是否完整。
```

文件输入测试的回调速度不代表真人边说边传时的端到端延迟。

## 4. OpenTypeless 如何处理和展示

`AzureSpeechProvider` 接收 SDK 事件；`AzureSpeechSession` 为每次录音独立保存和合并语音段。状态更新串行处理，按音频位置排序，同一段的预览被新预览替换，最终文本单独保留。

考虑到 offset 会漂移，当前实现还参考音频区间是否显著重叠（至少覆盖较短区间的一半）来匹配预览与最终结果，同时保护相邻的已完成段。该规则是 App 的合并策略，不是 Azure 提供的稳定段 ID 保证。重复、过期或已结束会话的回调不会再次触发输出。

两种模式都显示上下两行：

| 位置 | 标准模式 | Post 模式 |
| --- | --- | --- |
| 上方 | 实时预览 · 中间结果 | 实时预览 · 中间结果 |
| 下方 | Azure 标准识别 · 最终结果 | Azure 精修 · 最终结果 |

说到 B 时，上方保留 A 最后一次预览并更新 B 的预览，下方保留 A 已完成的最终文本；B 最终完成后再累积到下方。上方保留的是收到的最后一次预览，它有时比最终文本短，并非必定是一份完整草稿。

开启额外的 AI 润色时，服务最终结果与 AI 输出分开显示。Azure Post 属于 Speech 服务本身，不需要另配 Azure OpenAI；App 的可选 AI 润色是之后的独立步骤。

当前历史记录在开启 Post 时保存预览与精修对照及降级原因；标准模式本轮增加的是浮窗双行展示，没有同时扩展历史预览字段的保存范围。

## 5. 为什么关闭 Post，松开时仍会“等待最终结果”？

松开快捷键时，最后一段可能仍处于 `Recognizing`。App 必须结束输入并等待最后的 `Recognized`，不能把当前草稿直接当作完整成功结果。正常完成还会等待 `SessionStopped` 和 SDK 停止调用返回，以避免遗漏尾句。

这个等待在标准模式同样必要，不代表 App 暗中开启了 Post 或额外 AI 润色。当前实现最多等待 20 秒，不再用固定的 200ms 延迟猜测 Azure 是否已经完成。

## 6. 最后写入剪贴板和光标的到底是哪一份？

| 情况 | 输出内容 |
| --- | --- |
| 标准模式成功 | 按顺序合并的标准最终文本 |
| Post 模式成功 | 按顺序合并的精修最终文本 |
| 上述成功后另开启 AI 润色，且润色成功 | 在服务最终文本基础上的 AI 输出 |
| Post 缺少 final、超时或特定可恢复服务/连接错误 | 已完成段保留 final；未完成段使用已有预览，明确标记降级 |
| 用户取消、配置错误、不可恢复错误或没有可用文本 | 不自动输出 |

Post 降级时跳过额外 AI 润色，尽快保留已识别文字，浮窗显示“精修未完成 · 已使用识别文本”和“本次输出 · 未完整精修”，历史也保存降级原因。预览可能不完整，降级输出需要用户检查。当前标准模式没有启用这条 Post 预览降级策略。

一次录音在停止并完成处理后只输出一次，不会每收到一句 final 就粘贴一次。确定本次输出后，先写剪贴板并立即发起 `Cmd+V`，再保存历史与展示完成 UI。浮窗继续保留 1.5 秒，但不会为展示而延迟粘贴；“立即”指发起系统粘贴请求，目标应用的实际接收时间仍取决于系统和目标应用。

辅助功能权限缺失时，仍先写入剪贴板，再提示手动粘贴。替换本机 app 后如出现“能识别但无法自动插入”，应在系统设置中移除旧辅助功能条目，再添加 `/Applications/OpenTypeless.app`。

## 7. 本轮排查结论与验证

- 本机原 SDK 1.48.1 对 `PostRefinement` 返回过 `SPXERR_INVALID_ARG`（运行时代码 9）；升级至 1.51.2 后实际 Azure 调用通过。这个结论针对本次测试，不代表已确定所有旧版本的支持边界。
- 之前缺失最终结果的失败约在松开后 10 秒出现，未达到 App 的 20 秒上限。旧日志不能证明一定是 Azure 后台、SDK 或 App 段匹配的问题，不能据此宣称确认了 Azure 服务故障。
- 修复了可独立复现的相邻音频区间重叠导致错误合并的问题，并增加事件原因、音频偏移、接收/忽略计数、待完成段和降级原因日志，便于之后定位。
- 回归脚本覆盖延迟 final、offset 漂移、相邻/乱序多段、重复回调、缺失 final、超时、可恢复错误、取消/配置错误、标准模式严格输出，以及历史数据库迁移。
- 对同一合成音频完成了标准/Post、多句两秒停顿与说话中停止的真实 Azure 测试；检查了两种模式和降级状态的浮窗。用户已确认本机体验测试成功。

离线回归命令：

```bash
./scripts/test-azure-refinement.sh
```

测试使用临时数据库，不需要 Azure Key，不写入剪贴板。

## 8. 代码入口与参考

- [AzureSpeechProvider.swift](../OpenTypeless/Services/Speech/Providers/AzureSpeechProvider.swift)：SDK 配置和回调。
- [AzureSpeechSession.swift](../OpenTypeless/Services/Speech/Providers/AzureSpeechSession.swift)：语音段合并、停止等待和降级。
- [SpeechRecognitionProvider.swift](../OpenTypeless/Services/Speech/SpeechRecognitionProvider.swift)：阶段结果与降级元数据。
- [FloatingTranscriptView.swift](../OpenTypeless/Views/FloatingTranscriptView.swift)：双行浮窗、完成与错误状态。
- [OpenTypelessApp.swift](../OpenTypeless/App/OpenTypelessApp.swift)：停止录音、可选 AI 润色、剪贴板和粘贴顺序。

微软官方文档（本轮核对日期：2026-09-19）：

- [获取语音识别结果](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/get-speech-recognition-results?pivots=programming-language-python)
- [Post-stream refinement](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/how-to-recognize-speech?pivots=programming-language-python#post-stream-refinement)
- [识别结果后处理：TrueText 与 PostRefinement](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/how-to-post-processing)
- [静音与分段处理](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/how-to-recognize-speech?pivots=programming-language-python#change-how-silence-is-handled)

服务支持的区域、语言及行为可能继续变化；后续修改时应重新核对官方文档。
