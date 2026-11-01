# 公开参考与来源

产品 MoonBit 实现为本项目原创。标准库 moonbitlang/core（Apache-2.0）由工具链提供；CLI 使用 moonbitlang/async 0.21.2、moonbitlang/x 0.5.1，其原许可证随包保留。未将其他项目源码或测试数据移入核心实现。

- TFLM 官方内存流程：https://github.com/tensorflow/tflite-micro/blob/main/tensorflow/lite/micro/docs/online_memory_allocation_overview.md
- TFLM 离线计划：https://github.com/tensorflow/tflite-micro/blob/main/tensorflow/lite/micro/docs/offline_memory_plan.md
- 外部缓冲区 RFC：https://github.com/tensorflow/tflite-micro/blob/main/tensorflow/lite/micro/docs/rfc/001_preallocated_tensors.md
- 真实内存需求案例：https://github.com/tensorflow/tflite-micro/issues/2513
- ST DMA 可访问性案例：https://community.st.com/stm32-mcus-products-25/dma-issues-with-dual-core-stm32h745-105663
- 现有 MoonBit 推理运行时：https://github.com/mizchi/webnn-mbt
- 官方依赖：https://github.com/moonbitlang/core 、https://github.com/moonbitlang/async 、https://github.com/moonbitlang/x

示例 JSON、Python 独立检查器与 C replay 均为本项目编写的合成场景，不含客户数据、真实芯片实测或拷贝的神经网络模型。
