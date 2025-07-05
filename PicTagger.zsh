#!/bin/zsh

setopt null_glob

# プレビュー中に中断 → 終了できるように trap
trap 'echo "\n🚨 中断されました。QuickLookを閉じます。"; killall qlmanage &>/dev/null; exit 1' INT TERM QUIT

# ========== 設定 ==========
# カメラマンイニシャル（ここを編集するだけでOK）
photographers=("NK" "JU" "TH" "HI")

# ========== 1 フォルダ指定 ==========
top_dir="$1"
if [[ -z "$top_dir" || ! -d "$top_dir" ]]; then
  echo "📂 フォルダを指定（例: ./script.zsh /path/to/photo）"
  exit 1
fi

# ========== 2 バックアップ ==========
backup_dir="${top_dir}_backup_$(date +'%Y%m%d_%H%M%S')"
cp -a "$top_dir" "$backup_dir"

# ========== 3 members.txt 確認 ==========
members_file="${top_dir:h}/members.txt"
if [[ ! -f "$members_file" ]]; then
  echo "⚠️ members.txt が見つかりません: $members_file"
  exit 1
fi

# ========== 4 対象ファイルを取得 ==========
files=("${(@f)$(find "$top_dir" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.heic' \))}")
echo "📸 画像ファイル数: ${#files}"

# ========== 5 カメラマンイニシャル選択 ==========
echo "\n👤 カメラマン選択"
initial=$(printf "%s\n" "${photographers[@]}" | fzf --prompt="カメラマン: ")
initial="${(U)initial}"
if [[ -z "$initial" ]]; then
  echo "⚠️ カメラマンが選択されませんでした"
  exit 1
fi
echo "✅️ カメラマン: $initial"

# ========== 6 ログ準備 ==========
log_file="${top_dir}/log_$(date +'%Y%m%d_%H%M%S').txt"

# ========== 7 個別処理 ==========
count=0
for filepath in $files; do
  filename="${filepath:t}"
  name="${filename%.*}"
  ext="${filepath:e:l}"
  if [[ "$ext" == "jpeg" ]]; then
    ext="JPG"
  else
    ext="${ext:u}"
  fi

  # === 既に処理済みならスキップ ===
  skip=0
  for p in $photographers; do
    if [[ "$name" == *"_${p}" ]]; then
      skip=1
      break
    fi
  done
  if (( skip )); then
    continue
  fi

  # === プレビュー ===
  echo "👀 プレビュー: $filename"
  qlmanage -p "$filepath" &>/dev/null &

  sleep 1

  # === 被写体選択 ===
  selected=$(cat "$members_file" | fzf --multi --exact --tiebreak=index --prompt="被写体: " --bind 'space:clear-query')

  if [[ $? -ne 0 ]]; then
    echo "🚨 fzfで中断（ctrl+c）されたので処理を終了します。"
    killall qlmanage &>/dev/null
    exit 1
  fi

  killall qlmanage &>/dev/null

  # 被写体が空ならプレースホルダー
  if [[ -z "$selected" ]]; then
    subject="⚠️"
  else
    selected_names=("${(@f)$(echo "$selected" | awk '{print $1}')}")
    subject="${(j:_:)selected_names}"
  fi

  # === ログ記録 ===
  echo "${filename},${subject},${initial}" >> "$log_file"

  # === リネーム ===
  final_path="${top_dir}/${subject}_${name}_${initial}.${ext}"
  if [[ -e "$final_path" ]]; then
    n=1
    while [[ -e "${top_dir}/${subject}_${name}_${initial}_${n}.${ext}" ]]; do
      ((n++))
    done
    final_path="${top_dir}/${subject}_${name}_${initial}_${n}.${ext}"
  fi

  mv "$filepath" "$final_path"
  ((count++))
done

print -P "\n✅ 処理完了！合計 ${count} ファイルをリネーム" # \nログ: $log_file"
