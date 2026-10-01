# 其他 AI 工具如何使用蓝图

从仓库根目录开始，读取 [AGENTS.md](../AGENTS.md)、[AI Quickstart](ai-quickstart.md) 和 [技能索引](../.agent/skills/index.yaml)，再读任务对应的一个或少量技能。

可以把下面这段任务交给尚未接入的工具：

> 按此仓库的 AGENTS.md 和 docs/ai-quickstart.md，选读 .agent/skills/index.yaml 中与任务相关的 Skill。使用 blueprint.py 的真实帮助和受测样例完成实现、注入/导航与测试。保留已有工作区修改；最后列出实际执行结果与未执行项。

新建项目还要提供名称、目标目录、组织标识和平台；新增 Feature 提供目标成员、功能名及 presentation/api/local 类型。缺少业务细节时先完成与其无关的本地工作，只有无法合理判断的关键输入才需要澄清。

自动接入差异见 [发现机制](agent-skill-rule-discovery.md)。无需安装作者个人技能或访问作者的其他项目。
