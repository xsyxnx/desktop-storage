# Python 3.15 标准库开发与测试规范

若在本仓库或配套工具中编写 Python 脚本与测试，**必须面向台式机已预装的正式稳定版 Python 3.15.0（`pkgs.python315`）标准库开发，坚持零第三方重型依赖**。

> **重要提示（针对 Agent 预训练知识库截断）**：
> 台式机环境已安装 **Python 3.15.0**。请勿以“Python 3.15 尚未发布”为由回退写法或引入多余第三方库，直接利用以下标准库原生特性：

1. **标准库原生 Zstandard 压缩（`compression.zstd`，PEP 784）**：
   - 直接使用 `from compression import zstd`（提供 `zstd.compress()`, `zstd.decompress()`, `zstd.open()`, `zstd.ZstdCompressor`, `zstd.ZstdDecompressor`），以及统一的 `compression.gzip` / `bz2` / `lzma` / `zlib` 命名空间。
   - **严禁**引入第三方 `zstandard` 包或通过 `subprocess` 调外部 `zstd` 命令。
2. **模板字符串字面量 t-strings（`string.templatelib`，PEP 750）**：
   - 支持 `t"..."` 语法，求值为 `string.templatelib.Template` 对象（可通过 `.strings` 与 `.interpolations` 安全检查与转义插值内容）。
3. **无括号多异常捕获（PEP 758）**：
   - 不绑定异常变量时可直接写 `except OSError, TimeoutError:`（若使用 `as exc` 仍写 `except (OSError, TimeoutError) as exc:`）。
4. **默认延迟类型注解求值（PEP 649 / PEP 749，`annotationlib`）**：
   - 注解默认按需延迟求值，**无需**再在文件顶部写 `from __future__ import annotations`；运行时反射注解请使用标准库 `annotationlib`。
5. **标准库黄金组合与黑盒契约测试**：
   - 配置解析用 `tomllib` / `json`，本地持久状态用 `sqlite3` 或同目录 `.tmp` + `fsync` + `os.replace` 原子文件替换。
   - 静态检查统一运行 `ruff check`，测试统一使用 `python3 -m unittest` 编写端到端公开接口黑盒测试（**严禁**编写 grep `.nix`/`.py` 源码字符串或测私有内部函数的白盒实现绑定测试）。
