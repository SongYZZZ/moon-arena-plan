# MoonArenaPlan

静态多内存区缓冲区规划库与 CLI。给定缓冲区的大小、存活区间、允许内存区和固定位置，生成可复用的偏移布局，并用独立检查器核验结果。核心实现为 MoonBit，MIT 许可证。

适用于已知串行执行顺序的张量流水线、采集与处理缓冲区，以及内存预算的 CI 回归检查。使用者需提供准确的字节数、scratch、持久状态、保留输出和设备访问限制。

## 安装与构建

使用 moonc **0.10.16 或更高**；当前验证和 CI 固定 0.10.16+b1a0e846e 及匹配 core。Windows 已有 SDK 可在当前终端执行：

```powershell
. ./scripts/use-sdk.ps1 -SdkHome '你的 MoonBit SDK 绝对路径'
moon update
moon check --deny-warn
moon build --release --deny-warn
moon test --deny-warn
```

库安装：`moon add SongYZZZ/moon-arena-plan`。在 moon.pkg 导入 `"SongYZZZ/moon-arena-plan" @arena`，调用 `plan`、`verify`、`summarize`、`lifetimes`、`c_header`。API 见 pkg.generated.mbti，输入契约见 [SPEC.md](SPEC.md)。

## 可复现案例

```powershell
moon run cmd/arenaplan -- plan examples/reuse.json
moon run cmd/arenaplan -- plan examples/dma_banks.json
moon run cmd/arenaplan -- plan examples/budget_failure.json
```

第三条预期退出 1，报告超预算；不是构建失败。三个 64 字节、生命周期不重叠的缓冲区在第一个例子复用到 64 字节，而逐个独立预留需要 192 字节。第二例把固定采集缓冲区保留在 dma 内存区，把同一时刻存活的特征区放入 fast。第三例在交接步同时保留输入和输出，128 字节需求超出 96 字节预算。

这些是可执行的工程场景样本，尚无真实设备部署或用户采用记录。项目目标及成熟工具关系见 [docs/NECESSITY.md](docs/NECESSITY.md)。

```powershell
# layout 命令只输出布局，可把 stdout 保存为 layout.json
moon run cmd/arenaplan -- layout examples/reuse.json
moon run cmd/arenaplan -- verify examples/reuse.json layout.json
moon run cmd/arenaplan -- header examples/reuse.json layout.json
moon run cmd/arenaplan -- lifetimes examples/graph.json
```

文件读取仅接受最多 4 MiB 的 UTF-8 常规文件；CLI 只写 stdout/stderr，不覆盖输入。退出码 0 表示输入约束满足，1 表示布局/预算问题，2 表示输入、用法或导出失败。

## 验证

```powershell
python scripts/verify.py --exe _build/native/release/build/cmd/arenaplan/arenaplan.exe
moon run examples/c_replay
moon test --target js -p SongYZZZ/moon-arena-plan --deny-warn
moon test --target wasm-gc -p SongYZZZ/moon-arena-plan --deny-warn
```

Python 黑盒检查器用另一种实现核对随机问题、峰值和输入重排；C 示例使用 CLI 实际生成的头文件读写数组，检查交接步的数据保持。它们验证静态布局合同，不构成神经网络推理或硬件验证。

## 边界

schema 1 的完整字段及拒绝行为是本版本兼容终点。字节数、容量、对齐和偏移使用**十进制字符串**，时间步和 schema 使用 JSON 整数；禁止未知字段、重复 JSON 键和小数/指数形式的数值。空固定字段可省略或使用 null。

规划采用固定位置优先、可选 bank 数量较少的缓冲区优先、大小降序的贪心规则；ID 按 ASCII 排序，bank 列表顺序用于平局选择。结果不保证全局最优；超预算不证明其他布局都不可行。允许 bank 集合来自调用者，不从芯片型号自动推导。硬件地址、缓存一致性、异步 DMA 实际完成时间、栈和运行时开销需另行验证。

当前不读取 ONNX/TFLite 文件，不执行张量算子，不把外部框架的分配器作为产品实现。标准内存规划技术的公开参考与许可证见 [docs/REFERENCES.md](docs/REFERENCES.md)。

[终审自查与修复记录](docs/FINAL_REVIEW.md)包含实际结果和保留风险。
