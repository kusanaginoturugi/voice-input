# 作業計画・記録・引き継ぎ

## 作業計画（2026-10-16: 2台目 gallsk への導入）

- [x] `whisper-cpp` を入れ、モデルを `~/.local/share/whisper/` に置く。
- [x] `voice-input` と user service を配置し、GPU 推論を確認する。
- [x] Hyprland の `SUPER + H` を voxtype から `voice-input` に切り替え、submap と `share_states = 0` を設定する。
- [ ] 実機で `SUPER + H` から入力まで確認する。

## 作業計画（2026-10-08）

- [x] CUDA 版 Whisper サーバーを `127.0.0.1:8082` で常駐させる。
- [x] 録音終了後に GPU medium で一括変換し、失敗時は HUD 表示後に CPU small へ切り替える。
- [x] 録音中の出力音量を元の20%に下げ、終了時に戻す。
- [x] 入力、クリップボード、HUD の動作と切替経路を確認する。
- [x] マイク音声付きのデモ録画手順を README に追加する。

## 作業記録

- `systemd/user/voice-input-whisper.service` で CUDA 版 `whisper-server` を起動。ポートは `8082`。
- 随時入力は短い区間で文脈が切れ、停止キーと文字入力も干渉したため、一括入力へ変更。
- 認識結果が `-` で始まっても扱えるよう、`wtype` と `wl-copy` に標準入力から渡す。
- GPU 成功と CPU 切替の両経路を確認。録音中の音量 `0.80 → 0.40`、停止後 `0.80` を確認。
- 画面録画のマイクに再生音が入るため、録音中の出力音量を元の50%から20%に変更。
- 20%設定ではテスト音量 `0.80 → 0.16 → 0.80` を確認。
- デモ録画の停止が分かりにくかったため、`screenrec stop` を明示的な終了コマンドにし、直接起動した `wf-recorder` も HUD で検出するようユーザー側の `screenrec`、`hud-probe`、`cli-hud` を更新。
- `~/Videos/voice-input-demo4.mp4` を確認。約20秒で、音声入力HUDと認識結果の入力が映り、映像・マイク音声ともに記録済み。音声は正常に文字起こしでき、野球中継の音も混ざるが、実演用途では許容する方針。
- README に `wf-recorder` のマイク音声付き録画例と `screenrec stop` による停止手順を追加。
- 同じ約 11 秒の録音では、GPU medium が約 0.24 秒で「スモール」、CPU small が約 2.3 秒で「スモーリー」と認識。ユーザーは GPU 一括入力を実用上快適と評価。
- 一括入力でも `SUPER+ESC` が誤発火したため、停止後の変換・文字入力中は Hyprland の `voice_input_typing` submap へ切り替え、終了時に戻す。GPU 成功、CPU 切替、`wtype` 失敗時の復帰を確認。
- Arch Linux のパッケージ版 `whisper-cpp` と `ggml-cuda` が CUDA に対応したため、自前ビルドをやめて `/usr/bin/whisper-server`、`/usr/bin/whisper-cli` を使うよう変更。起動ログで RTX 4070 と `libggml-cuda.so` の読み込みを確認。
- `shellcheck` と `bats` のテストを追加（`make test`）。テスト作成中に、出力がミュート中または既定の出力先がない場合に `set -e` で録音前に終了するバグを発見して修正。2026-10-15 にユーザーが実機でミュート中も録音できることを確認。
- 2026-10-16: 2台目の gallsk（RTX 3060 12GB）へ導入。`whisper-cpp`、`shellcheck`、`bats` を pacman で入れ、モデルを Hugging Face の `ggerganov/whisper.cpp` から取得（sha256 一致を確認）。`~/.local/bin/voice-input` には 10/6 の初期版が残っていたので `voice-input.bak-20261006` に退避して更新。
- gallsk では `llama-server` が VRAM を約 8.4GB 使っている。whisper-server（medium）は約 2.1GB で載り、テスト WAV の `/inference` が約 0.3 秒で応答。
- パッケージ版 `whisper-cli` は `ggml-cuda` があると GPU を使う。VRAM が埋まっていると CPU 切替でも `cudaMalloc failed: out of memory` で落ちる。`-ng` なら CPU で通る（テスト WAV で約 2.8 秒）が、ユーザーは CPU は遅くて使わない方針なので付けていない。
- VRAM 不足に気づけるよう、切替後の `whisper-cli` が失敗して `cpu.log` に `out of memory` があれば HUD に `音声入力: VRAM不足で処理できません` を出すようにした。gallsk 実機の OOM ログで文言が一致することを確認。

## 引き継ぎ

- 実行ファイルは `~/.local/bin/voice-input`。変更時は `README.md` の手順でコピーする。
- GPU は `ggml-medium.bin`、CPU 切替時は `ggml-small.bin`。サーバーは user service で起動する。
- 状態と録音は `${XDG_RUNTIME_DIR}/voice-input/`。失敗時は `gpu.log`、`cpu.log` を見る。
- Hyprland のユーザー設定 `~/.config/hypr/hyprland.lua` で `input.virtualkeyboard.share_states = 0` にしている。このファイルは本リポジトリ外。
- `~/.config/hypr/binds-omarchy.lua` に `voice_input_typing` submap と復帰用 `F12` を定義している。このファイルも本リポジトリ外。ユーザーの直後の試行では誤爆しなかった。
- デモ録画用の `~/.local/bin/screenrec`、`~/.local/bin/hud-probe`、`~/.config/quickshell/cli-hud/shell.qml` も本リポジトリ外。HUD には録画時間と `ALT+Print` / `screenrec stop` を表示する。
- `~/Videos/voice-input-demo4.mp4` はローカルの実演動画で、リポジトリには含めていない。
- gallsk では Hyprland の設定が `~/.config/hypr/hyprland.lua` 1 本で、`SUPER + H`、`voice_input_typing` submap、`input.virtualkeyboard.share_states = 0` もここに書いた。変更前の状態は `~/.config/hypr/hyprland.lua.bak-before-voice-input`。voxtype はアンインストールしていない。
