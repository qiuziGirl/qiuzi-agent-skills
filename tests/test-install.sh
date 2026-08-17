#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
installer="$repo_root/scripts/install.sh"
test_root="$(mktemp -d)"

cleanup() {
  rm -rf -- "$test_root"
}
trap cleanup EXIT

assert_file() {
  [[ -f "$1" ]] || {
    echo "缺少文件：$1" >&2
    exit 1
  }
}

new_test_skill() {
  local root="$1"
  local name="$2"
  mkdir -p "$root/$name"
  cat > "$root/$name/SKILL.md" <<EOF
---
name: $name
description: 用于安装脚本测试的示例 Skill。
---

# $name
EOF
}

source_root="$test_root/source-skills"
target_root="$test_root/installed-skills"
new_test_skill "$source_root" "sample-skill"
new_test_skill "$source_root" "other-skill"

bash "$installer" --source-root "$source_root" --target-root "$target_root" --skill sample-skill
assert_file "$target_root/sample-skill/SKILL.md"
[[ ! -e "$target_root/other-skill" ]] || {
  echo "安装脚本安装了未指定的 Skill。" >&2
  exit 1
}

printf '旧版本内容\n' > "$target_root/sample-skill/legacy.txt"
set +e
bash "$installer" --source-root "$source_root" --target-root "$target_root" --skill sample-skill >"$test_root/no-force.out" 2>&1
no_force_status=$?
set -e
[[ "$no_force_status" -ne 0 ]] || {
  echo "未传 --force 时覆盖了已安装 Skill。" >&2
  exit 1
}
[[ "$(cat "$target_root/sample-skill/legacy.txt")" == "旧版本内容" ]] || {
  echo "拒绝覆盖后原有内容被修改。" >&2
  exit 1
}

bash "$installer" --source-root "$source_root" --target-root "$target_root" --skill sample-skill --force
[[ ! -e "$target_root/sample-skill/legacy.txt" ]] || {
  echo "传入 --force 后保留了旧文件。" >&2
  exit 1
}

for sensitive_case in export-api-key bare-token access-token refresh-token pem-block; do
  sensitive_root="$test_root/sensitive-$sensitive_case"
  new_test_skill "$sensitive_root" "sample-skill"
  case "$sensitive_case" in
    export-api-key)
      printf 'export API_KEY=example-not-a-real-secret\n' > "$sensitive_root/sample-skill/settings.sh"
      ;;
    bare-token)
      printf 'TOKEN=example-not-a-real-secret\n' > "$sensitive_root/sample-skill/settings.txt"
      ;;
    access-token)
      printf 'accessToken=example-not-a-real-secret\n' > "$sensitive_root/sample-skill/settings.txt"
      ;;
    refresh-token)
      printf 'refreshToken=example-not-a-real-secret\n' > "$sensitive_root/sample-skill/settings.txt"
      ;;
    pem-block)
      cat > "$sensitive_root/sample-skill/notes.md" <<'EOF'
-----BEGIN PRIVATE KEY-----
not-a-real-key
-----END PRIVATE KEY-----
EOF
      ;;
  esac

  set +e
  bash "$installer" --source-root "$sensitive_root" --target-root "$test_root/sensitive-target-$sensitive_case" --skill sample-skill >"$test_root/$sensitive_case.out" 2>&1
  sensitive_status=$?
  set -e
  [[ "$sensitive_status" -ne 0 ]] || {
    echo "安装脚本未拒绝敏感内容：$sensitive_case" >&2
    exit 1
  }
done

set +e
bash "$installer" --skill >"$test_root/missing-value.out" 2>&1
missing_value_status=$?
set -e
[[ "$missing_value_status" -eq 2 ]] || {
  echo "缺少 --skill 值时未返回参数错误。" >&2
  exit 1
}
grep -q '缺少值' "$test_root/missing-value.out" || {
  echo "缺少 --skill 值时未输出受控错误信息。" >&2
  exit 1
}

echo 'test-install.sh: PASS'
