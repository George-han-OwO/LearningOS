# 实验路线

这些实验不要求 GPU，优先使用 Python 标准库，让学习者先看懂数学和数据流。

## 运行环境

在仓库根目录执行：

```powershell
python 课程/实验/01_参数权重.py
python 课程/实验/02_字符_bigram语言模型.py
python 课程/实验/03_手搓神经字符语言模型.py
python 课程/实验/04_手搓_attention.py
python 课程/实验/05_手搓_MoE_router.py
```

## 实验 01：参数权重

[01_参数权重.py](01_参数权重.py) 是一个极小的逻辑回归。它用“学习小时数”和
“练习次数”预测是否完成目标，训练时会打印参数如何变化。这些参数是长期保存的
模型权重，不是注意力权重。

## 实验 02：字符 bigram 语言模型

[02_字符_bigram语言模型.py](02_字符_bigram语言模型.py) 用相邻字符的计数估计：

```text
P(下一个字符 | 当前字符)
```

它没有神经网络，但已经是一个能根据上下文生成文本的语言模型。下一步会把计数
表替换为 embedding、矩阵乘法和梯度训练。

## 实验 03：神经字符语言模型

[03_手搓神经字符语言模型.py](03_手搓神经字符语言模型.py) 在 bigram 的条件概率
上加入可训练 embedding 和输出矩阵，手写 softmax、交叉熵、反向传播和 SGD。它
会打印测试集 perplexity，生成文本，并把模型保存为 `03_tiny_char_lm.json` 后
重新加载验证。

## 实验 04：Attention 临时权重

[04_手搓_attention.py](04_手搓_attention.py) 手算 Q/K 点积、缩放、causal mask、
softmax 和 V 加权求和，并验证每一行的注意力权重总和为 1、没有偷看未来 token。

## 实验 05：MoE Router

[05_手搓_MoE_router.py](05_手搓_MoE_router.py) 使用教学版的
`sqrt(softplus())` 分数，打印 top-k 专家、归一化 gate 和合并输出。真实 DeepSeek
还包含专家并行、通信、shared expert、负载均衡和专用 kernel；本脚本只复现路由
概念，不代表真实规模或全部实现。
