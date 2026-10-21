# 作業計画・記録・引き継ぎ

## 作業計画（2026-10-21: 評価点の HUD 表示）

- [x] 清書評価が成功したら HUD に点数と decision の判定段階を表示し、69点以下は要確認を付ける。
- [x] 評価失敗や HUD の不在で音声入力を妨げない。
- [x] テストと実行先への配置を確認する。

## 作業計画（2026-10-21: 原文をクリップボードへ保存）

- [x] Whisper の原文を清書前にクリップボードへコピーする。
- [x] `wtype` は清書結果を入力し、履歴には原文と清書文を引き続き保存する。
- [x] テストと実行先への配置を確認する。

## 作業計画（2026-10-21: 配置の一本化）

- [x] 3コマンドを一度に配置する `deploy` を追加し、作業ディレクトリに依存しないようにする。
- [x] lint と README の配置手順を更新する。
- [x] `make test` と一時ディレクトリへの配置を確認する。
- [x] `~/.local/bin` に反映して原本との一致を確認する。

## 作業計画（2026-10-21: 清書後の評価）

- [x] 文字入力後に Laya 判断モデルで清書の意味保持を採点する。
- [x] 評価点・判定段階・確率・モデル名・所要時間を入力履歴と照合できる形で保存する。
- [x] 低スコアの絞り込みを操作画面へ追加し、失敗時も入力を妨げないことをテストする。
- [x] Laya Q8 を一時サーバーと本番ルーターで試し、正誤例の点数と所要時間を確認する。
- [x] Laya Q8 の CPU と GPU の速度・スコア・VRAM 使用量を同じ評価文で比較する。
- [ ] 実際の発話を使って点数の妥当性を確認する。

## 作業計画（2026-10-21: モデル切替と履歴閲覧）

- [x] 端末から清書モデルを選び、次の音声入力から使えるようにする。
- [x] 日付・モデル・清書状態・本文で履歴を絞り込み、原文と入力文を確認できるようにする。
- [x] テスト、README、実行ファイルを更新する。

## 作業計画（2026-10-21: 入力履歴）

- [x] 原文・入力文・Whisper/LLM モデル名・清書状態を JSONL に記録する。
- [x] Whisper・清書・全体の所要時間をミリ秒で記録する。
- [x] 履歴の無効化と保存先の権限を設定し、テストと README を更新する。
- [ ] 実際の発話後の履歴でモデル名と時間を確認する。

## 作業計画（2026-10-21: 音声認識後の清書）

- [x] Whisper の原文を残し、llama.cpp による清書を既定で有効にする。
- [x] `VOICE_INPUT_CLEANUP=0` で無効化し、短文・接続失敗・空の結果では原文を使う。
- [x] 成功、失敗、無効化、短文の自動テストと README を更新する。
- [x] VOICEVOX の合成音声で Whisper → 清書の品質と待ち時間を確認する。
- [ ] 実際の発話で清書の品質と待ち時間を確認する。

## 作業計画（2026-10-20: GPU モデルの量子化）

- [x] `whisper-quantize` で `ggml-medium.bin` を `q8_0` / `q5_0` に量子化し、VRAM・速度・日本語精度を比べる。
- [x] whisper-server を `ggml-medium-q8_0.bin` に切り替える。
- [ ] 実機の声で `q8_0` の認識精度を確認する。

## 作業計画（2026-10-16: 2台目 gallsk への導入）

- [x] `whisper-cpp` を入れ、モデルを `~/.local/share/whisper/` に置く。
- [x] `voice-input` と user service を配置し、GPU 推論を確認する。
- [x] Hyprland の `SUPER + H` を voxtype から `voice-input` に切り替え、submap と `share_states = 0` を設定する。
- [x] 切替後の `whisper-cli` も VRAM 不足で失敗したら HUD に表示する。
- [ ] 家で実機確認する（`SUPER + H` から入力まで、VRAM 不足時の HUD 表示）。職場では音を出せないため未確認。

## 作業計画（2026-10-08）

