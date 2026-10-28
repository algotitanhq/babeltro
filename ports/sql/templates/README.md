# SQL templates

The newer `.sql` files are generated: each `F32(expr)` in a `.tpl` here
expands into Veltkamp's float32 rounding of `expr`
(`v*536870913.0 - (v*536870913.0 - v)`), which is unreadable to write by
hand at every float32 step.

    python3 expand.py starfield.tpl ../starfield.sql

The finale is assembled from `finale.head`, `finale.tpl` and `finale.body`.
