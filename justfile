# Short commands for the project tooling. Run `just` to list them.

set positional-arguments

directory_name := kebabcase(file_name(justfile_directory()))

# List all recipes
default:
    @just --list --unsorted

# Rename the package and pin the latest stable toolchain, MSRV and edition
init-project name=directory_name: && check
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ ! "$1" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
        echo "error: invalid package name '$1'" >&2
        exit 1
    fi
    rustup update --no-self-update stable
    version="$(rustc +stable --version | cut -d ' ' -f 2)"
    probe="$(mktemp -d)"
    trap 'rm -rf "$probe"' EXIT
    cargo +stable new --quiet --vcs none "$probe/probe"
    edition="$(sed -n 's/^edition = //p' "$probe/probe/Cargo.toml")"
    sed -i "s/^channel = .*/channel = \"$version\"/" rust-toolchain.toml
    sed -i \
        -e "0,/^name = .*/s//name = \"$1\"/" \
        -e "s/^edition = .*/edition = $edition/" \
        -e "s/^rust-version = .*/rust-version = \"$version\"/" \
        Cargo.toml
    rustup toolchain install
    cargo update

# Install the cargo subcommands used by the recipes
install-tools:
    cargo install --locked cargo-deny cargo-llvm-cov

# Build the project
build *args:
    cargo build "$@"

# Run the binary with the given arguments
run *args:
    cargo run -- "$@"

# Format all code
fmt *args:
    cargo fmt "$@"

# Lint all targets and features, denying warnings
lint:
    cargo clippy --all-targets --all-features -- -D warnings

# Run all tests, including doctests
test *args:
    cargo test --all-features "$@"

# Build the documentation, denying warnings
doc *args:
    RUSTDOCFLAGS="-D warnings" cargo doc --no-deps "$@"

# Measure test coverage (e.g. `just cov --open` for the HTML report)
cov *args:
    cargo llvm-cov --all-features "$@"

# Check dependencies for advisories, licenses, duplicates and sources
deny:
    cargo deny check

# Run every check required before committing
check: (fmt "--check") lint test doc deny
