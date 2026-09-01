"""实验 03：不用 PyTorch，手写一个可训练的神经字符语言模型。

这个模型只有一个 token embedding 和一个输出矩阵，学习：

    P(next_token | current_token)

它还没有 attention，所以不能代表 DeepSeek；它的价值是把训练闭环完全摊开：
tokenizer -> forward -> softmax -> loss -> backward -> SGD -> generate -> evaluate。
"""

import json
import math
import random
from pathlib import Path


CORPUS = (
    "统计帮助我们理解数据。概率帮助我们描述不确定性。"
    "模型通过观察很多例子，学习在当前上下文之后什么更可能出现。"
    "attention 让模型能够根据上下文选择更相关的信息。"
) * 20


class CharTokenizer:
    def __init__(self, vocabulary: list[str]) -> None:
        self.vocabulary = vocabulary
        self.to_id = {character: index for index, character in enumerate(vocabulary)}

    @classmethod
    def train(cls, text: str) -> "CharTokenizer":
        special = ["<BOS>", "<EOS>"]
        return cls(special + sorted(set(text)))

    def encode(self, text: str) -> list[int]:
        return [self.to_id["<BOS>"]] + [self.to_id[c] for c in text] + [
            self.to_id["<EOS>"]
        ]

    def decode(self, ids: list[int]) -> str:
        ignored = {"<BOS>", "<EOS>"}
        return "".join(
            self.vocabulary[index]
            for index in ids
            if self.vocabulary[index] not in ignored
        )

    def to_dict(self) -> dict[str, object]:
        return {"vocabulary": self.vocabulary}

    @classmethod
    def from_dict(cls, data: dict[str, object]) -> "CharTokenizer":
        raw = data["vocabulary"]
        if not isinstance(raw, list) or not all(isinstance(x, str) for x in raw):
            raise ValueError("invalid tokenizer vocabulary")
        return cls(raw)


def zeros(rows: int, columns: int) -> list[list[float]]:
    return [[0.0 for _ in range(columns)] for _ in range(rows)]


class TinyNeuralLanguageModel:
    def __init__(self, vocabulary_size: int, embedding_size: int = 16, seed: int = 7):
        rng = random.Random(seed)
        self.vocabulary_size = vocabulary_size
        self.embedding_size = embedding_size
        scale = 0.08
        self.embedding = [
            [rng.uniform(-scale, scale) for _ in range(embedding_size)]
            for _ in range(vocabulary_size)
        ]
        self.output = [
            [rng.uniform(-scale, scale) for _ in range(vocabulary_size)]
            for _ in range(embedding_size)
        ]
        self.bias = [0.0 for _ in range(vocabulary_size)]

    def logits(self, token_id: int) -> list[float]:
        vector = self.embedding[token_id]
        return [
            sum(vector[dim] * self.output[dim][candidate] for dim in range(self.embedding_size))
            + self.bias[candidate]
            for candidate in range(self.vocabulary_size)
        ]

    @staticmethod
    def softmax(values: list[float]) -> list[float]:
        maximum = max(values)
        exponentials = [math.exp(value - maximum) for value in values]
        total = sum(exponentials)
        return [value / total for value in exponentials]

    def probability(self, token_id: int) -> list[float]:
        return self.softmax(self.logits(token_id))

    def train_step(self, current_id: int, target_id: int, learning_rate: float) -> float:
        vector = self.embedding[current_id]
        probabilities = self.softmax(self.logits(current_id))
        loss = -math.log(max(probabilities[target_id], 1e-12))

        # d(loss)/d(logits) for softmax + cross entropy.
        d_logits = list(probabilities)
        d_logits[target_id] -= 1.0

        # Save the input gradient before mutating the output matrix.
        d_vector = [
            sum(d_logits[candidate] * self.output[dim][candidate] for candidate in range(self.vocabulary_size))
            for dim in range(self.embedding_size)
        ]

        for dim in range(self.embedding_size):
            for candidate in range(self.vocabulary_size):
                self.output[dim][candidate] -= (
                    learning_rate * vector[dim] * d_logits[candidate]
                )
        for candidate in range(self.vocabulary_size):
            self.bias[candidate] -= learning_rate * d_logits[candidate]
        for dim in range(self.embedding_size):
            self.embedding[current_id][dim] -= learning_rate * d_vector[dim]
        return loss

    def generate(
        self,
        tokenizer: CharTokenizer,
        prompt: str,
        length: int = 80,
        seed: int = 11,
        temperature: float = 0.8,
    ) -> str:
        rng = random.Random(seed)
        encoded_prompt = tokenizer.encode(prompt)
        current_id = encoded_prompt[-2] if len(encoded_prompt) >= 2 else tokenizer.to_id["<BOS>"]
        generated = list(prompt)
        for _ in range(length):
            raw = self.logits(current_id)
            scaled = [value / max(temperature, 0.05) for value in raw]
            probabilities = self.softmax(scaled)
            next_id = rng.choices(range(self.vocabulary_size), weights=probabilities, k=1)[0]
            if next_id == tokenizer.to_id["<EOS>"]:
                break
            generated.append(tokenizer.vocabulary[next_id])
            current_id = next_id
        return "".join(generated)

    def perplexity(self, pairs: list[tuple[int, int]]) -> float:
        if not pairs:
            return float("inf")
        loss = 0.0
        for current_id, target_id in pairs:
            probabilities = self.probability(current_id)
            loss -= math.log(max(probabilities[target_id], 1e-12))
        return math.exp(loss / len(pairs))

    def to_dict(self) -> dict[str, object]:
        return {
            "vocabulary_size": self.vocabulary_size,
            "embedding_size": self.embedding_size,
            "embedding": self.embedding,
            "output": self.output,
            "bias": self.bias,
        }

    @classmethod
    def from_dict(cls, data: dict[str, object]) -> "TinyNeuralLanguageModel":
        model = cls(
            int(data["vocabulary_size"]),
            int(data["embedding_size"]),
        )
        model.embedding = data["embedding"]  # type: ignore[assignment]
        model.output = data["output"]  # type: ignore[assignment]
        model.bias = data["bias"]  # type: ignore[assignment]
        return model


