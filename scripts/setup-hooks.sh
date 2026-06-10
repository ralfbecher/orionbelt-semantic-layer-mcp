#!/bin/bash
# Install the project's git pre-commit hook.
#
# The hook runs `ruff format --check` and `ruff check` on server.py before each
# commit, catching the kind of formatting/lint issues that broke CI in v2.8.2.
# Re-run this script any time the hook changes.

set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"
HOOKS_DIR="$REPO_ROOT/.git/hooks"
HOOK_PATH="$HOOKS_DIR/pre-commit"

mkdir -p "$HOOKS_DIR"

cat > "$HOOK_PATH" <<'HOOK'
#!/bin/bash
# Pre-commit hook to ensure code quality before committing
# Prevents the formatting issues that broke CI in v2.8.2

set -e

echo "Running pre-commit checks..."

# Check if ruff is available
if command -v ruff >/dev/null 2>&1; then
    RUFF_CMD="ruff"
elif command -v uv >/dev/null 2>&1; then
    RUFF_CMD="uv run ruff"
else
    echo "Warning: ruff not found, skipping formatting checks"
    exit 0
fi

# Check formatting
echo "Checking code formatting..."
if ! $RUFF_CMD format --check server.py >/dev/null 2>&1; then
    echo "❌ Formatting issues detected!"
    echo "Run 'ruff format server.py' to fix formatting"
    exit 1
fi
echo "✓ Formatting OK"

# Check linting
echo "Checking linting..."
if ! $RUFF_CMD check server.py; then
    echo "❌ Linting issues detected!"
    echo "Fix the issues above before committing"
    exit 1
fi
echo "✓ Linting OK"

echo "✓ All pre-commit checks passed"
HOOK

chmod +x "$HOOK_PATH"

echo "✓ Installed pre-commit hook at $HOOK_PATH"
