# 作業計画・記録・引き継ぎ

## 作業計画（2026-10-08）

- [x] CUDA 版 Whisper サーバーを `127.0.0.1:8082` で常駐させる。
- [x] 録音終了後に GPU medium で一括変換し、失敗時は HUD 表示後に CPU small へ切り替える。
- [x] 録音中の出力音量を半分にし、終了時に戻す。
- [x] 入力、クリップボード、HUD の動作と切替経路を確認する。

## 作業記録

- `systemd/user/voice-input-whisper.service` で CUDA 版 `whisper-server` を起動。ポートは `8082`。
- 随時入力は短い区間で文脈が切れ、停止キーと文字入力も干渉したため、一括入力へ変更。
- 認識結果が `-` で始まっても扱えるよう、`wtype` と `wl-copy` に標準入力から渡す。
- GPU 成功と CPU 切替の両経路を確認。録音中の音量 `0.80 → 0.40`、停止後 `0.80` を確認。
- 同じ約 11 秒の録音では、GPU medium が約 0.24 秒で「スモール」、CPU small が約 2.3 秒で「スモーリー」と認識。ユーザーは GPU 一括入力を実用上快適と評価。

## 引き継ぎ

- 実行ファイルは `~/.local/bin/voice-input`。変更時は `README.md` の手順でコピーする。
- GPU は `ggml-medium.bin`、CPU 切替時は `ggml-small.bin`。サーバーは user service で起動する。
- 状態と録音は `${XDG_RUNTIME_DIR}/voice-input/`。失敗時は `gpu.log`、`cpu.log` を見る。
- Hyprland のユーザー設定 `~/.config/hypr/hyprland.lua` で `input.virtualkeyboard.share_states = 0` にしている。このファイルは本リポジトリ外。
