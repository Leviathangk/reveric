# 代码风格规则

## 控制流

- **所有控制流语句（`if`、`else`、`for`、`while`、`do-while`）必须使用大括号 `{}`**，即使只有单条语句。
- 禁止省略大括号的单行写法，例如 `if (condition) doSomething();` 一律改为 `if (condition) { doSomething(); }`。
- 该规则通过 `curly_braces_in_flow_control_structures` lint 强制生效。
