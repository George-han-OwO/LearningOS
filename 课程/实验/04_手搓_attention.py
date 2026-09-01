"""实验 04：把一个极小的 causal attention 摊开打印。

这是教学简化版：Q/K/V 已经给定，没有训练投影矩阵，也没有 RoPE。
它只展示“当前位置如何给可见位置分配临时注意力权重”。
"""

import math


TOKENS = ["我", "学", "AI"]
QUERIES = [[1.0, 0.0], [0.7, 0.7], [0.1, 0.99]]
KEYS = [[1.0, 0.0], [0.7, 0.7], [0.1, 0.99]]
VALUES = [[1.0, 0.0], [0.0, 1.0], [1.0, 1.0]]


def dot(left: list[float], right: list[float]) -> float:
    return sum(a * b for a, b in zip(left, right))


def softmax(values: list[float]) -> list[float]:
    maximum = max(values)
    exp_values = [math.exp(value - maximum) for value in values]
    total = sum(exp_values)
    return [value / total for value in exp_values]


def main() -> None:
    dimension = len(QUERIES[0])
    all_weights: list[list[float]] = []
    for position, query in enumerate(QUERIES):
        scores = [dot(query, key) / math.sqrt(dimension) for key in KEYS]
        # Causal mask: position i cannot look at positions after i.
        masked_scores = [score if index <= position else -float("inf") for index, score in enumerate(scores)]
        weights = softmax(masked_scores)
        output = [
            sum(weights[index] * VALUES[index][dimension_index] for index in range(len(VALUES)))
            for dimension_index in range(len(VALUES[0]))
        ]
        all_weights.append(weights)
        visible = {TOKENS[index]: round(weight, 4) for index, weight in enumerate(weights) if weight > 0}
        print(f"query={TOKENS[position]} scores={[round(x, 4) for x in scores]}")
        print(f"  visible attention weights={visible} sum={sum(weights):.4f}")
        print(f"  weighted value={list(map(lambda x: round(x, 4), output))}")

    assert all(abs(sum(row) - 1.0) < 1e-9 for row in all_weights)
    assert all(weight == 0.0 for weight in all_weights[0][1:])
    print("\n验证通过：每个位置的权重和为 1，且没有偷看未来 token。")


if __name__ == "__main__":
    main()
