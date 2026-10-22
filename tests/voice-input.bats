#!/usr/bin/env bats
# voice-input の録音開始・停止・変換・入力の流れを、外部コマンドを偽物に差し替えて確かめる。
# 偽コマンドは呼ばれた内容を $T/calls に1行ずつ書く。

SCRIPT="$BATS_TEST_DIRNAME/../voice-input"
CTL="$BATS_TEST_DIRNAME/../voice-inputctl"
JUDGE="$BATS_TEST_DIRNAME/../voice-input-judge"

setup() {
  T="$BATS_TEST_TMPDIR"
  export HOME="$T/home"
  export XDG_RUNTIME_DIR="$T/run"
  export XDG_DATA_HOME="$T/data"
  export XDG_STATE_HOME="$T/state"
  export XDG_CONFIG_HOME="$T/config"
  unset VOICE_INPUT_LLM_MODEL
  export VOICE_INPUT_WHISPER_CLI="$T/bin/whisper-cli"
  export T
  state="$XDG_RUNTIME_DIR/voice-input"
  mkdir -p "$T/bin" "$HOME/.local/bin" "$XDG_DATA_HOME/whisper" "$state"
  : > "$XDG_DATA_HOME/whisper/ggml-small.bin"
  : > "$T/calls"
  echo reset > "$T/submap"

  # 既定の振る舞い。各テストで上書きする。
  export MOCK_VOLUME='Volume: 0.80'
  export MOCK_CURL=ok
  export MOCK_GPU_TEXT='GPUの結果'
  export MOCK_CPU_TEXT='CPUの結果'
  export MOCK_CLI=ok
  export MOCK_IME=1
  export MOCK_WTYPE=ok
  export VOICE_INPUT_CLEANUP=0
  export VOICE_INPUT_LOG=1
  export MOCK_LLM=ok
  export MOCK_LLM_TEXT='清書した結果'
  export MOCK_JUDGE=ok
  export MOCK_JUDGE_SCORE=1.68

  mock wpctl <<'EOF'
echo "wpctl $*" >> "$T/calls"
case "$1" in
  inspect) echo 'id 42, type PipeWire:Interface:Node' ;;
  get-volume) echo "$MOCK_VOLUME" ;;
esac
EOF
  mock pw-record <<'EOF'
echo "pw-record $*" >> "$T/calls"
exec sleep 30
EOF
  mock hyprctl <<'EOF'
case "$1" in
  dispatch)
    echo "hyprctl $2" >> "$T/calls"
    case "$2" in
      *voice_input_typing*) echo voice_input_typing > "$T/submap" ;;
      *reset*) echo reset > "$T/submap" ;;
    esac ;;
  submap) cat "$T/submap" ;;
esac
EOF
  mock curl <<'EOF'
out=
payload=
is_llm=0
is_judge=0
while [ "$#" -gt 0 ]; do
  [ "$1" = -o ] && out=$2
  [ "$1" = --data-binary ] && payload=$2
  case "$1" in *chat/completions) is_llm=1 ;; *systemone) is_judge=1 ;; esac
  shift
done
if [ "$is_judge" = 1 ]; then
  echo 'curl judge' >> "$T/calls"
  printf '%s' "$payload" > "$T/judge-request.json"
  case "$MOCK_JUDGE" in
    ok) jq -n --argjson score "$MOCK_JUDGE_SCORE" '{answers:{quality:{score:$score,confidence:0.4,probabilities:(if $score >= 3 then {"0":0.01,"1":0.04,"2":0.15,"3":0.6,"4":0.2} else {"0":0.08,"1":0.38,"2":0.37,"3":0.12,"4":0.05} end)}}}' > "$out" ;;
    invalid) printf '%s\n' '{"answers":{"quality":{"score":"bad"}}}' > "$out" ;;
    fail) exit 7 ;;
  esac
  exit 0
fi
if [ "$is_llm" = 1 ]; then
  echo 'curl llm' >> "$T/calls"
  printf '%s' "$payload" > "$T/llm-request.json"
  case "$MOCK_LLM" in
    ok) jq -n --arg text "$MOCK_LLM_TEXT" '{choices: [{message: {content: ({text: $text} | tojson)}}]}' > "$out" ;;
    empty) printf '%s\n' '{"choices":[{"message":{"content":"{\"text\":\"\"}"}}]}' > "$out" ;;
    invalid) printf '%s\n' 'not json' > "$out" ;;
    fail) echo 'connection refused' >&2; exit 7 ;;
  esac
  exit 0