- [x] CUDA 版 Whisper サーバーを `127.0.0.1:8082` で常駐させる。
- [x] 録音終了後に GPU medium で一括変換し、失敗時は HUD 表示後に CPU small へ切り替える。
- [x] 録音中の出力音量を元の20%に下げ、終了時に戻す。
- [x] 入力、クリップボード、HUD の動作と切替経路を確認する。
- [x] マイク音声付きのデモ録画手順を README に追加する。

## 作業記録

- 2026-10-21: Whisper 原文を清書前にクリップボードへコピーし、`wtype` は清書結果を入力するよう変更。清書評価の HUD には点数と最大確率の decision 判定段階を表示し、69点以下は「要確認」を付ける。スコアは正解率ではないため `%` を付けない。`make test` で30件通過し、`./deploy` で3コマンドを配置して原本との一致を確認。
- 2026-10-21: `deploy` を追加。`voice-input`、`voice-inputctl`、`voice-input-judge` を既定で `~/.local/bin/` に配置する。任意の配置先を引数で指定できる。`make test` で29件通過。別ディレクトリから一時配置先への実行と、実配置先の3ファイルの原本一致・実行権限を確認。
- 2026-10-21: `voice-input` に llama.cpp の清書を追加。既定は `gemma-4-E4B-it-qat`、15秒で打ち切り、失敗時は原文を入力する。VOICEVOX の合成音声では、言い直しを含む発話を正しく清書した（モデル切替込み初回10.42秒、2回目1.76秒）。実際の発話での品質は未確認。
- 2026-10-21: 入力履歴を `history.jsonl` に追記。原文・入力文・モデル名・清書状態・Whisper/清書/全体の所要時間を記録し、保存先を `700`/`600` に設定。`VOICE_INPUT_LOG=0` で無効化できる。
- 2026-10-21: `voice-inputctl` を追加。`fzf` で清書モデルを選んで保存し、履歴を日付・モデル・状態・本文・評価点で絞り込める。
- 2026-10-21: `voice-input-judge` を追加。入力を返した後、Laya Q8 の `/v1/systemone` で原文と清書文を5段階評価し、期待値を0〜100点に換算する。判定段階・各段階の確率・所要時間を `judgments.jsonl` に記録する。`reason` は生成した説明ではなく、最大確率の段階名。
- 2026-10-21: 当初 Ornith を評価に使ったが、判断専用モデルではなかったため Laya に変更。`~/.config/llama.cpp/models.ini` に `laya-q8` を追加し、llama.cpp user service を `--models-max 2` に変更して再起動。Gemma と Laya は同時保持でき、Whisper 込みの GPU 使用量は 8206 / 12288 MiB（Whisper 1294、Gemma 6208、Laya 150 MiB）。
- 2026-10-21: 合成例を本番ルーターで評価し、正しい清書82点（約997ms）、曜日と時刻を誤った清書5点（約82ms）。実際の発話と幅広い例での点数校正は未実施。
- 2026-10-21: Laya Q8 を GPU 全層で別ポートに一時起動し、CPU 版と同じ訂正入り短文を各5回評価。両者とも約82.5点。HTTP 応答時間は CPU が1回目789ms・以降約50ms、GPU が1回目122ms・以降約14ms。GPU 版の VRAM は520MiB、空きは約1.0GiB。実験サーバーを停止し、常用設定は CPU のまま。
- 2026-10-21: `make test` で shellcheck と29件の Bats テストが通過。3コマンドを `~/.local/bin/` に配置して原本との一致を確認。
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
- 2026-10-20: gallsk（RTX 3060）で `ggml-medium.bin` を量子化して比較。モデルの VRAM は f16 1533MB / `q8_0` 823MB / `q5_0` 539MB。VOICEVOX で合成した日本語約 30 秒 × 2 話者で、処理時間は f16 約 1.8 秒 / `q8_0` 約 1.5 秒 / `q5_0` 約 1.4 秒。`q8_0` は f16 と出力が完全一致、`q5_0` は 1 話者の末尾だけ差があった。精度リスクが最小の `q8_0` をサーバーに採用。CPU 切替用の `ggml-small.bin` はそのまま。

## 引き継ぎ

