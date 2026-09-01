# DeepSeek-V4-Pro 原理教程：从零基础到手搓一个小模型

> 版本说明：本文按 2026-08-27 能查到的公开资料编写。凡是“官方公开”“实现
> 文档”“教学简化”都会明确标记。不要把尚未公开的工程细节当成事实。

## 0. 先建立正确的期待

DeepSeek-V4-Pro 不是一个可以在普通电脑上从零训练的项目。官方模型卡目前公开
的规格是约 1.6T 总参数、49B 激活参数、1M token 上下文；V4 系列使用混合注意力、
mHC 和 Muon 等技术，并以超过 32T tokens 进行预训练。[官方模型卡](https://huggingface.co/deepseek-ai/DeepSeek-V4-Pro)

我们的目标分成两层：

- **机制复现**：亲手实现 token、向量、attention、router、loss 和生成。
- **规模理解**：知道为什么真实模型需要多 GPU、压缩、缓存和并行系统。

“手搓一个模型”不等于复制 1.6T 参数，而是用小数据和小矩阵复现同一类计算。

## 1. 三种“权重”必须分清

### 1.1 参数权重

神经网络里的参数是训练时长期保存的数字。例如一个最简单的预测器：

```text
z = w1 × 学习小时数 + w2 × 练习次数 + b
预测 = sigmoid(z)
```

`w1`、`w2` 和 `b` 是参数。训练时模型先做预测，再比较答案，计算损失，然后用
梯度告诉参数应该增大还是减小：

```text
w_new = w_old - learning_rate × gradient
```

它们不是“某个词的固定重要性表”，而是很多层矩阵共同形成的分布式表示。

### 1.2 注意力权重

对某一个输入位置，注意力通常先计算 Query 和 Key 的匹配分数：

```text
score(i, j) = (q_i · k_j) / sqrt(d)
attention(i, j) = softmax(score(i, j))
output_i = Σ attention(i, j) × v_j
```

这里的 `attention(i, j)` 是当前这一次输入、当前层、当前头的临时数值；它和
训练后固定保存的参数权重不是一回事。因果 mask 还会禁止当前位置偷看未来 token。

### 1.3 相关度

“相关度”不是一个唯一公式。常见形式包括：

- 点积：`q · k`，方向相近且长度大时分数较大。
- 余弦相似度：`(q · k) / (||q|| ||k||)`，更关注方向。
- 注意力分数：点积经过缩放、mask 和 softmax 后变成权重。
- 检索相关度：可能是向量相似度、关键词匹配、重排序模型或混合分数。

因此不能说“AI 给每个词一个固定相关度”。必须说明是哪个层、哪个任务、哪次
输入、用的哪种评分函数。

## 2. Transformer 到底在运行什么

一次生成大致是：

```text
文字
 ↓ tokenizer
token id
 ↓ embedding lookup
向量序列
 ↓ 多层 decoder block
attention + MLP/MoE + residual/normalization
 ↓ vocabulary projection
每个候选 token 的 logits
 ↓ softmax / sampling
下一个 token
```

生成第一个 token 时，模型需要处理整个 prompt，这叫 prefill。之后每次只追加一个
新 token，并复用之前的 Key/Value，这叫 decode。KV cache 能省掉重复计算，但长上下文
会让缓存占用显存，因此 V4 的压缩注意力直接针对这个瓶颈。

## 3. V4-Pro 的公开架构要点

### 3.1 MoE：总参数很大，但每个 token 只激活一部分

V4-Pro 使用 Mixture-of-Experts。可以把每个 expert 想成一个专长不同的 MLP，router
先为当前 token 计算分数，然后选择 top-k 个 expert：

```text
gate_logits = router(x)
affinity = sqrt(softplus(gate_logits))   # V4 公开实现中的路由激活形式
chosen = top_k(affinity)
y = shared_expert(x) + Σ gate_weight[e] × expert_e(x)
```

Hugging Face 的 V4 实现文档给出的配置默认包括 256 个 routed experts、每个 token
选择 6 个、1 个 shared expert；它还记录了早期 hash-MoE 层和后续标准 top-k MoE 的
区别。[V4 实现文档：MoE 配置](https://huggingface.co/docs/transformers/en/model_doc/deepseek_v4#deepseekv4config)

这解释了两个容易混淆的数字：总参数量决定模型“仓库”有多大；激活参数量更接近
每个 token 实际参与矩阵乘法的规模，但真实运行还受到通信、缓存和并行方式影响。

### 3.2 CSA/HCA：先压缩，再决定看哪里

官方资料将 V4 的混合注意力描述为 Compressed Sparse Attention 和 Heavily
Compressed Attention 的组合，并强调 token 维度压缩和 DSA 稀疏注意力。[DeepSeek 官方预览说明](https://deepseek.com/en/news/v4-preview/)

- **CSA**：把一段 KV 压成较少的条目，再由 learned indexer 给压缩条目打分，取
  top-k，再做核心 attention；同时保留滑动窗口处理局部细节。
- **HCA**：压缩更激进，对压缩后的序列做稠密 attention；它没有 CSA 那样的 top-k
  indexer。

Hugging Face 的公开实现文档把教学上重要的控制量列出来：CSA 默认压缩率 `m=4`，
HCA 默认压缩率 `m'=128`，还有滑动窗口、index top-k、单 KV head 等设置。具体模型
配置可能随 checkpoint 变化，学习时以加载到的 config 为准。[V4 注意力实现文档](https://huggingface.co/docs/transformers/en/model_doc/deepseek_v4#architecture-paper-2)

一个教学化流程是：

```text
长序列 K/V
 ↓ 分块压缩
压缩条目 C0, C1, C2, ...
 ↓ indexer 计算 q_index · c_index
选择 top-k 条目
 ↓ 只对被选条目做长程 attention
再拼接局部滑动窗口信息
```

“相关度”在这里至少有两个层次：indexer 的筛选分数，以及被选条目进入核心
attention 后的 attention probability。二者不能混称。

### 3.3 mHC：让残差流更稳定

普通残差大致是：

```text
x_next = x + block(x)
```

mHC 使用多个残差流，并将组合矩阵投影到双随机矩阵空间；公开实现文档描述了用
Sinkhorn–Knopp 迭代产生这种约束，从而控制信号传播的放大趋势。[V4 mHC 实现文档](https://huggingface.co/docs/transformers/en/model_doc/deepseek_v4#manifold-constrained-hyper-connections-2)

初学者可以先把它理解为：模型允许多个“信息水管”混合，但混合规则受到约束，
避免信号在很多层中不断爆炸或衰减。真正的矩阵公式放到线性代数阶段学习。

### 3.4 训练和精度

官方模型卡公开了超过 32T tokens 的预训练和两阶段 post-training 描述：先培养
不同领域能力，再通过 on-policy distillation 统一能力。[DeepSeek-V4-Pro 模型卡](https://huggingface.co/deepseek-ai/DeepSeek-V4-Pro)

公开模型卡还列出 Pro instruct checkpoint 的 FP4 + FP8 mixed 形式：MoE expert 参数
使用 FP4，多数其他参数使用 FP8。精度降低不是“模型变聪明的魔法”，而是用更少的
存储和带宽换取工程效率，同时要处理量化误差和硬件 kernel 支持。

## 4. 硬件上怎样跑

从工程角度看，一次推理包含：

1. CPU 或输入服务接收请求并完成 tokenizer。
2. GPU 进行 embedding、矩阵乘法、attention 和 router 计算。
3. MoE token dispatch 把 token 发往对应 expert，可能需要 GPU 间通信。
4. KV cache 保留历史状态，下一轮 decode 复用它。
5. logits 返回采样器，选出下一个 token。

瓶颈通常不是单个乘法，而是“权重搬运、GPU 显存、KV cache、专家通信、批处理和
kernel 融合”一起决定吞吐和延迟。V4 的公开目标是让百万 token 上下文的计算和缓存
比传统方案更省；官方模型卡给出的对比是，在 1M 上下文下，单 token 推理 FLOPs
约为 V3.2 的 27%，KV cache 约为 10%。这是官方报告中的特定比较，不应外推成所有
硬件、所有输入都固定省到这个比例。[V4-Pro 官方模型卡](https://huggingface.co/deepseek-ai/DeepSeek-V4-Pro)

## 5. 我们怎样从零手搓

课程按以下顺序实现，不直接复制大模型源码：

```text
1. 线性/逻辑回归：理解参数权重和梯度
2. 向量相似度：理解点积、余弦和相关度
3. 字符 tokenizer：文字 → token id
4. bigram 语言模型：统计 token → 下一个 token 的概率
5. embedding：token id → 向量
6. 简化 attention：Q/K/V 和 softmax
7. 小型 MLP/Transformer：训练 next-token prediction
8. top-k router：用少数 expert 处理 token
9. KV cache 和采样：理解真实推理循环
10. 评估：loss、perplexity、生成样例和失败分析
```

先运行 [实验说明](实验/README.md) 中的两个标准库实验，再进入 PyTorch 版本。每次
实验都要回答：输入是什么、参数是什么、哪些数字是临时权重、损失如何改变参数、
推理时哪些步骤不再更新参数。