fi
echo curl whisper >> "$T/calls"
case "$MOCK_CURL" in
  ok) printf '%s\n' "$MOCK_GPU_TEXT" > "$out" ;;
  empty) : > "$out" ;;
  fail) echo 'connection refused' >&2; exit 7 ;;
esac
EOF
  mock whisper-cli <<'EOF'
echo "whisper-cli $*" >> "$T/calls"
base=
while [ "$#" -gt 0 ]; do
  [ "$1" = -of ] && base=$2
  shift
done
if [ "$MOCK_CLI" = oom ]; then
  echo 'cudaMalloc failed: out of memory' >&2
  exit 3
fi
printf '%s\n' "$MOCK_CPU_TEXT" > "$base.txt"
EOF
  mock wl-copy <<'EOF'
echo wl-copy >> "$T/calls"
cat > "$T/clipboard"
EOF
  mock wtype <<'EOF'
echo wtype >> "$T/calls"
[ "$MOCK_WTYPE" = ok ] || exit 1
cat > "$T/typed"
EOF
  mock fcitx5-remote <<'EOF'
if [ "$#" -eq 0 ]; then
  echo "$MOCK_IME"
else
  echo "fcitx5-remote $*" >> "$T/calls"
fi
EOF
  mock_at "$HOME/.local/bin/hud" <<'EOF'
echo "hud $*" >> "$T/calls"
EOF
  mock_at "$HOME/.local/bin/hud-status" <<'EOF'
echo "hud-status $*" >> "$T/calls"
EOF

  export PATH="$T/bin:$PATH"
}

teardown() {
  if [ -f "$state/recording.pid" ]; then
    kill "$(cat "$state/recording.pid")" 2>/dev/null || true
  fi
  if [ -n "${recorder:-}" ]; then
    kill "$recorder" 2>/dev/null || true
  fi
}

mock() {
  mock_at "$T/bin/$1"
}

mock_at() {
  { echo '#!/bin/sh'; cat; } > "$1"
  chmod +x "$1"
}

# 録音中の状態を作る。録音処理の代わりに sleep を置き、元の音量を保存しておく。
start_fake_recording() {
  sleep 30 &
  recorder=$!
  echo "$recorder" > "$state/recording.pid"
  echo '42 0.80' > "$state/sink-volume"
  : > "$state/input.wav"
}

called() {
  grep -qxF "$1" "$T/calls"
}

line_of() {
  grep -nxF "$1" "$T/calls" | head -n 1 | cut -d: -f1
}

@test "1回目で出力音量を20%に下げて録音を始める" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  called 'wpctl set-volume 42 0.16'
  [ "$(cat "$state/sink-volume")" = '42 0.80' ]
  [ -f "$state/recording.pid" ]
  kill -0 "$(cat "$state/recording.pid")"
  grep -q '^pw-record --rate 16000 --channels 1 ' "$T/calls"
}

@test "ミュート中は音量を変えずに録音を始める" {
  MOCK_VOLUME='Volume: 0.80 [MUTED]'
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  ! grep -q '^wpctl set-volume' "$T/calls" || false
  [ ! -f "$state/sink-volume" ]
  [ -f "$state/recording.pid" ]
}

@test "既定の出力先が取れなくても録音を始める" {
  mock wpctl <<'MOCK'
echo "wpctl $*" >> "$T/calls"
exit 1
MOCK
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -f "$state/sink-volume" ]
  [ -f "$state/recording.pid" ]
}

@test "録音処理が死んでいたら音量を戻して新しく録音を始める" {
  echo '42 0.50' > "$state/sink-volume"
  sh -c 'exit 0' &
  dead=$!
  wait "$dead"
  echo "$dead" > "$state/recording.pid"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(line_of 'wpctl set-volume 42 0.50')" -lt "$(line_of 'wpctl set-volume 42 0.16')" ]
  [ "$(cat "$state/recording.pid")" != "$dead" ]
}

