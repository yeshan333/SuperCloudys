#!/bin/bash
# 测量 Finder 右键卡顿:同时 sample Finder 主线程 + 抓 SuperCloudys 扩展 perf log
# 用法: ./diagnose_rightclick.sh
# 流程: 倒计时 3 秒 -> 你立刻在 Finder 右键一次 -> sample 8 秒结束 -> 输出报告

set -u

FINDER_PID=$(pgrep -x Finder | head -1)
if [ -z "$FINDER_PID" ]; then
    echo "❌ Finder 进程未找到"
    exit 1
fi

EXT_PID=$(pgrep -x SuperCloudysExtension | head -1)
if [ -z "$EXT_PID" ]; then
    echo "⚠️  SuperCloudysExtension 未启动 (pkd 可能已回收)。继续测试 — 第一次右键会触发冷启动。"
else
    echo "ℹ️  SuperCloudysExtension PID: $EXT_PID (扩展已驻留)"
fi
echo "ℹ️  Finder PID: $FINDER_PID"
echo ""

PERF_LOG=$(mktemp -t supercloudys_perf.XXXXXX)
LOG_PID=""
cleanup() {
    if [ -n "$LOG_PID" ]; then
        kill "$LOG_PID" 2>/dev/null || true
        wait "$LOG_PID" 2>/dev/null || true
    fi
    rm -f "$PERF_LOG"
}
trap cleanup EXIT INT TERM
/usr/bin/stdbuf -o L /usr/bin/log stream --level debug \
    --timeout 12s \
    --predicate 'subsystem == "com.yeshan333.SuperCloudys"' --style compact \
    >"$PERF_LOG" 2>/dev/null &
LOG_PID=$!

echo "准备好你的鼠标光标在 Finder 窗口里某个文件上。"
for i in 3 2 1; do
    echo "  $i ..."
    sleep 1
done

START_TIME=$(date "+%Y-%m-%d %H:%M:%S")
START_EPOCH=$(date +%s)
echo "🎯 现在右键!可以右键多次,采样 8 秒"

SAMPLE_FILE=$(mktemp -t finder_sample.XXXXXX).txt
sample "$FINDER_PID" 8 -file "$SAMPLE_FILE" >/dev/null 2>&1

END_TIME=$(date "+%Y-%m-%d %H:%M:%S")
END_EPOCH=$(date +%s)
wait "$LOG_PID" 2>/dev/null || true
LOG_PID=""

ELAPSED=$((END_EPOCH - START_EPOCH))
echo ""
echo "✅ 采样完成 ($ELAPSED 秒)"
echo ""

echo "================================================================"
echo "  ⬇️  SuperCloudys 扩展 perf log (采样窗口内)"
echo "================================================================"
grep -Ev "^(Timestamp|Filtering)" "$PERF_LOG" \
    | sed -E 's/^[^[]*\[[0-9:]+ /[/;s/^.*com.yeshan333.SuperCloudys:perf\] /  /'

echo ""
echo "================================================================"
echo "  ⬇️  Finder 慢响应检测 (spindump)"
echo "================================================================"
/usr/bin/log show --start "$START_TIME" --end "$END_TIME" \
    --predicate 'process == "spindump" AND eventMessage CONTAINS "Finder"' --style compact 2>/dev/null \
    | grep -v "^Timestamp" \
    | grep -oE "Finder.*$" || echo "  (无 spindump 报告)"

echo ""
echo "================================================================"
echo "  ⬇️  Finder 主线程调用树 (Thread 0x... DispatchQueue 1)"
echo "================================================================"
# 提取主线程调用树（兼容不同 macOS sample 输出格式）
awk '
BEGIN { in_main=0 }
/^[[:space:]]*[0-9]+ Thread_.*(Main Thread|com.apple.main-thread)/ { in_main=1; print; next }
/^[[:space:]]*[0-9]+ Thread_/ && in_main { exit }
in_main { print }
' "$SAMPLE_FILE" | head -80

echo ""
echo "================================================================"
echo "  ⬇️  Top 25 热点函数 (所有线程合计)"
echo "================================================================"
awk '/^Sort by top of stack/,/^Binary Images:/' "$SAMPLE_FILE" \
    | grep -v "^Sort by\|^Binary Images\|^$" \
    | head -25

echo ""
echo "(完整 sample: $SAMPLE_FILE)"
echo ""
echo "📊 解读:"
echo "  - 看到 SuperCloudys 的 menu(for:) total < 50ms 说明 SuperCloudys 不是瓶颈"
echo "  - 看到 spindump 'slow hid response' 说明 Finder 主线程被卡了"
echo "  - 看 Finder 调用栈顶层是什么函数 — 那就是真正的 2 秒花在哪"
