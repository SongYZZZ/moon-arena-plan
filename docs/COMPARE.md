# 版本间内存回归门禁

`compare BEFORE.json AFTER.json [MAX_GROWTH_BYTES]` 规划两个清单，逐 bank 比较高水位、峰值活跃字节数、容量和 bank 增删。默认允许增长 0；任一 bank 的高水位或活跃峰值增长超过阈值，或新布局超出容量，退出 1。通过退出 0；输入／布局结构错误退出 2。阈值单位为字节，并按 bank 分别应用，范围 0..2^50。

examples/regression_before.json 的 16 字节工作区升级为 regression_after.json 的 32 字节工作区时，默认门禁失败；明确允许 16 字节增长后通过。减少 bank 容量导致超预算时，即使占用不增长也失败。

库函数 compare_layouts 接受前后 Problem 与经过核验的 Layout，可比较实际使用的外部布局或 exact 结果。CLI 使用贪心计划，比较的是声明清单和该规划策略，不代表测得的整机内存或推理性能。