@test "2回目で録音を止め、GPU の結果を入力してクリップボードにも入れる" {
  start_fake_recording
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  ! kill -0 "$recorder" 2>/dev/null || false
  called 'wpctl set-volume 42 0.80'
  [ "$(cat "$T/typed")" = 'GPUの結果 ' ]
  [ "$(cat "$T/clipboard")" = 'GPUの結果 ' ]
  ! grep -q '^whisper-cli' "$T/calls" || false
  ! grep -q '^hud ' "$T/calls" || false
}

@test "停止後は状態ファイルを消し、submap を元に戻す" {
  start_fake_recording
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -f "$state/recording.pid" ]
  [ ! -f "$state/sink-volume" ]
  [ ! -f "$state/hud-status" ]
  [ "$(cat "$T/submap")" = reset ]
  called 'hud-status clear voice-input'
  # 文字入力は typing submap の中で行う
  [ "$(line_of 'hyprctl hl.dsp.submap("voice_input_typing")')" -lt "$(line_of wtype)" ]
  [ "$(line_of wtype)" -lt "$(line_of 'hyprctl hl.dsp.submap("reset")')" ]
}

@test "GPU が失敗したら HUD に表示して CPU で再処理する" {
  MOCK_CURL=fail
  start_fake_recording
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  called 'hud -s off --no-voice 音声入力: GPU処理失敗、CPUへ切替'
  called 'hud-status set voice-input 音声入力: CPUで処理中'
  grep -q "^whisper-cli -t 12 -m $XDG_DATA_HOME/whisper/ggml-small.bin -f $state/input.wav " "$T/calls"
  [ "$(cat "$T/typed")" = 'CPUの結果 ' ]
  grep -q 'connection refused' "$state/gpu.log"
}

@test "GPU が空の結果を返したら CPU で再処理する" {
  MOCK_CURL=empty
  start_fake_recording
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q '^whisper-cli ' "$T/calls"
  [ "$(cat "$T/typed")" = 'CPUの結果 ' ]
}

@test "VRAM 不足で whisper-cli も失敗したら HUD に表示し、何も入力しない" {
  MOCK_CURL=fail
  MOCK_CLI=oom
  start_fake_recording
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  called 'hud -s off --no-voice 音声入力: VRAM不足で処理できません'
  ! called wtype || false
  [ "$(cat "$T/submap")" = reset ]
  [ ! -f "$state/hud-status" ]
  grep -q 'out of memory' "$state/cpu.log"
}

@test "CPU モデルがなければ何も入力せずに失敗し、後片付けはする" {
  MOCK_CURL=fail
  rm "$XDG_DATA_HOME/whisper/ggml-small.bin"
  start_fake_recording
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  ! called wtype || false
  [ "$(cat "$T/submap")" = reset ]
  [ ! -f "$state/hud-status" ]
  called 'wpctl set-volume 42 0.80'
}

@test "IME が有効なら入力中だけ無効にする" {
  MOCK_IME=2
  start_fake_recording
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(line_of 'fcitx5-remote -c')" -lt "$(line_of wtype)" ]
  [ "$(line_of wtype)" -lt "$(line_of 'fcitx5-remote -o')" ]
}

@test "IME を戻すまでの待ち時間は文が長いほど延びる" {
  MOCK_IME=2
  MOCK_GPU_TEXT=$(printf 'あ%.0s' $(seq 200))
  MOCK_LLM_TEXT=$MOCK_GPU_TEXT
  start_fake_recording
  mock sleep <<'EOF'
echo "sleep $*" >> "$T/calls"
EOF
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  called 'sleep 1.055'  # 50 ミリ秒 + 201 文字（Whisper の末尾の改行を変えた空白を含む）× 5 ミリ秒
  [ "$(line_of wtype)" -lt "$(line_of 'sleep 1.055')" ]
  [ "$(line_of 'sleep 1.055')" -lt "$(line_of 'fcitx5-remote -o')" ]
}

@test "IME が無効なら IME を操作しない" {
  start_fake_recording
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  ! grep -q '^fcitx5-remote' "$T/calls" || false
}

@test "入力に失敗しても IME と submap を元に戻す" {
  MOCK_IME=2
  MOCK_WTYPE=fail
  start_fake_recording
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  called 'fcitx5-remote -o'
  [ "$(cat "$T/submap")" = reset ]
  [ ! -f "$state/hud-status" ]
}

