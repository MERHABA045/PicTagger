#!/bin/zsh

setopt null_glob

trap 'echo "\n🚨 中断されました。QuickLookを閉じます。"; killall qlmanage &>/dev/null; exit 1' INT TERM QUIT

# ========== 設定 ==========
photographers=("NK" "JU" "TH" "HI")

# ========== 1 フォルダ指定・オプション解析 ==========
cloud_mode=0
no_initial_mode=0
top_dir=""
members_file=""

for arg in "$@"; do
  case $arg in
    -c) cloud_mode=1 ;;
    -n) no_initial_mode=1 ;;
    *)
      if [[ -z "$top_dir" ]]; then
        top_dir="$arg"
      fi
      ;;
  esac
done

# 通常モードのリネームフォルダが未指定の場合終了
if (( ! cloud_mode )); then
  if [[ -z "$top_dir" || ! -d "$top_dir" ]]; then
    echo "📂 フォルダを指定（例: ./script.zsh /path/to/photo）"
    exit 1
  fi
fi

# ========== 2 クラウドモード入力 ==========
if (( cloud_mode )); then
  echo "☁️ クラウドモード起動　"
  echo "📂 タグ付けする写真フォルダをドラッグ＆ドロップ："
  read top_dir
  top_dir="${top_dir//\'/}"

  if [[ ! -d "$top_dir" ]]; then
    echo "❌️ 無効なディレクトリ：$top_dir"
    exit 1
  fi

  echo "\n📄 リネームファイルをドラッグ＆ドロップ："
  read members_file
  members_file="${members_file//\'/}"

  if [[ ! -f "$members_file" ]]; then
    echo "❌️ 無効なファイル：$members_file"
    exit 1
  fi

  log_file="${members_file:h}/log_$(date +'%Y%m%d_%H%M%S').txt"

  echo ""
  echo "============================"
  echo "📂 フォルダ: $top_dir"
  echo "📄 リネーム: $members_file"
  echo "ログ出力: $log_file"
  echo "============================"
  echo ""
  echo "⚠️ この設定でよろしいですか？ (y/N)"
  read yn
  if [[ "$yn" != "y" && "$yn" != "Y" ]]; then
    echo "🚪 処理をキャンセルしました"
    exit 0
  fi
else
  # ========== 3 通常モード ==========
  backup_dir="${top_dir}_backup_$(date +'%Y%m%d_%H%M%S')"
  echo "バックアップフォルダ：$backup_dir"
  cp -a "$top_dir" "$backup_dir"

  members_file="${top_dir:h}/members.txt"
  if [[ ! -f "$members_file" ]]; then
    echo "⚠️ members.txtは無効なファイル：$members_file"
    exit 1
  fi
  log_file="${top_dir}/log_$(date +'%Y%m%d_%H%M%S').txt"
fi

# ========== 4 undoスクリプト生成 ==========
undo_script="${log_file:h}/undo_$(date +'%Y%m%d_%H%M%S').sh"
echo "#!/bin/zsh" > "$undo_script"
echo "" >> "$undo_script"
chmod +x "$undo_script"

# ========== 5 対象ファイル取得 ==========
files=("${(@f)$(find "$top_dir" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.heic' \))}")
echo "\n📸 画像ファイル数: ${#files}"

# ========== 6 カメラマンイニシャル選択 ==========
if (( ! no_initial_mode )); then
  echo "👤 カメラマン選択"
  initial=$(printf "%s\n" "${photographers[@]}" | fzf --prompt="カメラマン: ")
  initial="${(U)initial}"
  if [[ -z "$initial" ]]; then
    echo "⚠️ カメラマンが選択されませんでした"
    exit 1
  fi
  echo "✅️ カメラマン: $initial"
fi

# ========== 7 個別処理 ==========
count=0
for filepath in $files; do
  filename="${filepath:t}"
  name="${filename%.*}"
  ext="${filepath:e:l}"
  [[ "$ext" == "jpeg" ]] && ext="JPG" || ext="${ext:u}"

  # 既に処理済みならスキップ
  if (( ! no_initial_mode )); then
    skip=0
    for p in $photographers; do
      [[ "$name" == *"_${p}" ]] && skip=1 && break
    done
    (( skip )) && continue
  fi

  echo "👀 プレビュー: $filename"
  qlmanage -p "$filepath" &>/dev/null &
  sleep 1

  # 被写体選択
  selected=$(cat "$members_file" | fzf --multi --exact --tiebreak=index --prompt="被写体: " --bind 'space:clear-query')
  [[ $? -ne 0 ]] && echo "🚨 fzfで中断（ctrl+c）のため終了" && killall qlmanage &>/dev/null && exit 1
  killall qlmanage &>/dev/null

  # fzfが空欄を許容するモード　fzf --no-select　を有効にさせない限り次のif文は 偽
  if [[ -z "$selected" ]]; then
    subject="⚠️"
  else
    selected_names=("${(@f)$(echo "$selected" | awk '{print $1}')}")
    subject="${(j:_:)selected_names}"
  fi

  # ログ記録
  if (( no_initial_mode )); then
    echo "${filename},${subject}" >> "$log_file"
  else
    echo "${filename},${subject},${initial}" >> "$log_file"
  fi

  # リネームパス作成
  if (( no_initial_mode )); then
    final_path="${top_dir}/${subject}_${name}.${ext}"
  else
    final_path="${top_dir}/${subject}_${name}_${initial}.${ext}"
  fi

  n=1
  while [[ -e "$final_path" ]]; do
    if (( no_initial_mode )); then
      final_path="${top_dir}/${subject}_${name}_${n}.${ext}"
    else
      final_path="${top_dir}/${subject}_${name}_${initial}_${n}.${ext}"
    fi
    ((n++))
  done

  # mv & undo 追記
  mv "$filepath" "$final_path"
  echo "mv \"$final_path\" \"$filepath\"" >> "$undo_script"
  ((count++))
done

# ========== 8 終了処理 ==========
print -P "✅ 完了！合計 ${count} ファイルをリネーム　🔄復元用スクリプト：$undo_script\n"