- 清書が適用され、履歴記録に成功した入力だけ Laya Q8 の `/v1/systemone` で評価する。`VOICE_INPUT_JUDGE=0` で停止、`VOICE_INPUT_JUDGE_MODEL` と `VOICE_INPUT_JUDGE_URL` で変更できる。評価は別プロセスで動き、`judgments.jsonl` に記録する。llama-server は `--models-max 2`。サービス変更前のファイルは `~/.config/systemd/user/llama.cpp.service.bak-before-voice-input-two-models`。
- Laya のモデル設定は `~/.config/llama.cpp/models.ini` の `[laya-q8]`。設定変更前のバックアップは `~/.config/llama.cpp/models.ini.bak-before-laya-voice-input`。
- GPU で動かすなら `[laya-q8]` の `n-gpu-layers = all`。実測では繰り返し評価が約50msから約14msになり、VRAM は Laya プロセスで520MiB使用した。現在は `0` のままで、実験サーバーは停止済み。
- Whisper の原文はクリップボードへ、清書結果は `wtype` で入力先へ送る。清書しない場合は両方とも原文になる。
- 清書評価の HUD 表示は `voice-input-judge` が入力後に行う。点数と最大確率の decision 判定段階を表示し、69点以下は「要確認」を付ける。評価失敗時や HUD がないときは通知しない。
- `voice-inputctl` は `fzf` と `jq` が必要。`voice-inputctl model` でモデル選択、`voice-inputctl logs` で履歴選択。端末のない場面では `voice-inputctl model ID` と `voice-inputctl logs --json` を使える。`VOICE_INPUT_LLM_BASE_URL` でモデル一覧の接続先を変えられる。
- 選択したモデルは `~/.config/voice-input/model` に保存し、次の音声入力から使う。環境変数 `VOICE_INPUT_LLM_MODEL` が設定されている場合はそちらを優先する。
- 履歴は自動で追記される。保存先は `~/.local/state/voice-input/history.jsonl`（`XDG_STATE_HOME` があればそちら）。職場で残さない場合は起動コマンドに `VOICE_INPUT_LOG=0` を付ける。
- Whisper サーバー側のモデルを変えた場合は、起動コマンドの `VOICE_INPUT_WHISPER_MODEL` も変更する。CPU 切替時は CLI のモデルファイル名を自動記録する。
- 清書は既定で有効。職場では起動コマンドに `VOICE_INPUT_CLEANUP=0` を付ける。`jq` が必要。llama-server が使えないときは原文を入力する。
- llama-server は `models-max 2`。Gemma と Laya は同時保持できる。合成音声での Gemma 4 E4B は初回10.42秒、2回目1.76秒。実際の発話で遅い場合はモデルやタイムアウトを調整する。
- 実行ファイルは `~/.local/bin/` の3コマンド。変更時はリポジトリの `./deploy` で反映する。
- GPU は `ggml-medium-q8_0.bin`（`ggml-medium.bin` から `whisper-quantize` で作成）、CPU 切替時は `ggml-small.bin`。サーバーは user service で起動する。
- 状態と録音は `${XDG_RUNTIME_DIR}/voice-input/`。失敗時は `gpu.log`、`cpu.log` を見る。
- Hyprland のユーザー設定 `~/.config/hypr/hyprland.lua` で `input.virtualkeyboard.share_states = 0` にしている。このファイルは本リポジトリ外。
- `~/.config/hypr/binds-omarchy.lua` に `voice_input_typing` submap と復帰用 `F12` を定義している。このファイルも本リポジトリ外。ユーザーの直後の試行では誤爆しなかった。
- デモ録画用の `~/.local/bin/screenrec`、`~/.local/bin/hud-probe`、`~/.config/quickshell/cli-hud/shell.qml` も本リポジトリ外。HUD には録画時間と `ALT+Print` / `screenrec stop` を表示する。
- `~/Videos/voice-input-demo4.mp4` はローカルの実演動画で、リポジトリには含めていない。
- gallsk では Hyprland の設定が `~/.config/hypr/hyprland.lua` 1 本で、`SUPER + H`、`voice_input_typing` submap、`input.virtualkeyboard.share_states = 0` もここに書いた。変更前の状態は `~/.config/hypr/hyprland.lua.bak-before-voice-input`。voxtype はアンインストールしていない。