@test "改行は空白にし、- で始まる文もそのまま入力する" {
  MOCK_GPU_TEXT='-から始まる
二行目'
  start_fake_recording
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$T/typed")" = '-から始まる 二行目 ' ]
}

@test "清書は既定で有効で、原文を残して清書結果を入力する" {
  unset VOICE_INPUT_CLEANUP
  MOCK_GPU_TEXT='えーと、火曜日、違った、水曜日の会議です。'
  MOCK_LLM_TEXT='水曜日の会議です。'
  start_fake_recording
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  called 'curl llm'
  [ "$(cat "$T/typed")" = '水曜日の会議です。' ]
  [ "$(cat "$T/clipboard")" = "$MOCK_GPU_TEXT " ]
  [ "$(line_of 'curl llm')" -gt "$(line_of 'wl-copy')" ]
  [ "$(cat "$state/transcript.txt")" = "$MOCK_GPU_TEXT" ]
  [ "$(cat "$state/transcript.cleaned.txt")" = "$MOCK_LLM_TEXT" ]
  [ "$(jq -r '.model' "$T/llm-request.json")" = gemma-4-E4B-it-qat ]
  [ "$(jq -r '.messages[1].content' "$T/llm-request.json")" = "$MOCK_GPU_TEXT " ]
  [ "$(jq -r '.chat_template_kwargs.enable_thinking' "$T/llm-request.json")" = false ]
  jq -e --arg raw "$MOCK_GPU_TEXT " --arg output "$MOCK_LLM_TEXT" '
    .whisper_model == "ggml-medium-q8_0.bin" and
    .llm_model == "gemma-4-E4B-it-qat" and .cleanup_status == "applied" and
    .raw_text == $raw and .output_text == $output and
    (.whisper_ms | type == "number") and (.cleanup_ms | type == "number") and
    (.total_ms | type == "number")
  ' "$XDG_STATE_HOME/voice-input/history.jsonl"
}

@test "清書結果の改行はスペースに変えて、Enter を押さない" {
  unset VOICE_INPUT_CLEANUP
  MOCK_GPU_TEXT='明日の会議は水曜日です。場所は第2会議室です。'
  MOCK_LLM_TEXT=$'明日の会議は水曜日です。\n場所は第2会議室です。'
  start_fake_recording
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$T/typed")" = '明日の会議は水曜日です。 場所は第2会議室です。' ]
}

@test "清書を無効にすると LLM を呼ばず原文を入力する" {
  MOCK_GPU_TEXT='えーと、そのまま入力します。'
  start_fake_recording
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  ! called 'curl llm' || false
  [ "$(cat "$T/typed")" = "$MOCK_GPU_TEXT " ]
}

@test "清書に失敗したら原文を入力する" {
  VOICE_INPUT_CLEANUP=1
  MOCK_GPU_TEXT='えーと、原文を使ってください。'
  MOCK_LLM=fail
  start_fake_recording
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  called 'curl llm'
  [ "$(cat "$T/typed")" = "$MOCK_GPU_TEXT " ]
  [ ! -f "$state/transcript.cleaned.txt" ]
}

@test "清書結果が空なら原文を入力する" {
  VOICE_INPUT_CLEANUP=1
  MOCK_GPU_TEXT='えーと、原文を使ってください。'
  MOCK_LLM=empty
  start_fake_recording
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$T/typed")" = "$MOCK_GPU_TEXT " ]
}

@test "短い発話は清書しない" {
  VOICE_INPUT_CLEANUP=1
  MOCK_GPU_TEXT='はい。'
  start_fake_recording
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  ! called 'curl llm' || false
  [ "$(cat "$T/typed")" = 'はい。 ' ]
}

@test "履歴は追記し、原文入力とモデル名と処理時間を記録する" {
  start_fake_recording
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(stat -c %a "$XDG_STATE_HOME/voice-input")" = 700 ]
  [ "$(stat -c %a "$XDG_STATE_HOME/voice-input/history.jsonl")" = 600 ]
  jq -e '.cleanup_status == "disabled" and .cleanup_ms == 0 and
    .raw_text == "GPUの結果 " and .output_text == "GPUの結果 " and
    .whisper_ms >= 0 and .total_ms >= .whisper_ms and
    (.timestamp | test("^20[0-9]{2}-[0-9]{2}-[0-9]{2}T"))' \
    "$XDG_STATE_HOME/voice-input/history.jsonl"
  start_fake_recording
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$XDG_STATE_HOME/voice-input/history.jsonl")" -eq 2 ]
}

