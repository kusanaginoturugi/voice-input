# voice-input（簡略版）

しゃべった声を文字にして、カーソルの位置に打ち込む、1 ファイルのシェルスクリプトです。
YouTube「ローカル LLM で遊ぼう 第2弾：whisper.cpp で音声入力を作ろう」で解説している版です。

1. 1 回目の起動で録音を始め、2 回目の起動で止める（キーボードショートカットに割り当てて使う）
2. 録音を whisper-server に送って文字にする
3. llama-server で清書する（フィラーを消し、「火曜日、いや、水曜日」のような言い直しは後の方だけ残す）
4. 結果をクリップボードに入れ、カーソルの位置に打ち込む

文字起こしも清書も自分のパソコンで動かすので、声も文章も外に出ません。
本家（リポジトリ直下の `voice-input`）から、Hyprland・fcitx5・HUD・録音中の音量調整・CPU への切り替え・履歴と採点を外したものです。

## 必要なもの

- whisper.cpp の `whisper-server`（既定 `http://127.0.0.1:8082/inference`）
- llama.cpp の `llama-server`（既定 `http://127.0.0.1:8080/v1/chat/completions`。第1弾の設定のまま使える）
- `curl`、`jq`
- 録音: `pw-record`（PipeWire）か `arecord`（ALSA）
- 打ち込み: Wayland なら `wtype`、X11 なら `xdotool`（なくてもクリップボードには入る）
- クリップボード: `wl-copy` か `xclip`
- 通知（任意）: `notify-send`

## 使い方

```sh
install -m 755 voice-input ~/.local/bin/
voice-input                       # 録音開始。もう一度実行すると止めて文字にする
voice-input --file sample.wav     # 録音の代わりに音声ファイル（16kHz モノラルの WAV）を使う
```

キーボードショートカットに `voice-input` を割り当てると、押して話して、もう一度押すだけで文字が入ります。

## 設定（環境変数）

| 変数 | 既定 | 意味 |
| --- | --- | --- |
| `VOICE_INPUT_WHISPER_URL` | `http://127.0.0.1:8082/inference` | whisper-server の URL |
| `VOICE_INPUT_LANGUAGE` | `ja` | 話す言語 |
| `VOICE_INPUT_LLM_URL` | `http://127.0.0.1:8080/v1/chat/completions` | llama-server の URL |
| `VOICE_INPUT_LLM_MODEL` | `gemma-4-e4b` | 清書に使うモデル名（第1弾のプリセット名） |
| `VOICE_INPUT_CLEANUP` | `1` | `0` で清書しない |
| `VOICE_INPUT_TYPE` | `1` | `0` で打ち込まず、クリップボードと標準出力だけ |

清書のリクエストでは、モデルの「考える過程」（thinking）を切っています（`chat_template_kwargs.enable_thinking: false`）。
清書のような単純な作業では要らず、切ると 3 秒ほどかかっていたのが 0.3 秒台になります（RTX 4070 で実測）。
