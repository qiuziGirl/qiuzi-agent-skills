#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
source_root="$repo_root/skills"
target_root="$HOME/.agents/skills"
force=0
skills=()
staging_path=""

cleanup() {
  if [[ -n "$staging_path" && -d "$staging_path" ]]; then
    rm -rf -- "$staging_path"
  fi
}
trap cleanup EXIT

usage() {
  cat <<'EOF'
用法：
  ./scripts/install.sh --skill <skill-name> [--skill <skill-name> ...] [选项]

选项：
  --source-root <path>  Skill 源目录，默认是仓库中的 skills/
  --target-root <path>  安装目录，默认是 ~/.agents/skills
  --skill <name>        要安装的 Skill，可重复传入
  --force               覆盖同名已安装 Skill
  -h, --help            显示帮助
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-root)
      if [[ $# -lt 2 || -z "${2:-}" || "$2" == --* ]]; then
        echo "参数 --source-root 缺少值。" >&2
        usage >&2
        exit 2
      fi
      source_root="$2"
      shift 2
      ;;
    --target-root)
      if [[ $# -lt 2 || -z "${2:-}" || "$2" == --* ]]; then
        echo "参数 --target-root 缺少值。" >&2
        usage >&2
        exit 2
      fi
      target_root="$2"
      shift 2
      ;;
    --skill)
      if [[ $# -lt 2 || -z "${2:-}" || "$2" == --* ]]; then
        echo "参数 --skill 缺少值。" >&2
        usage >&2
        exit 2
      fi
      skills+=("$2")
      shift 2
      ;;
    --force)
      force=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "未知参数：$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ${#skills[@]} -eq 0 ]]; then
  echo "至少需要一个 --skill 参数。" >&2
  exit 2
fi

if [[ ! -d "$source_root" ]]; then
  echo "Skill 源目录不存在：$source_root" >&2
  exit 1
fi

validate_skill() {
  local skill_name="$1"
  local skill_path="$source_root/$skill_name"
  local skill_file="$skill_path/SKILL.md"

  [[ "$skill_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
    echo "非法 Skill 名称：$skill_name" >&2
    return 1
  }
  [[ -d "$skill_path" && -f "$skill_file" ]] || {
    echo "源 Skill 不存在或缺少 SKILL.md：$skill_name" >&2
    return 1
  }

  local declared_name
  declared_name="$(sed -n '/^---[[:space:]]*$/,/^---[[:space:]]*$/p' "$skill_file" | sed -n 's/^[[:space:]]*name[[:space:]]*:[[:space:]]*//p' | head -n 1 | tr -d "\"'[:space:]")"
  [[ "$declared_name" == "$skill_name" ]] || {
    echo "目录名与 front matter name 不一致：$skill_name" >&2
    return 1
  }

  if find "$skill_path" -type f \( -name '.env' -o -name '.env.*' -o -name '*.pem' -o -name '*.key' -o -name '*.pfx' -o -name '*.p12' -o -iname 'credential*' -o -iname 'secret*' -o -iname 'token*' \) -print -quit | grep -q .; then
    echo "Skill 包含禁止提交的敏感文件名：$skill_name" >&2
    return 1
  fi

  if grep -RIniE --exclude='*.png' --exclude='*.jpg' --exclude='*.jpeg' --exclude='*.gif' --exclude='*.pdf' --exclude='*.zip' --exclude='*.7z' --exclude='*.dll' --exclude='*.exe' '(^|[[:space:];])(export[[:space:]]+)?([[:alpha:]_$][[:alnum:]_$]*\.)*(api[_-]?key|client[_-]?secret|((aws[_-]?)?secret([_-]?(access[_-]?key|key))?)|private[_-]?key|password|(access|refresh)[_-]?token|([[:alnum:]_]*[_-])?token|authorization)[[:space:]]*[:=][[:space:]]*["'\'']?[^[:space:]]+' "$skill_path" >/dev/null || grep -RIniE --exclude='*.png' --exclude='*.jpg' --exclude='*.jpeg' --exclude='*.gif' --exclude='*.pdf' --exclude='*.zip' --exclude='*.7z' --exclude='*.dll' --exclude='*.exe' -- '-----BEGIN ([A-Z0-9]+ )*PRIVATE KEY-----' "$skill_path" >/dev/null; then
    echo "Skill 包含疑似凭据赋值：$skill_name" >&2
    return 1
  fi
}

mkdir -p "$target_root"

for skill_name in "${skills[@]}"; do
  validate_skill "$skill_name"

  source_path="$source_root/$skill_name"
  destination_path="$target_root/$skill_name"
  if [[ -e "$destination_path" && "$force" -ne 1 ]]; then
    echo "目标 Skill 已存在：$destination_path。确认覆盖后请添加 --force。" >&2
    exit 1
  fi

  staging_path="$(mktemp -d "$target_root/.${skill_name}.install.XXXXXX")"
  backup_path=""

  cp -a "$source_path/." "$staging_path/"
  if [[ -e "$destination_path" ]]; then
    backup_path="$(mktemp -d "$target_root/.${skill_name}.backup.XXXXXX")"
    rmdir "$backup_path"
    mv -- "$destination_path" "$backup_path"
  fi

  if ! mv -- "$staging_path" "$destination_path"; then
    [[ -n "$backup_path" && -e "$backup_path" && ! -e "$destination_path" ]] && mv -- "$backup_path" "$destination_path"
    exit 1
  fi

  [[ -n "$backup_path" && -e "$backup_path" ]] && rm -rf -- "$backup_path"
  staging_path=""
  echo "已安装：$skill_name -> $destination_path"
done