@test "CPU 再処理時は実際に使った Whisper モデルを記録する" {
  MOCK_CURL=fail
  start_fake_recording
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.whisper_model' "$XDG_STATE_HOME/voice-input/history.jsonl")" = ggml-small.bin ]
}

@test "VOICE_INPUT_LOG=0 なら履歴を保存しない" {
  VOICE_INPUT_LOG=0
  start_fake_recording
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e "$XDG_STATE_HOME/voice-input/history.jsonl" ]
}

@test "選んだ清書モデルを次の音声入力で使い、reset で既定に戻す" {
  run "$CTL" model lfm2.5-2.6b
  [ "$status" -eq 0 ]
  [ "$(stat -c %a "$XDG_CONFIG_HOME/voice-input")" = 700 ]
  [ "$(stat -c %a "$XDG_CONFIG_HOME/voice-input/model")" = 600 ]
  run "$CTL" model show
  [ "$output" = lfm2.5-2.6b ]
  VOICE_INPUT_CLEANUP=1
  MOCK_GPU_TEXT='えーと、十分な長さの音声です。'
  start_fake_recording
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.model' "$T/llm-request.json")" = lfm2.5-2.6b ]
  run "$CTL" model reset
  [ "$status" -eq 0 ]
  run "$CTL" model show
  [ "$output" = gemma-4-E4B-it-qat ]
}

@test "環境変数のモデル指定は保存した設定より優先する" {
  "$CTL" model lfm2.5-2.6b
  export VOICE_INPUT_LLM_MODEL=another-model
  run "$CTL" model show
  [ "$output" = another-model ]
  VOICE_INPUT_CLEANUP=1
  MOCK_GPU_TEXT='えーと、十分な長さの音声です。'
  start_fake_recording
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.model' "$T/llm-request.json")" = another-model ]
}

@test "履歴を日付・モデル・状態・本文で絞り込む" {
  local history="$XDG_STATE_HOME/voice-input/history.jsonl"
  mkdir -p "${history%/*}"
  jq -n -c '{timestamp:"2026-10-19T10:00:00+09:00",whisper_model:"small",llm_model:"gemma",cleanup_status:"applied",raw_text:"月曜日",output_text:"月曜日",whisper_ms:10,cleanup_ms:20,total_ms:30}' > "$history"
  jq -n -c '{timestamp:"2026-10-21T10:00:00+09:00",whisper_model:"medium",llm_model:"gemma",cleanup_status:"applied",raw_text:"えー、水曜日",output_text:"水曜日",whisper_ms:11,cleanup_ms:22,total_ms:33}' >> "$history"
  jq -n -c '{timestamp:"2026-10-21T11:00:00+09:00",whisper_model:"medium",llm_model:"lfm",cleanup_status:"failed",raw_text:"木曜日",output_text:"木曜日",whisper_ms:12,cleanup_ms:23,total_ms:34}' >> "$history"
  run "$CTL" logs --since 2026-10-20 --model gemma --status applied --text 水曜日 --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | jq -r '.raw_text')" = 'えー、水曜日' ]
  [ "$(printf '%s\n' "$output" | wc -l)" -eq 1 ]
  run "$CTL" logs --model lfm
  [ "$status" -eq 0 ]
  [[ $output == *$'lfm\tfailed\t-\t34\t木曜日'* ]]
  run "$CTL" logs --text 金曜日
  [ "$status" -eq 0 ]
  [ "$output" = '該当する履歴はありません' ]
}

