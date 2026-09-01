"""实验 01：用标准库训练一个极小的逻辑回归。

目的：观察“参数权重”如何因为损失和梯度而改变。
这不是注意力，也不是 DeepSeek；它是后续理解训练的最小台阶。
"""

from math import exp


DATA = [
    # 学习小时数、练习次数、是否完成目标
    ([1.0, 0.0], 0),
    ([1.5, 1.0], 0),
    ([2.0, 1.0], 0),
    ([3.0, 2.0], 1),
    ([4.0, 3.0], 1),
    ([5.0, 4.0], 1),
]


def sigmoid(value: float) -> float:
    value = max(-60.0, min(60.0, value))
    return 1.0 / (1.0 + exp(-value))


def predict(weights: list[float], bias: float, features: list[float]) -> float:
    score = sum(weight * feature for weight, feature in zip(weights, features))
    return sigmoid(score + bias)


def train(epochs: int = 1200, learning_rate: float = 0.08) -> tuple[list[float], float]:
    weights = [0.0, 0.0]
    bias = 0.0

    for epoch in range(epochs):
        gradient_w = [0.0, 0.0]
        gradient_b = 0.0
        loss = 0.0

        for features, target in DATA:
            probability = predict(weights, bias, features)
            probability = max(1e-12, min(1.0 - 1e-12, probability))
            loss -= target * __import__("math").log(probability)
            loss -= (1 - target) * __import__("math").log(1 - probability)
            error = probability - target
            for index, feature in enumerate(features):
                gradient_w[index] += error * feature
            gradient_b += error

        count = len(DATA)
        for index in range(len(weights)):
            weights[index] -= learning_rate * gradient_w[index] / count
        bias -= learning_rate * gradient_b / count

        if epoch in (0, 1, 9, 99, 1199):
            print(
                f"epoch={epoch + 1:4d} loss={loss / count:.4f} "
                f"weights={[round(item, 4) for item in weights]} "
                f"bias={bias:.4f}"
            )

    return weights, bias


def main() -> None:
    weights, bias = train()
    print("\n最终预测：")
    for features, target in DATA:
        probability = predict(weights, bias, features)
        print(f"features={features} target={target} probability={probability:.3f}")
    print("\n思考：如果把练习次数全部改成 0，哪个权重会受到影响？")


if __name__ == "__main__":
    main()
