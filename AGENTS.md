# Agent Guidelines for Rust Code Quality

This document provides guidelines for maintaining high-quality Rust code.
These rules MUST be followed by all AI coding agents and contributors.

## Your Core Principles

All code you write MUST be fully optimized.

"Fully optimized" includes:

- maximizing algorithmic big-O efficiency for memory and runtime
- avoiding unnecessary allocations, copies and `.clone()` calls
- using parallelization and vectorization where appropriate
- following idiomatic Rust and the [Rust API Guidelines](https://rust-lang.github.io/api-guidelines/)
  (e.g. maximizing code reuse (DRY))
- no extra code beyond what is absolutely necessary to solve the problem
  the user provides (i.e. no technical debt)

Back every non-obvious optimization with a benchmark. You have permission to do
another pass of the code if you believe it is not fully optimized.

## Preferred Tools

- Use `cargo` for builds and dependency management. Add dependencies with `cargo add`.
- Pin the toolchain in `rust-toolchain.toml` and set `rust-version` (MSRV) and the latest
  stable `edition` in `Cargo.toml`.
- Use `serde` with `serde_json` for JSON loading/dumping.
- Use `tracing` for diagnostics: `tracing::error!` instead of `eprintln!`, never `println!`
  for logging. Binaries install a subscriber (`tracing-subscriber`) in `main`; libraries
  never install one.
- Use `thiserror` for error types in libraries and `anyhow` in binaries.
- Use `clap` with the derive API for command line interfaces.
- Use `rayon` for CPU-bound data parallelism. Use `tokio` only for I/O-bound work; do not
  introduce `async` otherwise.
- For data science:
  - **ALWAYS** use `polars` for data frame manipulation.
  - If a `polars` data frame will be printed, **NEVER** simultaneously print
    the number of entries in the data frame nor the schema as it is redundant.
  - **NEVER** ingest more than 10 rows of a data frame at a time. Only analyze
    subsets of data to avoid overloading your memory context.
- For creating databases:
  - Do not denormalize unless explicitly prompted to do so.
  - Always use the most appropriate data type, such as `DATETIME/TIMESTAMP` for
    date time-related fields.
  - Use `ARRAY` data types for nested fields. **NEVER** save as `TEXT/STRING`.
  - Prefer `sqlx` with compile-time checked queries (`query!` / `query_as!`).

## Code Style and Formatting

- **MUST** use meaningful, descriptive variable and function names
- **MUST** format with `rustfmt` using its defaults (4 spaces, `max_width = 100`)
- **NEVER** use emoji, or Unicode that emulates emoji (e.g. ✓, ✗).
  The only exception is when writing tests and testing the impact of multi byte
  characters.
- Use `snake_case` for functions, variables and modules, `UpperCamelCase` for types,
  traits and enum variants, `SCREAMING_SNAKE_CASE` for constants and statics
- Follow the conversion naming conventions: `as_` (free, borrowed), `to_` (expensive),
  `into_` (consumes `self`). Getters have no `get_` prefix

## Documentation

- **MUST** document every public item with `///` and every crate and public module with `//!`,
  enforced by the `missing_docs` lint
- **MUST** add an `# Errors` section to every public function returning `Result`, a `# Panics`
  section to every public function that can panic, and a `# Safety` section to every
  `unsafe fn`, enforced by clippy
- Describe parameters and the return value in prose; Rust does not use a formal
  parameter section
- Doc comments are **not** required for private items; add one only where the reasoning is
  non-obvious, and document *why* rather than *how to call*
- Include an `# Examples` section for complex public functions. Examples are compiled and run
  as doctests, so they must stay correct
- Link to other items with intra-doc links (`` [`TypeName`] ``)
- Keep comments up-to-date with code changes

Example doc comment:

```rust
/// Parses a TCP port from user supplied text.
///
/// Leading and trailing whitespace is ignored. Port `0` is rejected because it asks the
/// operating system to choose a port, which is never what a caller of this function means.
///
/// # Errors
///
/// Returns [`ParsePortError::NotANumber`] if `input` is not a decimal integer, and
/// [`ParsePortError::OutOfRange`] if it is `0` or greater than `65535`.
///
/// # Examples
///
/// ```
/// use my_crate::{ParsePortError, parse_port};
///
/// let port = parse_port(" 8080 ")?;
/// assert_eq!(port.get(), 8080);
/// # Ok::<(), ParsePortError>(())
/// ```
pub fn parse_port(input: &str) -> Result<NonZeroU16, ParsePortError> {
```

## Types

- Make invalid states unrepresentable: use enums instead of boolean flags or magic strings,
  and newtypes instead of bare primitives for values with a meaning (IDs, units, ports)
- **NEVER** use `dyn Any` or stringly typed data (`String` for a closed set of values,
  `HashMap<String, Value>` for structured data) unless absolutely necessary
- `match` on your own enums exhaustively, without a `_` arm, so that adding a variant is a
  compile error at every site that must handle it. Mark public enums that may grow
  `#[non_exhaustive]`
- **NEVER** use `as` for numeric conversions that can truncate, wrap or lose sign; use
  `From` / `TryFrom`
- Prefer generics and `impl Trait` (static dispatch); use `dyn Trait` only for heterogeneous
  collections or where compile time or binary size matters
- Annotate types where inference would obscure intent (e.g. the target of `collect` or `parse`)
- Shadowing is acceptable when a value changes type along a pipeline
  (`let port = port.trim(); let port: u16 = port.parse()?;`)
- Suppress a lint only with `#[expect(lint_name, reason = "...")]`, never `#[allow]`. Fix the
  root cause wherever possible

## Ownership and Borrowing

- Accept borrowed parameters: `&str` over `&String`, `&[T]` over `&Vec<T>`, `&Path` or
  `impl AsRef<Path>` over `&PathBuf`
- **NEVER** call `.clone()` to silence the borrow checker; clone only where ownership is
  actually needed
- Use `Cow` when a value is usually borrowed but sometimes owned
- Pre-allocate with `with_capacity` when the final size is known
- Prefer iterator chains over index loops, and avoid intermediate `collect()` calls
- Avoid `Rc<RefCell<T>>` and `Arc<Mutex<T>>` unless shared mutable state is truly required;
  restructure ownership first

## Runtime Validation

The compiler only proves properties of values the program constructed itself. Values that
enter from outside are unchecked until validated.

- **Runtime checks belong where values cross a trust boundary; the type system is enough
  everywhere else**
- Trust boundaries are: public constructors and functions of a library, command line
  arguments, environment variables, configuration and file contents, file system paths,
  network input and FFI
- Parse, don't validate: convert unchecked input once into a type that can only hold valid
  values (private fields plus a constructor returning `Result`, or `TryFrom`). Code behind
  the boundary takes the validated type and does not check again
- Invalid input returns an `Err`. `assert!` is only for invariants whose violation is a bug;
  use `debug_assert!` for internal invariants too costly to check in release builds

## Error Handling

- **NEVER** silently discard errors: no `let _ = fallible();` or `.ok()` to drop an error
  without logging it or stating why it is safe to ignore
- **NEVER** use `.unwrap()` outside tests. Use `.expect("...")` only for invariants that
  cannot fail, with a message stating the invariant
- Propagate errors with `?`. Add context at the point of failure (`anyhow::Context` in
  binaries, a variant carrying its `#[source]` in libraries)
- Libraries expose typed error enums implementing `std::error::Error`; **NEVER** expose
  `anyhow::Error` in a public library API
- **NEVER** panic in library code on recoverable conditions
- Use RAII (`Drop`) for resource cleanup; never rely on manual cleanup calls
- Error messages are lowercase, concise and without trailing punctuation

## Unsafe Code

- **NEVER** write `unsafe` code unless absolutely necessary. Crates forbid it by default
  (`unsafe_code = "forbid"`); lifting that requires an explicit decision
- Every `unsafe` block **MUST** have a `// SAFETY:` comment explaining why its invariants hold

## Function Design

- **MUST** keep functions focused on a single responsibility
- Limit function parameters to 5 or fewer; group the rest into a struct or use a builder
- Use an enum instead of a `bool` parameter
- Return early to reduce nesting; use `let ... else` for early exits on patterns
- Mark functions whose result must not be ignored with `#[must_use]`

## Type Design

- **MUST** keep types focused on a single responsibility
- **MUST** keep `new` simple; use a builder for types with many optional fields
- Eagerly derive common traits on public types where they make sense: `Debug`, `Clone`,
  `PartialEq`, `Eq`, `Hash`, `Default`, and `Copy` for small plain data
- In libraries, gate `serde` derives behind an optional `serde` feature
- Keep fields private and expose methods; avoid methods that are not necessary
- Prefer composition and traits; **NEVER** emulate inheritance with `Deref`
- Implement `Display` instead of a custom `to_string` method

## Testing

- **MUST** write unit tests for all new functions
- Place unit tests in a `#[cfg(test)] mod tests` in the same file, integration tests in
  `tests/`, and public usage examples as doctests
- **MUST** mock what you do not own and cannot run: third party APIs, network calls, and
  hardware, through traits injected at the boundary. Prefer the real thing wherever it is
  cheap and deterministic — the file system under `tempfile::TempDir`, an in-memory
  database — because a mock of those largely asserts that the mock was called
- **MUST** use the built-in test harness (`#[test]`, `cargo test`)
- **MUST** split the test into three phases:
  - Setup, declaring every input and every expected value
  - Declaring the `system_under_test` variable, and nothing else
  - Executing the assertions against the system under test, and nothing else
- Each of these steps shall be separated by an empty line
- A test may omit the first phase when its inputs are already declared by attributes,
  which covers `rstest`'s `#[case]` and `proptest!`
- Use `rstest` for parametrized tests. Use `proptest` for property based tests where a rule
  is cheaper to state than a table of examples, such as round trips and unit conversions.
  Use it **narrowly**: parametrized tables remain the default, and property tests are a
  poor fit wherever the rule would restate the implementation
- Iterate over all enum variants (`strum::EnumIter`) rather than a hand written list, so
  that adding a variant extends the tests on its own. This is the runtime half of
  exhaustive `match`
- `.unwrap()` and `.expect()` are allowed in tests
- **NEVER** run tests you generate without first saving them in the test suite
- **NEVER** delete files created as a part of testing
- Ensure every folder used for test outputs is present in `.gitignore`
- Do not commit commented-out or `#[ignore]`d tests without a stated reason
- **Green is not complete.** Deleting a test keeps the suite green. Gate a change on the
  collected test count and the coverage number (`cargo llvm-cov`), never on exit status alone
- **Import-only coverage is not test coverage.** Modules that only hold constants, type
  aliases or re-exports are deliberately left uncovered. Do not "fix" their coverage

Example test:

```rust
#[test]
fn parse_port_rejects_zero() {
    let input = "0";
    let expected_error = ParsePortError::OutOfRange;

    let system_under_test = parse_port(input);

    assert_eq!(system_under_test, Err(expected_error));
}
```

## Imports and Dependencies

- **MUST** avoid glob imports (`use module::*`), except a crate's `prelude` and
  `use super::*` in test modules
- **MUST** declare dependencies in `Cargo.toml`; in a workspace, declare versions once
  under `[workspace.dependencies]`
- Enable only the crate features you use (`default-features = false` where possible)
- Prefer the standard library; add a crate only when it removes substantial code
- Organize imports: standard library, third-party, then `crate::` / `super::`
- Commit `Cargo.lock`

## Lint Configuration

If `Cargo.toml` has no `[lints]` table, add this one (in a workspace, under
`[workspace.lints]` with `lints.workspace = true` in each member):

```toml
[lints.rust]
unsafe_code = "forbid"
missing_docs = "warn"

[lints.clippy]
pedantic = { level = "warn", priority = -1 }
unwrap_used = "warn"
dbg_macro = "warn"
todo = "warn"
allow_attributes = "warn"
allow_attributes_without_reason = "warn"
```

and a `clippy.toml` containing:

```toml
allow-unwrap-in-tests = true
```

## Security

- **NEVER** store secrets, API keys, or passwords in code. Only store them in `.env`
  (loaded with `dotenvy`).
  - Ensure `.env` is declared in `.gitignore`.
  - **NEVER** print or log URLs to console if they contain an API key.
- **MUST** use environment variables for sensitive configuration
- Wrap secrets in `secrecy::SecretString` so that `Debug` output redacts them
- **NEVER** log sensitive information (passwords, tokens, PII)
- Check dependencies for advisories and licenses with `cargo deny check`

## Version Control

- **MUST** write clear, descriptive commit messages
- **NEVER** commit commented-out code; delete it
- **NEVER** commit `dbg!`, debug `println!`, `todo!()` or `unimplemented!()`
- **NEVER** commit credentials or sensitive data

## Tools

- **MUST** use `cargo fmt` for formatting
- **MUST** use `cargo clippy --all-targets --all-features -- -D warnings` for linting
- Use `cargo test` for tests (`cargo nextest` does not run doctests; run
  `cargo test --doc` alongside it)
- Use `cargo llvm-cov` for coverage, `cargo deny` for dependency checks, and `criterion`
  for benchmarks

## Before Committing

- [ ] `cargo fmt --check` passes
- [ ] `cargo clippy --all-targets --all-features -- -D warnings` passes
- [ ] `cargo test --all-features` passes, including doctests
- [ ] `RUSTDOCFLAGS="-D warnings" cargo doc --no-deps` passes
- [ ] All public items are documented, including `# Errors`, `# Panics` and `# Safety`
- [ ] No commented-out code, `dbg!`, `todo!()` or `.unwrap()` outside tests
- [ ] No hard-coded credentials

---

**Remember:** Prioritize clarity and maintainability over cleverness.
