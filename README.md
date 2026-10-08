# voice-input

`SUPER + H` で音声入力を開始し、もう一度押すと止める。録音中は現在の出力音量を半分に下げ、停止キーで元に戻す。停止後に録音全体を GPU の Whisper サーバーで文字起こしし、現在の入力先へ入力する。結果はクリップボードにもコピーする。IME が有効な場合は、入力中だけオフにしてから元に戻す。

## 動作仕様

1. 1回目の `SUPER + H` で録音を開始する。既定の出力先と音量を保存し、その出力先を元の50%に下げる。録音は `${XDG_RUNTIME_DIR}/voice-input/input.wav` に保存する。
2. 2回目の `SUPER + H` で録音を止め、出力音量をすぐに戻す。録音中には文字を入力しない。
3. 録音全体を `127.0.0.1:8082/inference` に送り、日本語・タイムスタンプなしのテキストを取得する。GPU 処理が失敗するか空の結果を返した場合は、HUD に切替を表示して CPU の small モデルで同じ録音を再処理する。
4. 認識結果をクリップボードにコピーし、現在フォーカスしている入力先へ `wtype` で打ち込む。IME が有効なら打ち込み中だけ無効にする。HUD には状態だけを表示する。

録音した WAV は次の録音開始時まで残る。変換の失敗内容は同じディレクトリの `gpu.log` または `cpu.log` に残る。

## 実行環境

- Hyprland の `~/.config/hypr/binds-omarchy.lua` が `SUPER + H` に `voice-input` を割り当てている。
- 実際に呼ばれるファイルは `~/.local/bin/voice-input`。このディレクトリの `voice-input` が編集用の原本。
- 録音に `pw-record`、文字起こしにローカルの `whisper-server` を使う。GPU 側は `${XDG_DATA_HOME:-$HOME/.local/share}/whisper/ggml-medium.bin`、CPU への切替時は `ggml-small.bin` を使う。CPU 版 CLI は `~/src/whisper.cpp/build/bin/whisper-cli`。
- 出力音量の変更と復元には `wpctl` を使う。録音開始時の出力先と音量を保存するため、途中で既定の出力先を変更しても元の出力先へ戻す。
- 結果の入力に `wl-copy`、`wtype`、`fcitx5-remote` を使う。

## CUDA 版 Whisper サーバー

RTX 4070 では CUDA 版を別のビルドディレクトリに作る。既存の CPU 版ビルドはそのまま残す。

```sh
cmake -S ~/src/whisper.cpp -B ~/src/whisper.cpp/build-cuda \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_CUDA_ARCHITECTURES=89 \
  -DGGML_CUDA=ON -DWHISPER_BUILD_SERVER=ON
cmake --build ~/src/whisper.cpp/build-cuda -j 4
```

このディレクトリで次を実行して user service を登録する。

```sh
mkdir -p ~/.config/systemd/user
cp systemd/user/voice-input-whisper.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now voice-input-whisper.service
```

サーバーは `127.0.0.1:8082` だけで待ち受ける。起動確認は次の通り。

```sh
curl --fail http://127.0.0.1:8082/health
journalctl --user -u voice-input-whisper.service -b -n 50
```

`/health` が `{"status":"ok"}` を返したら利用できる。GPU を使えているかはサーバーの起動ログで CUDA デバイスの認識を確認する。

## 随時入力をやめた理由

以前は約0.4秒の無音、または最大3秒で音声を区切り、0.8秒程度の短い区間まで個別に認識していた。短い区間では前後の文脈が使えず、言い直しや発話中の間で文が切れ、「(音声)(笑)」のような余計な出力も出た。区間ごとのリクエストも増えた。実際にユーザーが比較したところ、CPU の small モデルによる一括入力の方が修正が少なかった。

随時入力では認識結果を録音中に `wtype` で送るため、`SUPER + H` の停止操作と打鍵が重なり、DMS の電源メニューが開く現象も起きた。修飾キーの状態共有を切る設定だけでは解消しなかった。原因となったキーイベントは特定できていない。安定した随時入力には、発話の区切り、途中結果の確定と訂正、入力先のフォーカス、物理キーと仮想キーの競合を扱う必要がある。現在は録音停止後に一度だけ変換・入力する。

## cli-hud との連携

`voice-input` は `${XDG_RUNTIME_DIR}/voice-input/` に状態を置く。`~/.local/bin/hud-probe` がこれを読み、`~/.config/quickshell/cli-hud/shell.qml` が1秒ごとに `hud-probe` を実行して表示を更新する。

| 状態 | `voice-input` が書くファイル | `hud-probe` の判定 | HUD の表示 |
| --- | --- | --- | --- |
| 録音中 | `recording.pid` に録音処理の PID | ファイルがあり、PID が生きている | `● 音声入力: 録音中  (SUPER + H で確定)` |
| 文字起こし中 | `hud-status` に `<PID> transcribing` | PID が生きている | `音声入力: 文字起こし中…` |
| CPU へ切替 | 既存の `hud` と `hud-status` を呼び出す | 5 秒の通知と、終了までの状態表示 | `GPU処理失敗、CPUへ切替` / `CPUで処理中` |
| 終了後 | 状態ファイルなし | 状態なし | 非表示 |

2回目の起動時に録音を止め、文字起こしが終わったら状態ファイルを消す。通常のデスクトップ通知は出さない。

## 変更の反映

このディレクトリのスクリプトを編集したら、実行先へコピーする。

```sh
cp voice-input ~/.local/bin/
chmod +x ~/.local/bin/voice-input
```

次の `SUPER + H` から新しい内容が使われる。`cli-hud` 側の表示文言や更新間隔を変える場合は `~/.config/quickshell/cli-hud/shell.qml`、状態の判定を変える場合は `~/.local/bin/hud-probe` を編集する。
