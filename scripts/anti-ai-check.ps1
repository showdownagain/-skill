# anti-ai-check.ps1 — AI 味自动检测脚本(v0.0.3 升级版)
# 用法: powershell -ExecutionPolicy Bypass -File scripts/anti-ai-check.ps1 [-Path 正文目录] [-Threshold 3]
# 默认扫描 正文/ 下所有 vol-*/chapter-*.md,输出每章 AI 味风险报告
# 方法论:密度阈值化检测(不 0 容忍)+ 7 种 blocking 句式 + 10 类 AI tics
# 详细规则见 guidelines/去AI味手册.md

param(
    [string]$Path = "正文",
    [int]$Threshold = 3
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

if (-not (Test-Path $Path)) { Write-Error "目录不存在: $Path"; exit 1 }

$files = Get-ChildItem -Path $Path -Recurse -Filter *.md | Where-Object { $_.Name -notmatch "index" }
if ($files.Count -eq 0) { Write-Error "未找到章节文件"; exit 1 }

# ── 五类禁词(与 guidelines/去AI味手册.md 保持一致) ──
$weakAdverbs = "轻轻|微微|缓缓|慢慢|渐渐|悄悄|默默|静静|淡淡|深深|狠狠|猛地|忽然|突然|顿时|瞬间|立刻|马上|一时间|不由得|不由自主|下意识|不自觉|莫名|不知为何|恍然|骤然|蓦然|兀自|暗暗"
$universalPhrases = "深吸一口气|眸中闪过一丝|心底涌起|嘴角勾起一抹|空气中弥漫|这一刻|那一刻|他不禁|只见他|心想|暗道|默念|沉声道|淡淡的说|轻声说道|微微点头|目光如炬|映入眼帘"
$logicConnectors = "然而|但是|可是|不过|于是|因此|所以|竟|居然|竟然|原来|其实|显然|似乎|好像|仿佛|却"
$psychSummary = "他知道，这一切不过是|那一刻，他明白|也许，这就是|内心充满了|心中充满了|说不清道不明|挥之不去|暗暗发誓|他感到|她感到|感到一阵|感受到一种|涌起一股|升起一股|复杂的情绪|强烈的情绪"
$clicheMetaphors = "像一把刀|利刃|千斤重|如同一座大山|针扎|冰冷刺骨|空气仿佛凝固|时间仿佛停止|刀子般|一道闪电|断线的风筝|热锅上的蚂蚁"
$abstractWords = "命运|宿命|注定|意义深远|前所未有|可谓|充满希望|前途无量|未来可期|真正的开始|新的篇章|才刚刚开始|命运的齿轮"
$essayWords = "不难看出|由此可见|事实上|综上所述|于是乎|与此同时|从而|因而|诚然|进一步|深入|推进|落实"

# ── blocking 句式(真人语料命中≈0,出现即改) ──
$b1_not_is = "不(?:是|是)[^。！？!?，,，]{1,16}[，,][^。！？!?]{0,6}而?是[^。！？!?]{1,20}"      # 不是A,而是B
$b2_reverse_not_is = "是[^。！？!?，,]{1,12}[，,]\s*(?:而)?不是[^。！？!?]{1,20}"                        # 是A,不是B
$b3_voice_contrast = "声音(?:并)?不[大高响亮][^。！？!?\n]{0,16}[却但偏]"                              # 声音不大…却
$b4_negation_parade = "(?:没有[^。！？!?\n，,]{1,12}[，,]){2}"                                            # 没有X,没有Y
$b5_trailer = "没人知道|谁也不知道|谁也没想到|殊不知|才刚刚开(?:始|头)|正(?:朝着|向着)[^。！？!?]{0,24}(?:压|涌|袭|逼)(?:了?过去|了?过来|来)|拉开(?:序幕|帷幕)|即将(?:开始|来临|降临)"
$b6_trailer_summary = "这一(?:夜|天|刻|战|年|局|役)[，,]?[^。！？!?]{0,8}注定|就这样[，,][^。！？!?]{0,8}(?:一切|全部)[^。！？!?]{0,4}(?:结束了|落幕|收场)|这一切[，,]?[^。！？!?]{0,8}(?:都)?(?:说明|意味着|结束了)|(?:新的篇章|新的旅程|崭新的篇章|新的人生)[^。！？!?]{0,6}(?:开始|拉开|展开)|命运[^。！？!?]{0,6}齿轮"
$b7_em_dash = "——"

# ── tics 检测 ──
$microAction = "了(?:[一两三几半])?[下阵圈道声眼口气会]"        # 微动作复读:拍了两下/松了半圈
$reasonChain = "这意味着|也就是说|换句话说|问题在于|关键在于|只有这样|想到这里|(?:他|她|我)?(?:知道|明白|意识到)"  # 解释链
$actionListVerbs = "伸手|抬手|拿起|拿过|取出|取过|掏出|摸出|抓起|攥住|握住|按住|推开|拉开|打开|关上|放下|递给|转身|回头|抬头|低头|弯腰|坐下|站起|走到|看向|盯着"

$total = @{}
foreach ($f in $files) {
    $text = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
    $name = $f.Name
    $chars = $text.Length
    $kilo = [math]::Max(1, $chars / 1000)
    $r = @{}

    # 1. 五类禁词(按密度计)
    $weak = ([regex]::Matches($text, $weakAdverbs)).Count
    $r["类一:情绪副词/千字"] = [math]::Round($weak / $kilo, 1)
    $r["类二:万能句式"] = ([regex]::Matches($text, $universalPhrases)).Count
    $r["类三:逻辑连词"] = ([regex]::Matches($text, $logicConnectors)).Count
    $r["类四:心理总结"] = ([regex]::Matches($text, $psychSummary)).Count
    $r["类五:俗套比喻"] = ([regex]::Matches($text, $clicheMetaphors)).Count
    $r["类六:抽象升华"] = ([regex]::Matches($text, $abstractWords)).Count
    $r["类七:论文体"] = ([regex]::Matches($text, $essayWords)).Count

    # 2. blocking 句式
    $r["B1 不是A而是B"] = ([regex]::Matches($text, $b1_not_is)).Count
    $r["B2 是A不是B"] = ([regex]::Matches($text, $b2_reverse_not_is)).Count
    $r["B3 音量反差"] = ([regex]::Matches($text, $b3_voice_contrast)).Count
    $r["B4 否定排比"] = ([regex]::Matches($text, $b4_negation_parade)).Count
    $b5 = ([regex]::Matches($text, $b5_trailer)).Count
    $b6 = ([regex]::Matches($text, $b6_trailer_summary)).Count
    $r["B5 预告收尾"] = $b5
    $r["B6 状态总结"] = $b6
    $r["B7 破折号"] = ([regex]::Matches($text, $b7_em_dash)).Count

    # 3. tics
    $r["t1 微动作复读/千字"] = [math]::Round(([regex]::Matches($text, $microAction)).Count / $kilo, 1)
    $r["t2 解释链/千字"] = [math]::Round(([regex]::Matches($text, $reasonChain)).Count / $kilo, 1)
    $r["t3 动作清单"] = ([regex]::Matches($text, $actionListVerbs)).Count
    $r["t4 比喻标记/千字"] = [math]::Round(([regex]::Matches($text, "好像|像是|仿佛|宛如|如同|犹如")).Count / $kilo, 1)
    $r["t5 套词/千字"] = [math]::Round(([regex]::Matches($text, "仿佛|一丝|一抹|些许|隐约|深吸一口气|平静无波|指节泛白")).Count / $kilo, 1)

    # 4. 句长分析:逗号长句占比 / 短句 / 碎句号(连续6+个≤5字短句)
    $commaSentences = [regex]::Matches($text, "，[^，。！？!?…]{8,12}，[^，。！？!?…]{8,12}，?[^。！？!?…]{8,24}[。！]")
    $r["逗号长句数"] = $commaSentences.Count
    $sentences = [regex]::Split($text, "[。！？!?…]+") | Where-Object { $_.Trim().Length -ge 2 }
    $shortCount = ($sentences | Where-Object { $_.Length -le 5 }).Count
    $r["短句(≤5字)占比"] = if ($sentences.Count) { [math]::Round($shortCount * 100 / $sentences.Count, 1) } else { 0 }
    $stutterRun = 0; $stutterMax = 0
    foreach ($s in $sentences) {
        if ($s.Trim().Length -le 5) { $stutterRun++ } else { if ($stutterRun -gt $stutterMax) { $stutterMax = $stutterRun }; $stutterRun = 0 }
    }
    $r["最长碎句号连排"] = $stutterMax

    # 5. 主语单调
    $lines = $text -split "`r?`n"
    $heRun = 0; $heMax = 0
    foreach ($ln in $lines) {
        if ($ln -match '^\s*[他她]') { $heRun++ } else { if ($heRun -gt $heMax) { $heMax = $heRun }; $heRun = 0 }
    }
    $r["他/她开头连续行"] = $heMax

    # 6. 对话占比 / 省略号
    $paras = $text -split "`r?`n" | Where-Object { $_.Trim().Length -gt 0 }
    $dlg = ($paras | Where-Object { $_ -match "「" }).Count
    $r["对话占比"] = if ($paras.Count) { [math]::Round($dlg * 100 / $paras.Count, 1) } else { 0 }
    $r["省略号"] = ([regex]::Matches($text, "…")).Count

    $total[$name] = $r
}

# ── 风险判定 ──
Write-Output ""
Write-Output "═" * 78
Write-Output " AI 味检测报告 v0.0.3(命中 $Threshold 项以上 = HIGH)"
Write-Output "═" * 78
Write-Output ("{0,-18} {1,5} {2,5} {3,5} {4,5} {5,5} {6,5} {7,5} {8,5} {9,5} {10,4} {11,4} {12,4} {13,4} {14,5}" -f "文件","类一/千","万能式","心理结","抽象升","B1-B4","B5-B6","破折号","碎句号","长句数","对话%","解释链","动作清","省略号","风险")
Write-Output ("-" * 78)

foreach ($name in $total.Keys | Sort-Object) {
    $r = $total[$name]
    $hits = 0
    $hits += if ($r["类一:情绪副词/千字"] -gt 3) { 1 } else { 0 }
    $hits += if ($r["类二:万能句式"] -gt 0) { 1 } else { 0 }
    $hits += if ($r["类三:逻辑连词"] -gt 15) { 1 } else { 0 }
    $hits += if ($r["类四:心理总结"] -gt 0) { 1 } else { 0 }
    $hits += if ($r["类五:俗套比喻"] -gt 0 -or $r["类六:抽象升华"] -gt 0 -or $r["类七:论文体"] -gt 0) { 1 } else { 0 }
    $b = [int]$r["B1 不是A而是B"] + [int]$r["B2 是A不是B"] + [int]$r["B3 音量反差"] + [int]$r["B4 否定排比"]
    $hits += if ($b -gt 0) { 1 } else { 0 }
    $b56 = [int]$r["B5 预告收尾"] + [int]$r["B6 状态总结"]
    $hits += if ($b56 -gt 0) { 1 } else { 0 }
    $hits += if ($r["B7 破折号"] -gt 3) { 1 } else { 0 }
    $hits += if ($r["最长碎句号连排"] -ge 6) { 1 } else { 0 }
    $hits += if ($r["逗号长句数"] -eq 0) { 1 } else { 0 }
    $hits += if ($r["对话占比"] -lt 15 -or $r["对话占比"] -gt 60) { 1 } else { 0 }
    $hits += if ($r["t2 解释链/千字"] -gt 5) { 1 } else { 0 }
    $hits += if ($r["t3 动作清单"] -ge 8) { 1 } else { 0 }
    $hits += if ($r["省略号"] -gt 3) { 1 } else { 0 }
    $hits += if ($r["他/她开头连续行"] -ge 3) { 1 } else { 0 }

    $risk = if ($hits -ge $Threshold) { "HIGH" } else { "  OK" }
    Write-Output ("{0,-18} {1,5} {2,5} {3,5} {4,5} {5,5} {6,5} {7,5} {8,5} {9,5} {10,4} {11,4} {12,4} {13,4} {14,5}" -f $name,$r["类一:情绪副词/千字"],$r["类二:万能句式"],$r["类四:心理总结"],$r["类六:抽象升华"],$b,$b56,$r["B7 破折号"],$r["最长碎句号连排"],$r["逗号长句数"],$r["对话占比"],$r["t2 解释链/千字"],$r["t3 动作清单"],$r["省略号"],$risk)
}

Write-Output ""
Write-Output "判定标准(详见 guidelines/去AI味手册.md 第九节):"
Write-Output "  类一情绪副词 >3/千字 | 类二万能句式/类四心理总结 出现即红 | 类三逻辑连词 >15/章"
Write-Output "  类五/六/七 俗套比喻/抽象升华/论文体 出现即红 | B1-B4 blocking 句式 出现即红"
Write-Output "  B5-B6 章尾预告/总结体 出现即红 | 破折号 >3 | 碎句号连排 ≥6 | 无逗号长句"
Write-Output "  对话占比 <15% 或 >60% | 解释链 >5/千字 | 动作清单 ≥8 | 省略号 >3 | 他/她开头连续 ≥3"
Write-Output "  命中 $Threshold 项以上 = HIGH,按《去AI味手册》三遍法回炉;blocking 句式(B1-B7)优先处理。"
