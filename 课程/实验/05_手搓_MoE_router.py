"""实验 05：教学化的 top-k MoE Router。

每个 expert 都是一个极小的线性变换。Router 只负责给当前 token 打分，
选择 top-k，再用归一化后的分数合并 expert 输出。
"""

import math


TOKEN = [0.8, 0.2]
ROUTER = [
    [1.0, 0.0],
    [0.2, 0.9],
    [-0.4, 0.7],
    [0.6, 0.4],
]
EXPERTS = [
    [[1.0, 0.0], [0.0, 1.0]],
    [[0.5, 0.0], [0.0, 0.5]],
    [[-1.0, 0.0], [0.0, -1.0]],
    [[0.0, 1.0], [1.0, 0.0]],
]


def score(weights: list[float], token: list[float]) -> float:
    return sum(a * b for a, b in zip(weights, token))


def matvec(matrix: list[list[float]], vector: list[float]) -> list[float]:
    return [score(row, vector) for row in matrix]


def main() -> None:
    router_logits = [score(row, TOKEN) for row in ROUTER]
    # V4 public implementation documents sqrt(softplus) as the router score
    # transform; this tiny experiment uses the same named transform.
    affinity = [math.sqrt(math.log1p(math.exp(value))) for value in router_logits]
    top_k = 2
    selected = sorted(range(len(affinity)), key=lambda index: affinity[index], reverse=True)[:top_k]
    selected_total = sum(affinity[index] for index in selected)
    gate = {index: affinity[index] / selected_total for index in selected}

    print("router logits:", [round(value, 4) for value in router_logits])
    print("sqrt(softplus) affinity:", [round(value, 4) for value in affinity])
    print("selected experts:", selected)
    print("normalized gate:", {index: round(value, 4) for index, value in gate.items()})

    output = [0.0, 0.0]
    for index, weight in gate.items():
        expert_output = matvec(EXPERTS[index], TOKEN)
        for dimension, value in enumerate(expert_output):
            output[dimension] += weight * value
    print("combined output:", [round(value, 4) for value in output])
    assert len(selected) == top_k
    assert abs(sum(gate.values()) - 1.0) < 1e-9


if __name__ == "__main__":
    main()
