#!/usr/bin/env bats
# voice-input の録音開始・停止・変換・入力の流れを、外部コマンドを偽物に差し替えて確かめる。
# 偽コマンドは呼ばれた内容を $T/calls に1行ずつ書く。

SCRIPT="$BATS_TEST_DIRNAME/../voice-input"

setup() {
  T="$BATS_TEST_TMPDIR"
  export HOME="$T/home"
  export XDG_RUNTIME_DIR="$T/run"
  export XDG_DATA_HOME="$T/data"
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
  export MOCK_IME=1
  export MOCK_WTYPE=ok

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
echo curl >> "$T/calls"
out=
while [ "$#" -gt 0 ]; do
  [ "$1" = -o ] && out=$2
  shift
done
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
printf '%s\n' "$MOCK_CPU_TEXT" > "$base.txt"
EOF
  mock wl-copy <<'EOF'
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
  ! grep -q '^wpctl set-volume' "$T/calls"
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
  ! kill -0 "$recorder" 2>/dev/null
  called 'wpctl set-volume 42 0.80'
  [ "$(cat "$T/typed")" = 'GPUの結果 ' ]
  [ "$(cat "$T/clipboard")" = 'GPUの結果 ' ]
  ! grep -q '^whisper-cli' "$T/calls"
  ! grep -q '^hud ' "$T/calls"
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

@test "CPU モデルがなければ何も入力せずに失敗し、後片付けはする" {
  MOCK_CURL=fail
  rm "$XDG_DATA_HOME/whisper/ggml-small.bin"
  start_fake_recording
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  ! called wtype
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

@test "IME が無効なら IME を操作しない" {
  start_fake_recording
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  ! grep -q '^fcitx5-remote' "$T/calls"
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