@test "評価モデルは点数・理由・所要時間を別ログに保存する" {
  jq -nc '{id:"record-1",raw_text:"火曜日、いや、水曜日です",output_text:"火曜日です"}' > "$T/record.json"
  run "$JUDGE" < "$T/record.json"
  [ "$status" -eq 0 ]
  jq -e '.record_id == "record-1" and .judge_model == "laya-q8" and
    .status == "ok" and .score == 42 and .reason == "重要な情報に差" and
    .level_score == 1.68 and .confidence == 0.4 and
    .probabilities["1"] == 0.38 and
    (.judge_ms | type == "number")' "$XDG_STATE_HOME/voice-input/judgments.jsonl"
  [ "$(stat -c %a "$XDG_STATE_HOME/voice-input/judgments.jsonl")" = 600 ]
  [ "$(jq -r '.model' "$T/judge-request.json")" = laya-q8 ]
  [ "$(jq -r '.questions.quality.type' "$T/judge-request.json")" = score ]
  called 'hud -s off --no-voice 音声入力: 清書評価 42点 要確認（重要な情報に差）'
}

@test "高スコアの評価は点数と判定段階を HUD に表示する" {
  MOCK_JUDGE_SCORE=3.4
  jq -nc '{id:"record-high",raw_text:"えー、水曜日です",output_text:"水曜日です"}' > "$T/record.json"
  run "$JUDGE" < "$T/record.json"
  [ "$status" -eq 0 ]
  called 'hud -s off --no-voice 音声入力: 清書評価 85点（意味は保持）'
  [ "$(jq -r '.score' "$XDG_STATE_HOME/voice-input/judgments.jsonl")" = 85 ]
}

@test "評価に失敗しても失敗状態を保存する" {
  MOCK_JUDGE=invalid
  jq -nc '{id:"record-2",raw_text:"原文",output_text:"清書"}' > "$T/record.json"
  run "$JUDGE" < "$T/record.json"
  [ "$status" -eq 0 ]
  jq -e '.record_id == "record-2" and .status == "failed" and .score == null' \
    "$XDG_STATE_HOME/voice-input/judgments.jsonl"
  ! grep -q '^hud ' "$T/calls"
}

@test "低スコア履歴を絞り込み、評価理由を表示する" {
  mkdir -p "$XDG_STATE_HOME/voice-input"
  jq -nc '{id:"a",timestamp:"2026-10-21T10:00:00Z",whisper_model:"medium",llm_model:"gemma",cleanup_status:"applied",raw_text:"火曜日、いや、水曜日",output_text:"火曜日",whisper_ms:1,cleanup_ms:2,total_ms:3}' > "$XDG_STATE_HOME/voice-input/history.jsonl"
  jq -nc '{id:"b",timestamp:"2026-10-21T11:00:00Z",whisper_model:"medium",llm_model:"gemma",cleanup_status:"applied",raw_text:"水曜日",output_text:"水曜日",whisper_ms:1,cleanup_ms:2,total_ms:3}' >> "$XDG_STATE_HOME/voice-input/history.jsonl"
  jq -nc '{record_id:"a",judge_model:"ornith",status:"ok",score:42,reason:"曜日を変更",judge_ms:100}' > "$XDG_STATE_HOME/voice-input/judgments.jsonl"
  jq -nc '{record_id:"b",judge_model:"ornith",status:"ok",score:95,reason:"問題なし",judge_ms:100}' >> "$XDG_STATE_HOME/voice-input/judgments.jsonl"
  run "$CTL" logs --max-score 69 --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | jq -r '.id')" = a ]
  [ "$(printf '%s\n' "$output" | jq -r '.judge.reason')" = '曜日を変更' ]
  run "$CTL" logs --max-score 69
  [ "$status" -eq 0 ]
  [[ $output == *$'42\t3\t火曜日'* ]]
}

@test "文字入力の後に評価を起動し、履歴と評価を結び付ける" {
  export VOICE_INPUT_JUDGE_CMD="$JUDGE"
  VOICE_INPUT_CLEANUP=1
  MOCK_GPU_TEXT='えーと、火曜日、いや、水曜日の会議です。'
  start_fake_recording
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -s "$XDG_STATE_HOME/voice-input/judgments.jsonl" ] && break
    sleep 0.1
  done
  [ -s "$XDG_STATE_HOME/voice-input/judgments.jsonl" ]
  [ "$(jq -r '.id' "$XDG_STATE_HOME/voice-input/history.jsonl")" = \
    "$(jq -r '.record_id' "$XDG_STATE_HOME/voice-input/judgments.jsonl")" ]
  [ "$(line_of 'wtype')" -lt "$(line_of 'curl judge')" ]
}
