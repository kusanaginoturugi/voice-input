#!/usr/bin/env bats
# lite/voice-input（動画で解説している簡略版）の流れを、外部コマンドを偽物に差し替えて確かめる。
# 偽コマンドは呼ばれた内容を $T/calls に1行ずつ書く。

SCRIPT="$BATS_TEST_DIRNAME/../lite/voice-input"

setup() {
  T="$BATS_TEST_TMPDIR"
  export T
  export XDG_RUNTIME_DIR="$T/run"
  export WAYLAND_DISPLAY=wayland-test
  mkdir -p "$T/bin" "$XDG_RUNTIME_DIR"
  : > "$T/calls"
  : > "$T/audio.wav"
  unset VOICE_INPUT_CLEANUP VOICE_INPUT_TYPE VOICE_INPUT_LLM_MODEL

  export MOCK_WHISPER='えーと、明日の会議は火曜日、いや、水曜日です'
  export MOCK_WHISPER_FAIL=0
  export MOCK_LLM_TEXT='明日の会議は水曜日です。'
  export MOCK_LLM_FAIL=0

  mock curl <<'EOF'
url=
payload=
while [ "$#" -gt 0 ]; do
  [ "$1" = --data-binary ] && payload=$2
  case "$1" in http*) url=$1 ;; esac
  shift
done
case "$url" in
  */inference)
    echo 'curl whisper' >> "$T/calls"
    [ "$MOCK_WHISPER_FAIL" = 0 ] || exit 7
    printf '%s\n' "$MOCK_WHISPER" ;;
  */chat/completions)
    echo 'curl llm' >> "$T/calls"
    printf '%s' "$payload" > "$T/llm-request.json"
    [ "$MOCK_LLM_FAIL" = 0 ] || exit 7
    jq -n --arg text "$MOCK_LLM_TEXT" '{choices:[{message:{content:({text:$text}|tojson)}}]}' ;;
esac
EOF
  mock wl-copy <<'EOF'
printf 'wl-copy %s\n' "$(cat)" >> "$T/calls"
EOF
  mock wtype <<'EOF'
printf 'wtype %s\n' "$(cat)" >> "$T/calls"
EOF
  mock notify-send <<'EOF'
echo "notify $*" >> "$T/calls"
EOF
  export PATH="$T/bin:$PATH"
}

mock() {
  { echo '#!/bin/sh'; cat; } > "$T/bin/$1"
  chmod +x "$T/bin/$1"
}

@test "文字起こしを清書して、クリップボードとカーソルの位置に入れる" {
  run "$SCRIPT" --file "$T/audio.wav"
  [ "$status" -eq 0 ]
  [ "$output" = '明日の会議は水曜日です。' ]
  grep -qx 'curl whisper' "$T/calls"
  grep -qx 'curl llm' "$T/calls"
  grep -qx 'wl-copy 明日の会議は水曜日です。' "$T/calls"
  grep -qx 'wtype 明日の会議は水曜日です。' "$T/calls"
}

@test "清書では thinking を切り、JSON スキーマで結果を受け取る" {
  run "$SCRIPT" --file "$T/audio.wav"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.chat_template_kwargs.enable_thinking' "$T/llm-request.json")" = false ]
  [ "$(jq -r '.response_format.type' "$T/llm-request.json")" = json_schema ]
  [ "$(jq -r '.model' "$T/llm-request.json")" = gemma-4-e4b ]
}

@test "VOICE_INPUT_CLEANUP=0 なら清書せず、文字起こしのまま入れる" {
  VOICE_INPUT_CLEANUP=0 run "$SCRIPT" --file "$T/audio.wav"
  [ "$status" -eq 0 ]
  [ "$output" = "$MOCK_WHISPER" ]
  ! grep -qx 'curl llm' "$T/calls"
}

@test "短い言葉は清書しない" {
  MOCK_WHISPER='はい' run "$SCRIPT" --file "$T/audio.wav"
  [ "$status" -eq 0 ]
  [ "$output" = 'はい' ]
  ! grep -qx 'curl llm' "$T/calls"
}

@test "清書に失敗したら、文字起こしのまま入れる" {
  MOCK_LLM_FAIL=1 run "$SCRIPT" --file "$T/audio.wav"
  [ "$status" -eq 0 ]
  [ "$output" = "$MOCK_WHISPER" ]
  grep -q '^notify .*清書に失敗' "$T/calls"
  grep -qx "wtype $MOCK_WHISPER" "$T/calls"
}

@test "whisper-server につながらなければ、何も入れずにエラーで終わる" {
  MOCK_WHISPER_FAIL=1 run "$SCRIPT" --file "$T/audio.wav"
  [ "$status" -ne 0 ]
  [[ "$output" == *文字起こしに失敗* ]]
  ! grep -q '^wtype' "$T/calls"
}

@test "VOICE_INPUT_TYPE=0 なら打ち込まず、クリップボードと標準出力だけ" {
  VOICE_INPUT_TYPE=0 run "$SCRIPT" --file "$T/audio.wav"
  [ "$status" -eq 0 ]
  grep -q '^wl-copy' "$T/calls"
  ! grep -q '^wtype' "$T/calls"
}
