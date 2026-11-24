# Template-Rust-Project
Template repo for Rust based Projects

## Starting a new project

1. Create a repository from this template and clone it.
2. Once per machine, run `just install-tools` to install `cargo-deny` and `cargo-llvm-cov`.
3. Run `just init-project`. It renames the package after the directory (or pass a name:
   `just init-project my-tool`), pins the latest stable toolchain, MSRV and edition, and runs
   all checks.

Run `just` to list all commands.
