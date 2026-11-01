# MoonArenaPlan schema 1

独立新项目，核心为多内存区约束、固定缓冲区、静态生命周期复用和布局独立核验。

schema=1 完整支持范围：显式内存区容量、字节数、两端包含的存活区间、对齐、允许内存区集合、固定 bank/offset。输出确定性布局；核验器重新读取原输入约束。

不承诺 ONNX/TFLite 格式兼容、形状推断、并行调度、别名原地计算或硬件缓存一致性。输入需列出 scratch、持久状态与外部占用。贪心超预算不证明不存在其他可行布局。

限制为 2048 buffers、32 banks、2^50 字节地址、时间步 0..1000000、ASCII 标识符最多 64 字符。

## 序列图合同

Graph schema 1：banks、tensors、steps。Tensor 继承 Buffer 的 ID、大小、对齐、允许 bank 与可选固定位置，并声明 source（外部已有输入）、retain（保留到结束）。Step 声明 ID、inputs、outputs、scratch。顺序必须满足依赖，生产者唯一，scratch 仅在一个算子内使用。最多 4096 steps、65536 引用。转换后再次执行完整 Problem 校验。

JSON 的所有 Int64 字段以十进制字符串表示，Int32 时间步/schema 使用整数 token；可选固定字段省略或 null 均可。未知字段、重复键、小数与指数 numeric token 拒绝；嵌套深度最多 32。布局最多 4096 placements、4096 条诊断；超过诊断上限返回 FindingLimit 错误，不返回部分通过结论。

## 0.2.0 完整新增合同

- solve_exact：Problem 不变；最多 12 buffers、4 banks；每个允许 bank 的所有对齐偏移都属于搜索域，固定位置只有一个候选。max_nodes 范围 1..1000000，默认 100000。solved 附独立核验布局，infeasible 只在搜索域全部耗尽时给出，limit 不提供不可行结论。此处是有限域可行性，不是 footprint 全局最优性。
- explain：只接受结构有效布局；按每个实际分配 bank 的最早最大活跃时间报告缓冲区 ID、字节数和偏移。highwater_minus_peak 包含对齐与固定空洞，不全部归为碎片；live_over_budget_by 不是可选 bank 全局不可行证明。
- compare_layouts：从两组 Problem/Layout 重算摘要；默认增长阈值 0，允许范围 0..2^50，按 bank 分别应用于高水位和活跃峰值。新布局容量违规总是使 gate_passed=false；增删 bank 明确报告。CLI compare 使用两边贪心计划，库 API 可接受外部精确布局。
- ExecutionTrace schema 1：banks、buffers（id、bytes、alignment、banks、可选 fixed_bank/fixed_offset）、events（step、op、buffer）。最多 2048 buffers、65536 events；step 非递减且为 0..1000000 的整数。op 为 begin/read/write/end，每个 ID 恰好一个闭合生命周期，所有读写必须在 active 状态。拒绝未知引用、重复开始、结束后访问、缺少结束与未观测对象。同一步包含两端，重复分配需不同 ID。仅检查被记录路径，不推断异步硬件完成时间。

CLI exact 退出码为 0（solved）、1（infeasible）、3（limit），输入错误为 2；compare 为 0（门禁通过）或 1（容量／增长失败），输入错误为 2。其余既有 schema 1、输入限制和命令语义保持可调用。
