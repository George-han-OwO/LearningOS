"""实验 02：只用字符计数做一个能生成文本的语言模型。

模型学习的是 P(next_character | current_character)。
它没有神经网络，却完整展示了：数据、词表、概率、采样和生成。
"""

from collections import Counter, defaultdict
from random import Random


CORPUS = """
统计帮助我们理解数据，概率帮助我们描述不确定性。
模型通过观察很多例子，学习在当前上下文之后什么更可能出现。
attention 让模型能够根据上下文选择更相关的信息。
""".strip()


def build_model(text: str) -> tuple[dict[str, Counter[str]], list[str]]:
    transitions: dict[str, Counter[str]] = defaultdict(Counter)
    for current, following in zip(text, text[1:]):
        transitions[current][following] += 1
    vocabulary = sorted(set(text))
    return transitions, vocabulary


def sample_next(counter: Counter[str], vocabulary: list[str], rng: Random) -> str:
    # 加一点平滑，避免训练语料里没出现过的转移概率永远为零。
    weights = [counter[character] + 0.2 for character in vocabulary]
    return rng.choices(vocabulary, weights=weights, k=1)[0]


def generate(text: str, length: int = 80, seed: int = 7) -> str:
    transitions, vocabulary = build_model(text)
    rng = Random(seed)
    current = text[0]
    output = [current]
    for _ in range(length - 1):
        next_character = sample_next(transitions[current], vocabulary, rng)
        output.append(next_character)
        current = next_character
    return "".join(output)


def main() -> None:
    transitions, _ = build_model(CORPUS)
    print("字符 '模' 后面观察到的计数：", dict(transitions["模"]))
    print("\n生成结果：")
    print(generate(CORPUS))
    print("\n思考：bigram 只能看一个字符；要理解长句，需要什么结构？")


if __name__ == "__main__":
    main()
