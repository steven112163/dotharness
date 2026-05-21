# Naming Conventions

## General

- Describe what something is or does, not how it works internally.
- Use domain terminology from the project glossary.
- Universally understood abbreviations are fine: `id`, `url`, `db`, `config`. Avoid `usr`, `mgr`, `proc`.
- Stay consistent. If the codebase says `remove`, do not introduce `delete` for the same action.
- Longer names for larger scopes. Single letters only for loop counters and short lambdas.

## JavaScript / TypeScript

- Variables and functions: `camelCase`.
- Classes, types, interfaces: `PascalCase`.
- True constants: `UPPER_SNAKE_CASE`.
- Enums: `PascalCase` name and members.
- Booleans: `is`, `has`, `can`, `should` prefix.
- Event handlers: `on` or `handle` prefix.
- Files: `kebab-case.ts` for modules, `PascalCase.tsx` for React components.

## Python

- Variables, functions, modules: `snake_case`.
- Classes: `PascalCase`.
- Constants: `UPPER_SNAKE_CASE`.
- Private members: single underscore prefix `_name`.
- Type variables: `PascalCase` with `T` suffix: `ItemT`, `ResponseT`.

## Go

- Exported: `PascalCase`. Unexported: `camelCase`.
- Interfaces: behavior-describing, often ending in `-er` (`Reader`, `Closer`).
- Packages: short, lowercase, single word. No underscores or hyphens.
- Acronyms: all caps when standalone (`ID`, `URL`), otherwise `Id`, `Url`.
- Receivers: one or two letter abbreviation of the type.

## Rust

- Variables, functions, modules: `snake_case`.
- Types, traits, enums: `PascalCase`.
- Constants and statics: `UPPER_SNAKE_CASE`.
- Lifetimes: short lowercase (`'a`, `'ctx`).
- Crate names: `kebab-case` in Cargo.toml, `snake_case` in code.

## Database

- Tables: `snake_case`, plural (`users`, `order_items`).
- Columns: `snake_case`, singular (`user_id`, `created_at`).
- Primary keys: `id`. Foreign keys: `<table_singular>_id`.
- Indexes: `idx_<table>_<columns>`.
- Migrations: `<timestamp>_<description>`.
