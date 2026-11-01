# MoonArenaPlan schema 1

独立新项目，核心为多内存区约束、固定缓冲区、静态生命周期复用和布局独立核验。

schema=1 完整支持范围：显式内存区容量、字节数、两端包含的存活区间、对齐、允许内存区集合、固定 bank/offset。输出确定性布局；核验器重新读取原输入约束。

不承诺 ONNX/TFLite 格式兼容、形状推断、并行调度、别名原地计算或硬件缓存一致性。输入需列出 scratch、持久状态与外部占用。贪心超预算不证明不存在其他可行布局。

限制为 2048 buffers、32 banks、2^50 字节地址、时间步 0..1000000、ASCII 标识符最多 64 字符。

## 序列图合同

Graph schema 1：banks、tensors、steps。Tensor 继承 Buffer 的 ID、大小、对齐、允许 bank 与可选固定位置，并声明 source（外部已有输入）、retain（保留到结束）。Step 声明 ID、inputs、outputs、scratch。顺序必须满足依赖，生产者唯一，scratch 仅在一个算子内使用。最多 4096 steps、65536 引用。转换后再次执行完整 Problem 校验。

JSON 的所有 Int64 字段以十进制字符串表示，Int32 时间步/schema 使用整数 token；可选固定字段省略或 null 均可。未知字段、重复键、小数与指数 numeric token 拒绝；嵌套深度最多 32。布局最多 4096 placements、4096 条诊断；超过诊断上限返回 FindingLimit 错误，不返回部分通过结论。
