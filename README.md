# voice-input

`SUPER + H` で録音を開始し、もう一度押すと録音を止めて Whisper で文字起こしする。結果はクリップボードにコピーし、現在の入力先にも打ち込む。IME が有効な場合は、入力中だけオフにしてから元に戻す。

## 実行環境

- Hyprland の `~/.config/hypr/binds-omarchy.lua` が `SUPER + H` に `voice-input` を割り当てている。
- 実際に呼ばれるファイルは `~/.local/bin/voice-input`。このディレクトリの `voice-input` が編集用の原本。
- 録音に `pw-record`、文字起こしに `~/src/whisper.cpp/build/bin/whisper-cli` を使う。モデルは `${XDG_DATA_HOME:-$HOME/.local/share}/whisper/ggml-medium.bin`。
- 結果の入力に `wl-copy`、`wtype`、`fcitx5-remote` を使う。

## cli-hud との連携

`voice-input` は `${XDG_RUNTIME_DIR}/voice-input/` に状態を置く。`~/.local/bin/hud-probe` がこれを読み、`~/.config/quickshell/cli-hud/shell.qml` が1秒ごとに `hud-probe` を実行して表示を更新する。

| 状態 | `voice-input` が書くファイル | `hud-probe` の判定 | HUD の表示 |
| --- | --- | --- | --- |
| 録音中 | `recording.pid` に録音プロセスの PID | ファイルがあり、PID が生きている | `● 音声入力: 録音中  (SUPER + H で確定)` |
| 文字起こし中 | `hud-status` に `<PID> transcribing` | PID が生きている | `音声入力: 文字起こし中…` |
| 終了後 | 状態ファイルなし | 状態なし | 非表示 |

2回目の起動時に `recording.pid` を消し、文字起こし中は終了時の trap で `hud-status` を消す。通常のデスクトップ通知は出さない。HUD が表示するのは録音中と文字起こし中の状態で、完了やエラーのメッセージは表示しない。

## 変更の反映

このディレクトリのスクリプトを編集したら、実行先へコピーする。

```sh
cp voice-input ~/.local/bin/voice-input
```

次の `SUPER + H` から新しい内容が使われる。`cli-hud` 側の表示文言や更新間隔を変える場合は `~/.config/quickshell/cli-hud/shell.qml`、状態の判定を変える場合は `~/.local/bin/hud-probe` を編集する。