def make_pairs(token_ids: list[int]) -> list[tuple[int, int]]:
    return list(zip(token_ids, token_ids[1:]))


def main() -> None:
    tokenizer = CharTokenizer.train(CORPUS)
    all_pairs = make_pairs(tokenizer.encode(CORPUS))
    # Randomize pair assignment so the tiny evaluation set still contains
    # transitions from the same small teaching corpus. A contiguous split
    # would measure topic/order shift, not whether the toy model learned the
    # conditional transition rule.
    shuffled_pairs = list(all_pairs)
    random.Random(23).shuffle(shuffled_pairs)
    split = max(1, int(len(shuffled_pairs) * 0.8))
    train_pairs = shuffled_pairs[:split]
    test_pairs = shuffled_pairs[split:]
    model = TinyNeuralLanguageModel(len(tokenizer.vocabulary), embedding_size=18)

    print(f"vocabulary size: {len(tokenizer.vocabulary)}")
    print(f"training pairs: {len(train_pairs)}, test pairs: {len(test_pairs)}")
    print(f"initial test perplexity: {model.perplexity(test_pairs):.2f}")

    rng = random.Random(19)
    for step in range(1, 6001):
        current_id, target_id = rng.choice(train_pairs)
        loss = model.train_step(current_id, target_id, learning_rate=0.08)
        if step in (1, 1000, 3000, 6000):
            print(
                f"step={step:4d} loss={loss:.4f} "
                f"test_perplexity={model.perplexity(test_pairs):.2f}"
            )

    print("\ngenerated:")
    print(model.generate(tokenizer, "模型", length=80))

    artifact = Path(__file__).with_name("03_tiny_char_lm.json")
    artifact.write_text(
        json.dumps(
            {"tokenizer": tokenizer.to_dict(), "model": model.to_dict()},
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )
    restored = json.loads(artifact.read_text(encoding="utf-8"))
    restored_tokenizer = CharTokenizer.from_dict(restored["tokenizer"])
    restored_model = TinyNeuralLanguageModel.from_dict(restored["model"])
    print("saved and loaded:", model.generate(restored_tokenizer, "模型", 20, 11) == restored_model.generate(restored_tokenizer, "模型", 20, 11))


if __name__ == "__main__":
    main()
