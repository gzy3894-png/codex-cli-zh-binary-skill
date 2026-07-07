# Worker C 终端 perf 工作日志

日期：2026-07-07

## 改动文件

- `android-app/core/main/src/main/java/com/rk/terminal/ui/screens/terminal/TerminalBackEnd.kt`

## 已完成

- 保留 16ms 终端输出合帧。
- 扩展 perf 快照字段：平均/最大帧耗时、慢帧、输入事件、最近窗口请求与合帧计数、请求到帧延迟等。
- 通过现有 `$PREFIX/local/perf/terminal.status` 写入链路暴露，不引入 JankStats 依赖。

## 未做

- 未跑 Gradle/APK。
