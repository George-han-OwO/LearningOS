import 'models.dart';

CourseQuestion _question(
  String id,
  String prompt,
  List<String> options,
  int correctIndex,
  String explanation,
) => CourseQuestion(
  id: id,
  prompt: prompt,
  options: options,
  correctIndex: correctIndex,
  explanation: explanation,
);

CourseChapter _chapter({
  required String id,
  required String phase,
  required int order,
  required String title,
  required String description,
  required List<String> objectives,
  required String lesson,
  required List<CourseQuestion> questions,
}) => CourseChapter(
  chapterId: id,
  phase: phase,
  orderIndex: order,
  title: title,
  description: description,
  objectives: objectives,
  lesson: lesson,
  questions: questions,
  status: CourseChapterStatus.locked,
  mastery: 0,
  attempts: 0,
);

/// The first curriculum slice is intentionally hand-authored and deterministic.
/// AI-generated lessons can be added later, but the learner must always have a
/// safe, testable baseline instead of receiving an unvalidated lesson.
final List<CourseChapter> courseCatalog = [
  _chapter(
    id: 'statistics.data.01',
    phase: 'AP 统计 · 起步',
    order: 1,
    title: '数据、变量与样本',
    description: '先学会区分数据、变量、样本和总体。',
    objectives: ['识别变量', '区分样本与总体', '知道一条记录包含什么'],
    lesson: '''数据是对对象或事件的记录。变量是会变化、可以被记录的特征，例如每天学习分钟数。

总体是我们想了解的全部对象，样本是从总体中实际观察到的一部分。统计推断的关键，就是用样本信息谨慎地了解总体，而不是把一次观察当成绝对真理。''',
    questions: [
      _question(
        'q1',
        '记录“每天学习了多少分钟”时，学习分钟数最像什么？',
        ['总体', '变量', '结论', '模型文件'],
        1,
        '它是每条记录可能不同的特征，因此是变量。',
      ),
      _question(
        'q2',
        '想了解全班同学的复习时间，只调查其中 20 人，这 20 人是？',
        ['总体', '样本', '参数权重', '标签'],
        1,
        '实际被观察的一部分对象叫样本。',
      ),
      _question(
        'q3',
        '下面哪句话最谨慎？',
        ['样本平均数必然等于总体平均数', '样本可以帮助我们估计总体，但会有不确定性', '一次记录就是规律', '数据不需要来源'],
        1,
        '样本推断总体必须保留不确定性。',
      ),
    ],
  ),
  _chapter(
    id: 'statistics.summary.01',
    phase: 'AP 统计 · 起步',
    order: 2,
    title: '平均数、中位数与异常值',
    description: '用中心趋势描述一组数据，并理解异常值的影响。',
    objectives: ['计算平均数', '理解中位数', '解释异常值对统计量的影响'],
    lesson: '''平均数把所有数值相加后除以数量；中位数是排序后位于中间的值。平均数使用了每个数，因此容易被极端值拉动；中位数通常更稳健。

描述数据时不能只报一个数字，还要说明数据的分布和可能的异常值。''',
    questions: [
      _question(
        'q1',
        '数据 1、2、3、100 中，哪个中心量更不容易被 100 拉动？',
        ['平均数', '中位数', '总和', '最大值'],
        1,
        '中位数主要由排序位置决定，对极端值更稳健。',
      ),
      _question(
        'q2',
        '4 个数的平均数是 10，它们的总和是多少？',
        ['2.5', '10', '14', '40'],
        3,
        '总和 = 平均数 × 数量 = 10 × 4。',
      ),
      _question(
        'q3',
        '只报告平均数而不看分布，最大的风险是什么？',
        ['无法知道数据是否偏斜或有异常值', '一定会算错', '会把样本变成总体', '能自动得到因果关系'],
        0,
        '同一个平均数可能对应完全不同的分布。',
      ),
    ],
  ),
  _chapter(
    id: 'statistics.probability.01',
    phase: 'AP 统计 · 概率',
    order: 3,
    title: '概率与条件概率直觉',
    description: '用概率描述不确定性，为机器学习打基础。',
    objectives: ['理解概率范围', '区分联合与条件概率', '识别独立性的含义'],
    lesson: '''概率是 0 到 1 之间对事件可能性的描述。条件概率 P(A|B) 表示“已知 B 发生后 A 的概率”，它不一定等于 P(A)。

独立表示知道一个事件发生，并不会改变另一个事件的概率；“看起来有关”不等于数学上的独立或因果。''',
    questions: [
      _question(
        'q1',
        '一个必然发生的事件，其概率是？',
        ['-1', '0', '0.5', '1'],
        3,
        '必然事件概率为 1。',
      ),
      _question(
        'q2',
        'P(A|B) 中竖线的直观含义是？',
        ['A 和 B 相减', '在已知 B 的条件下看 A', 'A 的参数权重', 'B 一定导致 A'],
        1,
        '条件概率把 B 作为已知条件。',
      ),
      _question(
        'q3',
        '独立事件的正确描述是？',
        ['一个事件发生会改变另一个的概率', '两个事件不能同时发生', '知道一个事件不会改变另一个的概率', '两个事件一定相等'],
        2,
        '独立是概率上的不影响，不代表事件不能同时发生。',
      ),
    ],
  ),
  _chapter(
    id: 'math.functions.01',
    phase: '数学桥梁 · 微积分前置',
    order: 4,
    title: '函数：输入如何变成输出',
    description: '建立模型最重要的语言：输入、规则和输出。',
    objectives: ['读懂函数', '理解变量关系', '为导数和模型映射做准备'],
    lesson: '''函数可以先看成一台机器：输入 x，按照规则计算，得到输出 y。机器学习模型也是函数，只是它的规则由大量参数决定。

例如 y = 2x + 1 中，x 是输入，2 和 1 是参数/常数，y 是输出。改变参数，就会改变整台机器的行为。''',
    questions: [
      _question(
        'q1',
        '在 y = 2x + 1 中，x 代表什么？',
        ['输入', '输出', '损失', 'GPU'],
        0,
        'x 是函数的输入。',
      ),
      _question(
        'q2',
        '如果 x = 3，y = 2x + 1 等于多少？',
        ['5', '6', '7', '9'],
        2,
        '2 × 3 + 1 = 7。',
      ),
      _question(
        'q3',
        '机器学习模型可以先被理解成什么？',
        ['只是一张图片', '把输入映射为输出的函数', '永远不变的答案表', '一个邮箱协议'],
        1,
        '模型接受输入并计算输出。',
      ),
    ],
  ),
  _chapter(
    id: 'ml.vectors.01',
    phase: '机器学习 · 向量',
    order: 5,
    title: '向量、点积与相关度',
    description: '理解“两个表示有多匹配”，为 attention 做准备。',
    objectives: ['计算点积', '理解方向与长度', '区分相似度和因果关系'],
    lesson:
        '''向量是一列数字。两个向量的点积是对应位置相乘再相加：q·k = Σ q_i k_i。点积常被当作匹配分数，但它会同时受到方向和长度影响。

余弦相似度会除以两个向量的长度，更多关注方向。相似度高只表示表示空间中的接近，不自动证明现实世界中存在因果关系。''',
    questions: [
      _question(
        'q1',
        '向量 [1, 2] 与 [3, 4] 的点积是多少？',
        ['7', '8', '11', '14'],
        2,
        '1×3 + 2×4 = 11。',
      ),
      _question(
        'q2',
        '点积常被用作什么？',
        ['匹配分数', '密码', '文件路径', '训练轮数'],
        0,
        '点积是常见的匹配/相似度原始分数。',
      ),
      _question(
        'q3',
        '相似度高是否自动代表因果关系？',
        ['是', '否', '只有中文是', '只有 GPU 上是'],
        1,
        '相关或相似不等于因果。',
      ),
    ],
  ),
  _chapter(
    id: 'ml.weights.01',
    phase: '机器学习 · 训练',
    order: 6,
    title: '参数权重与梯度下降',
    description: '观察模型如何根据错误调整参数。',
    objectives: ['区分参数和预测', '理解损失', '解释梯度下降'],
    lesson:
        '''参数权重是模型长期保存的数字。模型先用参数做预测，再用损失衡量预测和答案的差距。梯度告诉我们改变每个参数会让损失如何变化，梯度下降沿着降低损失的方向更新参数。

w_new = w_old - learning_rate × gradient。学习率太大可能震荡，太小则学习很慢。''',
    questions: [
      _question(
        'q1',
        '参数权重在训练中主要做什么？',
        ['控制输入如何被变换', '保存邮箱密码', '决定屏幕颜色', '跳过所有数据'],
        0,
        '参数决定模型函数的具体形状。',
      ),
      _question(
        'q2',
        '损失函数用于衡量什么？',
        ['预测与目标的差距', '电脑重量', '文件大小', 'token 字符数'],
        0,
        '损失是训练的优化目标。',
      ),
      _question(
        'q3',
        '梯度下降的基本方向是？',
        ['沿梯度增大的方向永远走', '沿能降低损失的方向调整参数', '随机删除参数', '只更新输入'],
        1,
        '更新公式通常是 w - 学习率×梯度。',
      ),
    ],
  ),
  _chapter(
    id: 'llm.token.01',
    phase: '语言模型 · Token',
    order: 7,
    title: 'Tokenizer：文字变成编号',
    description: '理解语言模型为什么不直接处理汉字和单词。',
    objectives: ['理解 token', '建立词表', '知道编号不是语义本身'],
    lesson:
        '''神经网络处理数字，所以输入文字必须先由 tokenizer 切成 token，再把 token 映射成整数 id。一个 token 可能是一个字、一个词、一个子词或标点。

token id 只是词表中的编号，不代表数字大小具有语义。后续 embedding 会把编号查表变成向量。''',
    questions: [
      _question(
        'q1',
        'Tokenizer 的主要工作是？',
        ['把文字切成 token 并映射为 id', '直接训练 GPU', '生成最终答案', '删除所有标点'],
        0,
        'Tokenizer 是文字到数字序列的入口。',
      ),
      _question(
        'q2',
        'token id = 20 和 token id = 40 的关系是？',
        ['40 的语义一定是 20 的两倍', '它们通常只是两个编号', '40 一定更重要', '20 一定更常见'],
        1,
        'id 的数值大小通常没有这种语义。',
      ),
      _question(
        'q3',
        'embedding 的作用更接近什么？',
        ['把 id 查成可学习的向量', '把向量变成密码', '删除上下文', '选择 GPU 型号'],
        0,
        'Embedding 是一个可学习的查表。',
      ),
    ],
  ),
  _chapter(
    id: 'llm.attention.01',
    phase: '语言模型 · Transformer',
    order: 8,
    title: 'Attention：当前 token 看哪里',
    description: '用 Q、K、V 理解上下文相关度。',
    objectives: ['计算 QK 匹配分数', '理解 softmax', '解释加权求和'],
    lesson:
        '''Attention 先把表示投影成 Query、Key、Value。Query 和 Key 的点积得到匹配分数，除以 sqrt(d) 后做 softmax 得到一组和约为 1 的注意力权重，最后用这些权重对 Value 加权求和。

这是一次输入中的临时计算，不等于模型参数权重。''',
    questions: [
      _question(
        'q1',
        'attention 的匹配分数常由什么产生？',
        ['Q 和 K 的点积', 'V 和文件名相加', 'GPU 温度', '答案长度'],
        0,
        'QK 点积是注意力的经典匹配步骤。',
      ),
      _question(
        'q2',
        'softmax 后的一组注意力权重通常具有什么性质？',
        ['可以是任意负数且总和为 100', '非负且总和约为 1', '全部相等', '全部变成字符串'],
        1,
        'softmax 输出非负概率样权重。',
      ),
      _question(
        'q3',
        '注意力权重和参数权重的区别是？',
        ['完全相同', '注意力权重依赖当前输入，参数权重通常是训练后保存的', '参数权重只用于显示', '注意力权重永远不变'],
        1,
        '二者生命周期和含义不同。',
      ),
    ],
  ),
  _chapter(
    id: 'llm.moe.01',
    phase: '语言模型 · MoE',
    order: 9,
    title: 'Router 与专家选择',
    description: '理解为什么总参数很大而每个 token 只走部分专家。',
    objectives: ['理解 router', '理解 top-k', '区分总参数和激活参数'],
    lesson:
        '''Mixture-of-Experts 把多个 MLP 专家放在一起。router 对当前 token 计算专家分数，选择 top-k 个专家，并按归一化分数合并它们的输出。shared expert 可以对所有 token 都运行。

总参数包含所有专家；激活参数更接近某个 token 实际使用的那部分，但通信和缓存也会影响真实成本。''',
    questions: [
      _question(
        'q1',
        'router 的主要工作是？',
        ['为当前 token 选择专家', '训练 tokenizer', '保存用户密码', '渲染 UI'],
        0,
        'router 决定 token 经过哪些专家。',
      ),
      _question(
        'q2',
        'top-k 的含义是？',
        ['选择分数最高的 k 个候选', '永远选择全部专家', '只看第 k 个字符', '删除 k 个参数'],
        0,
        'top-k 是稀疏选择。',
      ),
      _question(
        'q3',
        '总参数量和激活参数量的区别是？',
        [
          '总参数包含所有专家，激活参数是当前 token 参与计算的部分',
          '二者永远相等',
          '激活参数是磁盘容量',
          '总参数只包含 tokenizer',
        ],
        0,
        '这是 MoE 规模理解的核心区别。',
      ),
    ],
  ),
  _chapter(
    id: 'deepseek.v4.01',
    phase: 'DeepSeek-V4-Pro',
    order: 10,
    title: 'DeepSeek-V4-Pro 总览',
    description: '把前面学到的概念映射到真实公开模型。',
    objectives: ['说出 V4-Pro 的公开规格', '区分事实与推断', '理解长上下文效率目标'],
    lesson:
        '''根据当前官方公开模型卡，DeepSeek-V4-Pro 是 1.6T 总参数、49B 激活参数、支持 1M token 上下文的 MoE 模型。V4 系列公开介绍了 CSA/HCA 混合注意力、mHC 和 Muon 等关键技术。

学习时要区分：官方已公开的规格是事实；对未公开 kernel、数据配比或内部部署细节的说法只能标为推断。''',
    questions: [
      _question(
        'q1',
        'V4-Pro 官方公开的数字组合更接近哪一个？',
        [
          '1.6T 总参数 / 49B 激活参数 / 1M 上下文',
          '1.6B / 49T / 1K',
          '49B 总参数 / 1.6T 激活',
          '只有 4K 上下文',
        ],
        0,
        '这是当前公开模型卡列出的核心规格。',
      ),
      _question(
        'q2',
        'CSA/HCA 主要针对什么问题？',
        ['长上下文中的计算与缓存效率', '用户登录密码', '屏幕分辨率', '邮件协议'],
        0,
        '它们改变长上下文注意力的计算方式。',
      ),
      _question(
        'q3',
        '面对未公开的内部 kernel 细节，正确做法是？',
        ['把猜测当官方事实', '标注为未知或合理推断并查证', '永远不学习', '随机编造数字'],
        1,
        '工程分析必须标注证据等级。',
      ),
    ],
  ),
  _chapter(
    id: 'capstone.tiny-lm.01',
    phase: '毕业项目',
    order: 11,
    title: '手搓一个字符级语言模型',
    description: '从数据、tokenizer 到生成，完成第一条闭环。',
    objectives: ['训练一个 bigram 模型', '生成文本', '解释概率与评估'],
    lesson:
        '''先用字符作为 token，统计 P(下一个字符 | 当前字符)，再用采样生成文本。这个模型远小于 DeepSeek，但它已经具备语言模型的闭环：数据、词表、条件概率、生成和评估。

后续再把计数表换成 embedding、矩阵乘法、attention 和梯度训练。''',
    questions: [
      _question(
        'q1',
        'bigram 模型主要估计什么？',
        ['P(下一个 token | 当前 token)', 'GPU 温度', '用户密码概率', '固定答案表'],
        0,
        'bigram 只使用一个前置 token。',
      ),
      _question(
        'q2',
        '手搓小模型最重要的学习价值是什么？',
        ['能逐步看见完整数据流', '一定超过大型模型', '不需要数据', '不需要评估'],
        0,
        '机制透明比规模相同更重要。',
      ),
      _question(
        'q3',
        'perplexity 等评估指标应该做什么？',
        ['帮助衡量模型对数据的预测能力', '自动证明模型有意识', '替代所有测试', '隐藏错误'],
        0,
        '评估指标是可观测的代理，不是意识证明。',
      ),
    ],
  ),
];

CourseChapter? courseChapterById(String chapterId) {
  for (final chapter in courseCatalog) {
    if (chapter.chapterId == chapterId) return chapter;
  }
  return null;
}
