import 'word_parser.dart';

/// The single note format exposed by the simplified LearningOS client.
class LearningJournalTemplate {
  const LearningJournalTemplate._();

  static const _blank = '';

  static String blank({DateTime? date}) {
    final value = (date ?? DateTime.now()).toLocal();
    return '''# Learning Journal

## 基本信息

- 日期：${_date(value)}
- 学习主题：
- 学习时长：
- 学习方式 / 来源：

---

## 1. 今日学习目标

### 目标一

- $_blank

### 目标二

- $_blank

### 目标三

- $_blank

---

## 2. 学习内容记录

### 我今天学到了什么？

- $_blank

### 关键概念 / 知识点

- $_blank

### 重要例子 / 证据 / 资料

- $_blank

### 仍然不清楚的地方

- $_blank

---

## 3. 学习过程

### 我采用了哪些方法？

- $_blank

### 哪些方法有效？为什么？

- $_blank

### 遇到了哪些困难？

- $_blank

### 我是如何解决或尝试解决的？

- $_blank

---

## 4. 反思与理解

### 用自己的话总结今天的学习



### 这次学习与已有知识有什么联系？



### 这次学习改变了我的哪些认识？



### 如果重新开始，我会怎么做？



---

## 5. 学习成果 / 输出

- 完成的练习或任务：
- 产出的作品 / 笔记 / 代码：
- 可以展示或验证的结果：

---

## 6. 下一步行动计划

- 下一步要完成的事项：
- 需要补充的知识：
- 预计完成时间：
- 需要的资源或帮助：

---

## 7. 今日自评

- 目标完成度：`     / 10`
- 理解程度：`     / 10`
- 学习投入度：`     / 10`
- 今日最满意的地方：
- 明天想改进的地方：

---

## 8. 自由记录
''';
  }

  static String fromAiAnalysis({
    required String topic,
    required String source,
    required String summaryChinese,
    required String summaryEnglish,
    required List<String> concepts,
    required List<String> actions,
    required List<ParsedWord> words,
    required String originalText,
    DateTime? date,
  }) {
    final value = (date ?? DateTime.now()).toLocal();
    final goals = actions.take(3).toList(growable: false);
    final wordEvidence = words
        .take(12)
        .map((item) => '${item.word}：${item.translation}')
        .toList(growable: false);
    return '''# Learning Journal

## 基本信息

- 日期：${_date(value)}
- 学习主题：${_clean(topic)}
- 学习时长：待补充
- 学习方式 / 来源：${_clean(source)}

---

## 1. 今日学习目标

### 目标一

- ${_at(goals, 0)}

### 目标二

- ${_at(goals, 1)}

### 目标三

- ${_at(goals, 2)}

---

## 2. 学习内容记录

### 我今天学到了什么？

- ${_clean(summaryChinese)}

### 关键概念 / 知识点

${_bullets(concepts)}

### 重要例子 / 证据 / 资料

${_bullets(wordEvidence)}

### 仍然不清楚的地方

- 待复盘时补充

---

## 3. 学习过程

### 我采用了哪些方法？

- 使用 ${_clean(source)} 学习，并由 AI 提取重点、行动项和单词

### 哪些方法有效？为什么？

- AI 先整理信息结构，再由我核对原始资料和结论

### 遇到了哪些困难？

- 待补充

### 我是如何解决或尝试解决的？

- 待补充

---

## 4. 反思与理解

### 用自己的话总结今天的学习

${_clean(summaryChinese)}

### 这次学习与已有知识有什么联系？

待补充

### 这次学习改变了我的哪些认识？

待补充

### 如果重新开始，我会怎么做？

先明确问题，再阅读原始资料，最后使用 AI 检查遗漏。

---

## 5. 学习成果 / 输出

- 完成的练习或任务：完成一次 AI 分析总结
- 产出的作品 / 笔记 / 代码：本篇 Learning Journal
- 可以展示或验证的结果：${words.isEmpty ? '已保存分析摘要' : '提取 ${words.length} 个候选单词'}

---

## 6. 下一步行动计划

- 下一步要完成的事项：${actions.isEmpty ? '复习本篇记录' : _clean(actions.first)}
- 需要补充的知识：${actions.length < 2 ? '待补充' : _clean(actions[1])}
- 预计完成时间：待补充
- 需要的资源或帮助：待补充

---

## 7. 今日自评

- 目标完成度：`     / 10`
- 理解程度：`     / 10`
- 学习投入度：`     / 10`
- 今日最满意的地方：完成了结构化整理
- 明天想改进的地方：补充自评并验证仍不清楚的内容

---

## 8. 自由记录

### English summary

${_clean(summaryEnglish)}

### 原始学习材料

${originalText.trim()}
''';
  }

  static String _date(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  static String _at(List<String> values, int index) =>
      index < values.length ? _clean(values[index]) : '待补充';

  static String _bullets(List<String> values) => values.isEmpty
      ? '- 待补充'
      : values.map((value) => '- ${_clean(value)}').join('\n');

  static String _clean(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ');
}
