# voice-input

`SUPER + H` で音声入力を開始し、もう一度押すと止める。録音中は現在の出力音量を20%に下げ、停止キーで元に戻す。録音を始めると確認ダイアログが開き、停止後に録音全体を GPU の Whisper サーバーで文字起こしした結果がそのダイアログに入る。直して `Ctrl + Enter` で送信すると、録音を始めたときのウィンドウへ `SUPER + V` と同じ方法で貼り付ける。ダイアログで直した語は学習し、同じ直しが2回たまると辞書に入って次から自動で直る。ローカル LLM による清書は既定で無効で、`VOICE_INPUT_CLEANUP=1` で有効にできる。

動画「ローカル LLM で遊ぼう 第2弾」で解説している簡略版（Hyprland などに依存しない 1 ファイル版）は [`lite/`](lite/) にあります。

## 動作仕様

1. 1回目の `SUPER + H` で録音を開始する。既定の出力先と音量を保存し、その出力先を元の20%に下げる。録音は `${XDG_RUNTIME_DIR}/voice-input/input.wav` に保存する。そのとき前面にあるウィンドウを貼り先として `target-window` に覚え、確認ダイアログを「録音中」の表示で開く。
2. 2回目の `SUPER + H`（またはダイアログの `Ctrl + Enter`）で録音を止め、出力音量をすぐに戻す。ダイアログは「文字起こし中」の表示になる。録音中には文字を入力しない。録音中にダイアログを `Esc` でやめると、録音を捨てて音量を戻す。
3. 録音全体を `127.0.0.1:8082/inference` に送り、日本語・タイムスタンプなしのテキストを取得する。GPU 処理が失敗するか空の結果を返した場合は、HUD に切替を表示して CPU の small モデルで同じ録音を再処理する。
4. 清書を有効にした場合（`VOICE_INPUT_CLEANUP=1`）、10文字以上の認識結果はローカルの llama.cpp に送り、フィラーと言い直しの削除、句読点の調整を依頼する。15秒以内に清書できない場合や結果が空の場合は原文を使う。
5. 辞書（後述）で置き換え、確認ダイアログに入れて編集できるようにする。文字起こしに失敗したらダイアログを閉じる。`Esc` でやめた場合は何も貼らない。送信したら、前面のウィンドウが録音開始時と違えばそのウィンドウへフォーカスを戻す。閉じられていた場合は貼らずにクリップボードへコピーし、HUD で知らせる。
6. Whisper の原文をクリップボードへコピーする。清書した場合は清書結果をコピーし直すので、原文は DMS のクリップボード履歴（`SUPER + CTRL + V`）に残る。次に `hyprctl eval 'voice_input_paste()'` で、`SUPER + V` と同じ貼り付けキー（端末は `Ctrl+Shift+V`、それ以外は `Ctrl+V`）を Hyprland から入力先へ送る。貼り付けは IME を通らないので、IME が有効でも長い文が崩れない。Hyprland 設定が `voice_input_paste` を公開していない環境では、従来どおり IME を一時的に無効にして `wtype` で打ち込む。
7. ダイアログで直していれば、変わった語の組を学習候補に記録する（後述）。
8. 清書を適用した入力は、文字を返した後で別プロセスの評価モデルに渡す。評価待ちで文字入力を止めず、完了したら点数と判定段階を HUD に表示する。

録音した WAV は次の録音開始時まで残る。Whisper の原文は `transcript.txt`、清書に成功した結果は `transcript.cleaned.txt` に残る。変換の失敗内容は同じディレクトリの `gpu.log`、`cpu.log` または `cleanup.log` に残る。

## 確認ダイアログ

確認ダイアログは `quickshell` で作っている（`voice-input-dialog.qml`、`deploy` で `${XDG_DATA_HOME:-$HOME/.local/share}/voice-input/` に入る）。録音を始めたときに開き、`voice-input` が書く `dialog-state.json` を見張って「録音中（経過時間）」「文字起こし中」「編集」と表示を切り替える。録音中もキーボードを占有するので、ほかのウィンドウには入力できない。開けなかった場合は、録音を止めた後に改めて開く。レイヤーシェルの面として画面中央に浮かび、キーボードを占有する。色は cli-hud と同じく DMS のテーマ（カスタムテーマ・ダイナミックカラー、ライト/ダーク）に合わせ、読めなければ既定の色にする。SKK で日本語を入力できる。

| キー | 動作 |
| --- | --- |
| `Ctrl + Enter` | 録音中なら録音を止める。編集中なら送信して貼り付ける |
| `Enter`、`C-j` | 改行（貼り付けなら改行もそのまま入る）。SKK がオンだと `C-j` は SKK が使う |
| `Esc` | 何も貼らずにやめる（録音中なら録音も捨てる） |
| `C-f` `C-b` `C-n` `C-p` `C-a` `C-e` | 1文字・1行（折り返しも1行）・行頭・行末へ移動 |
| `M-f` `M-b` `M-<` `M->` | 単語単位（文字の種類が変わるところ）・先頭・末尾へ移動 |
| `C-d` `C-h` `M-d` `M-DEL` `C-k` | 1文字・単語・行末までを消す |
| `C-SPC`（`C-@`）`C-w` `M-w` `C-y` `C-g` | マーク、切り取り、コピー、貼り付け、マーク解除 |
| `C-/`（`C-_`） | 取り消し |

`C-k` などで切り取った文字はダイアログ内だけで持ち、システムのクリップボードには入れない。切り取ったものがなければ `C-y` はクリップボードを貼る。SKK の変換中は `Esc` と `Ctrl + Enter` も含めてキーを SKK に渡す。ダイアログはフォーカス中のモニターに出す。全部消して送信した場合はやめたのと同じ扱い。

ダイアログを待つ間も `voice_input_typing` submap のままなので、`SUPER` のショートカットは効かない。ダイアログが閉じなくなったら `F12` で閉じられる（submap も戻る）。30分（`VOICE_INPUT_DIALOG_TIMEOUT` 秒）たつと自動で閉じる。どちらの場合も何も貼らない。`VOICE_INPUT_DIALOG=0` でダイアログを出さずに貼る。`qs` やダイアログのファイルがない場合や起動に失敗した場合も、そのまま貼る。履歴の `dialog_status` は `submitted` / `cancelled` / `target_lost` / `unavailable` / `disabled`、ダイアログに出した文は `shown_text`、貼った文は `output_text`、待ち時間は `dialog_ms`（`total_ms` には含めない）。

## 辞書の自動学習

ダイアログで直して送信すると、表示した文と送信した文を1文字ずつ `diff` で比べ、置き換えた部分を「誤 → 正」の組として学習候補 `${XDG_STATE_HOME:-$HOME/.local/state}/voice-input/dictionary-candidates.jsonl` に記録する。同じ組が2回（`VOICE_INPUT_DICT_PROMOTE` で変更）たまると、辞書 `${XDG_CONFIG_HOME:-$HOME/.config}/voice-input/dictionary.tsv` に入れて HUD で知らせる。辞書は次の音声入力から、清書の後・ダイアログの前に当てる（どの清書モードでも効く）。

- 変わった部分は前後の漢字・カタカナ・英数字のまとまりまで広げる。「注出 → 抽出」は1文字ずつだと「注 → 抽」だが、それでは「注意」まで変わるため。
- 1文字だけの組（「ね → よ」のような語尾の直し）、空白・改行・句読点を含む組、13文字以上の組は覚えない。
- 書き換えた量が文の半分を超える場合は、言い換えとみなして何も覚えない。
- 辞書は文脈を見ずに置き換える。「感じ → 漢字」のような組が入ると「いい感じ」まで変わるので、そうなったら消す。

辞書は1行1組の `誤<TAB>正` で、`#` で始まる行と空行は無視する。手で編集してもよい。

```sh
voice-inputctl dict                 # 辞書と学習候補（回数）
voice-inputctl dict add 議事禄 議事録  # 手で追加
voice-inputctl dict rm 感じ          # 辞書と学習候補から消す
```

## Whisper のプロンプト

Whisper には、出てきそうな言葉を「初期プロンプト」として渡す。直前にその話をしていたものとして聞き取るので、渡した言葉に寄る。たとえば「WISPRに音声を…」が「Whisperに音声を…」になる。

- `${XDG_CONFIG_HOME:-$HOME/.config}/voice-input/prompt.txt` に言葉を書く。1行1語か読点区切りで、`#` で始まる行は無視する。
- 辞書（後述）の「正」の言葉も後ろに足す。直した言葉ほど次から聞き取られやすくなる。
- 重なった言葉は1回にし、全体を120文字（`VOICE_INPUT_PROMPT_MAX`）までにする。Whisper は長すぎるプロンプトを切り捨てるため。`prompt.txt` の言葉を優先する。
- 文章ではなく言葉だけを並べる。言いそうな文を渡すと「もう言った」と見なして何も返さないことがある。
- プロンプト付きで空の結果が返ったら、プロンプトを外してやり直す（GPU でも CPU でも）。
- `VOICE_INPUT_PROMPT=0` でプロンプトを付けない。

履歴には使ったプロンプトを `whisper_prompt`、外してやり直したかを `prompt_retried` に記録し、`voice-inputctl logs` の詳細にも表示する。

## 清書オプション

清書は既定で無効。清書は文章をきれいにするが、言い換えの過程で発話の意味を失うことが多かったため、原文をそのまま渡し、解釈は渡した先の生成 AI に任せる。使う場合は起動時に `VOICE_INPUT_CLEANUP` を指定する。

| 値 | 動作 |
| --- | --- |
| `0`（既定） | 清書しない。Whisper の原文を入力する。 |
| `1` | 清書する。フィラーと言い直しを削除し、句読点を整える。文体や言い回しも変わることがある。 |
| `2` | フィラー（えー、えっと、あのー、うーん など）とその直後の読点だけを消す。LLM の結果が原文から文字を消しただけで作れない場合（置き換え・追加がある場合や、1か所で9文字以上消した場合）は、原文を入力する。 |
| `3` | `2` の後に、読みが同じで漢字が違う誤変換（木字→目次、多数結→多数決 など）を直す。LLM には直した文ではなく「誤っている語と正しい語」の組だけを返させ、原文にあり、文字数が同じで、`kakasi` で調べた読みが一致する組だけを当てはめる。それ以外の文字は変わらない。 |

Hyprland のキー割り当てから起動する場合は、その割り当てのコマンドにも同じ環境変数を付ける。短い発話は設定に関係なく清書しない。`2` で弾いた LLM の結果は `transcript.rejected.txt` に残り、履歴の `cleanup_status` は `rejected` になる。フィラーを消せた場合は `filler_removed`。`3` の誤変換修正は履歴の `fix_status`（`applied` / `none` / `failed` / `unavailable` / `disabled`）、当てはめた組を `fixes`、条件を満たさず捨てた組を `rejected_fixes` に記録し、`voice-inputctl logs` の詳細にも表示する。読みの検査は言い換えを防ぐもので、同じ読みの別の語（漢字→感じ など）への誤った修正までは防げない。`kakasi` がなければ誤変換の修正だけを飛ばす。評価（Laya）は `1` の清書だけが対象。

既定では `127.0.0.1:8080/v1/chat/completions` の `gemma-4-E4B-it-qat` を使う。`voice-inputctl model` でサーバー上のモデルを選ぶと、次の音声入力から切り替わる。設定は `${XDG_CONFIG_HOME:-$HOME/.config}/voice-input/model` に保存する。`VOICE_INPUT_LLM_MODEL` が指定されていればそちらを優先する。接続先を変える場合は `VOICE_INPUT_LLM_URL` を指定し、一覧の接続先は `VOICE_INPUT_LLM_BASE_URL` で変える。モデルの読み込み時間も含めて15秒で打ち切り、Whisper の原文を入力する。清書は意味の取り違えがあり得るため、固有名詞・数字・指示文は使用前に確認する。

## モデルと履歴の操作

`voice-inputctl` は端末で動く操作画面。`fzf` と `jq` を使い、Web サーバーは不要。

```sh
voice-inputctl                      # メニューを開く
voice-inputctl model                # llama-server の一覧からモデルを選ぶ
voice-inputctl model show           # 現在のモデルを表示
voice-inputctl model reset          # 既定の Gemma に戻す
voice-inputctl logs                 # 履歴から1件選び、原文と入力文を表示
voice-inputctl logs --since 2026-10-21 --model gemma --status applied --text 会議
voice-inputctl logs --max-score 69  # 評価が低い入力だけ表示
voice-inputctl logs --json          # 絞り込んだ履歴を JSONL で出力
```

`model` の一覧にはサーバーが公開する全モデルが出るので、清書に使える会話モデルを選ぶ。端末のない実行環境では `voice-inputctl model モデルID` で直接指定できる。履歴は端末なら `fzf` で選択し、パイプなどでは一覧を TSV で出す。

## 清書の評価

清書を適用した入力は、文字入力後に判断モデル Laya Q8（`laya-q8`）で原文と清書文を比較する。llama.cpp の `/v1/systemone` に5段階の `score` 質問を送り、返った期待値を0〜100点に換算する。判定段階と各段階の確率も保存する。69点以下は確認候補として `voice-inputctl` の「低スコアを見る」または `voice-inputctl logs --max-score 69` で見られる。点数はこの用途で校正したものではなく、音声からの文字起こし精度も判定できない。[Laya のモデルカード](https://huggingface.co/ggml-org/Laya-GGUF)、[llama.cpp の API 仕様](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md#post-v1systemone-typesafe-compatible-system-one-api)。

評価は `${XDG_STATE_HOME:-$HOME/.local/state}/voice-input/judgments.jsonl` に保存する。`reason` は生成された説明ではなく、最も確率の高い判定段階のラベル。評価前の履歴は「未評価」、失敗時は「失敗」と表示する。`VOICE_INPUT_JUDGE_MODEL` で判断モデル、`VOICE_INPUT_JUDGE_URL` で API の接続先を指定でき、`VOICE_INPUT_JUDGE=0` で評価を無効にできる。履歴を無効にした場合も評価は動かない。Laya は `~/.config/llama.cpp/models.ini` の `laya-q8` プリセットに登録済み。llama-server は2モデルを同時保持し、Gemma と Laya を載せた実測 GPU 使用量は Whisper 込みで約8.2GB / 12GB。

評価に成功したら、文字入力の後で HUD に `音声入力: 清書評価 85点（意味は保持）` のように点数と decision の判定段階を表示する。69点以下は `要確認` を付ける。これは正解率ではなく、Laya の5段階評価を0〜100点に換算した値。評価失敗時は HUD に出さず、履歴に失敗状態を残す。HUD が使えない場合も入力と履歴記録は続く。

このマシンの `models.ini` には次のプリセットを追加した。Laya は CPU で動かす。

```ini
[laya-q8]
ui = false
hf = ggml-org/Laya-GGUF:Q8_0
n-gpu-layers = 0
batch-size = 512
ubatch-size = 512
```

`llama.cpp.service` では既存の `--models-preset` にこのファイルの絶対パスを指定し、`--models-max 2` を付ける。設定を変えたら `systemctl --user daemon-reload` と `systemctl --user restart llama.cpp.service` を実行する。

Laya Q8 の GPU 動作も、既存サービスとは別の一時サーバーで試した。同じ訂正を含む短文を `/v1/systemone` に5回送り、CPU と GPU で同じスコア（約82.5/100）が返った。以下は HTTP リクエスト全体の所要時間で、初回はモデルの起動時間を含まない。

| 実行先 | 1回目 | 2〜5回目 | Laya プロセスの GPU メモリ |
| --- | ---: | ---: | ---: |
| CPU（`n-gpu-layers = 0`） | 789ms | 約50ms | 182MiB |
| GPU（`n-gpu-layers = all`） | 122ms | 約14ms | 520MiB |

GPU 版を追加したときの空き VRAM は約1.0GiB（RTX 3060 12GiB、Whisper と清書モデルも稼働中）。GPU で試す場合は `[laya-q8]` の `n-gpu-layers` を `all` に変更する。現在の常用設定は `0` のまま。評価は文字入力後に走るので、入力完了までの時間にはこの差は含まれない。

## 入力履歴

入力が完了するたびに `${XDG_STATE_HOME:-$HOME/.local/state}/voice-input/history.jsonl` へ1行の JSON を追記する。`id` は評価ログとの照合に使う。`raw_text` は Whisper の原文、`output_text` は実際に入力した文。`whisper_model` と `llm_model` はモデル名、`cleanup_status` は `applied`（清書適用）、`failed`（清書失敗）、`short`（短文）、`disabled`（無効）、`unavailable`（jq なし）のいずれか。`whisper_ms`、`cleanup_ms`、`total_ms` はミリ秒で、全体時間は録音停止後の処理開始から文字入力完了までを測る。評価時間は `judgments.jsonl` の `judge_ms` に別記録する。Whisper が CPU に切り替わった場合の `whisper_ms` には GPU の試行も含む。Whisper サーバー側のモデル名を変えた場合は `VOICE_INPUT_WHISPER_MODEL` も合わせる。

```sh
jq -r '[.timestamp, .whisper_model, .llm_model, .cleanup_status, .whisper_ms, .cleanup_ms, .total_ms, .raw_text, .output_text] | @tsv' \
  "${XDG_STATE_HOME:-$HOME/.local/state}/voice-input/history.jsonl"
```

履歴には発話内容が含まれるため、保存先ディレクトリを `700`、ファイルを `600` にする。職場などで履歴を残したくない場合は、起動コマンドに `VOICE_INPUT_LOG=0` を付ける。Whisper や文字入力が失敗した試行は履歴に追加しない。

## 実行環境

- Hyprland の設定で `SUPER + H` に `env VOICE_INPUT_CLEANUP=3 voice-input`（フィラーを消して誤変換を直すモード）を割り当てる。設定ファイルはマシンによって違い、`~/.config/hypr/binds-omarchy.lua` または `~/.config/hypr/hyprland.lua` に置いている。
- 実際に呼ばれるファイルは `~/.local/bin/voice-input`。このディレクトリの `voice-input` が編集用の原本。
- 録音に `pw-record`、文字起こしにローカルの `whisper-server` を使う。GPU 側は `${XDG_DATA_HOME:-$HOME/.local/share}/whisper/ggml-medium-q8_0.bin`（`ggml-medium.bin` を `q8_0` に量子化したもの）、CPU への切替時は `ggml-small.bin` を使う。サーバーと CPU 版 CLI はパッケージ版の `/usr/bin/whisper-server` と `/usr/bin/whisper-cli`。
- 出力音量の変更と復元には `wpctl` を使う。録音開始時の出力先と音量を保存するため、途中で既定の出力先を変更しても元の出力先へ戻す。
- 清書にローカルの `llama-server` と `jq` を使う。サーバーが停止していても原文入力に戻る。
- 確認ダイアログに `quickshell`（`qs`）を使う。学習の比較に `diff` を使う。
- Whisper 原文のコピーと清書結果の入力に `wl-copy` と `hyprctl eval` を使う。貼り付けが使えない環境では `wtype` と `fcitx5-remote` を使う。

## CUDA 版 Whisper サーバー

Arch Linux のパッケージ版 `whisper-cpp` は CUDA に対応しているため、自分でビルドする必要はない。GPU 処理には ggml の CUDA バックエンド `ggml-cuda` も入れる。

```sh
sudo pacman -S whisper-cpp ggml-cuda
```

`whisper-server` と `whisper-cli` が `/usr/bin` に入り、CUDA バックエンドは実行時に `/usr/lib/ggml/libggml-cuda.so` から読み込まれる。モデルは別途 `${XDG_DATA_HOME:-$HOME/.local/share}/whisper/` に `ggml-medium.bin` と `ggml-small.bin` を置く。

GPU 側は VRAM を節約するため、`ggml-medium.bin` を `q8_0` に量子化して使う。f16 の約 1.5GB に対して約 0.8GB で、日本語の認識結果は f16 と変わらなかった。

```sh
whisper-quantize ~/.local/share/whisper/ggml-medium.bin ~/.local/share/whisper/ggml-medium-q8_0.bin q8_0
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

`/health` が `{"status":"ok"}` を返したら利用できる。GPU を使えているかはサーバーの起動ログで確認する。`ggml_cuda_init: found 1 CUDA devices` と `load_backend: loaded CUDA backend from /usr/lib/ggml/libggml-cuda.so` が出ていれば CUDA で動いている。

## 参考: ソースからの CUDA ビルド

パッケージ版が CUDA に対応する前は、whisper.cpp を自分でビルドしていた。現在は不要だが、パッケージ版が使えない場合の参考として残す。RTX 4070 向けに CUDA 版を別のビルドディレクトリに作り、CPU 版ビルド（`~/src/whisper.cpp/build`）はそのまま残していた。

```sh
cmake -S ~/src/whisper.cpp -B ~/src/whisper.cpp/build-cuda \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_CUDA_ARCHITECTURES=89 \
  -DGGML_CUDA=ON -DWHISPER_BUILD_SERVER=ON
cmake --build ~/src/whisper.cpp/build-cuda -j 4
```

この場合は service の `ExecStart` を `%h/src/whisper.cpp/build-cuda/bin/whisper-server`、`voice-input` の `whisper_cli` を `$HOME/src/whisper.cpp/build/bin/whisper-cli` に変える。

## 随時入力をやめた理由

以前は約0.4秒の無音、または最大3秒で音声を区切り、0.8秒程度の短い区間まで個別に認識していた。短い区間では前後の文脈が使えず、言い直しや発話中の間で文が切れ、「(音声)(笑)」のような余計な出力も出た。区間ごとのリクエストも増えた。実際にユーザーが比較したところ、CPU の small モデルによる一括入力の方が修正が少なかった。

随時入力では認識結果を録音中に `wtype` で送るため、`SUPER + H` の停止操作と打鍵が重なり、DMS の電源メニューが開く現象も起きた。一括入力に戻してからも再発したため、録音方式だけでは防げない。原因となったキーイベントは特定できていない。安定した随時入力には、発話の区切り、途中結果の確定と訂正、入力先のフォーカス、物理キーと仮想キーの競合を扱う必要がある。

## `SUPER` キーとの干渉対策

`SUPER + H` の割り当てと同じ Hyprland の設定ファイル（`~/.config/hypr/binds-omarchy.lua` または `~/.config/hypr/hyprland.lua`）に、次の submap を定義する。入力処理が予期せず止まって submap が残った場合は `F12` で通常のキー割り当てに戻せる。

```lua
voice_input_paste = universal_paste

-- 音声入力が止まったときの非常口。確認ダイアログを閉じて submap を戻す（voice-input は何も貼らない）
local function exit_voice_input_typing()
  hl.dispatch(hl.dsp.exec_cmd("pkill -f voice-input-dialog.qml"))
  hl.dispatch(hl.dsp.submap("reset"))
end

hl.define_submap("voice_input_typing", function()
  hl.bind("F12", exit_voice_input_typing, { description = "Exit voice input typing" })
end)
```

`voice_input_paste` は `SUPER + V` の `universal_paste` をグローバルに公開したもので、`voice-input` が `hyprctl eval` から呼ぶ。`universal_paste` を定義した後に書く。`voice-input` は録音停止後、この submap に切り替えてから変換・文字入力する。通常の `SUPER` ショートカットが文字入力中に発火するのを防ぎ、終了時はエラーが起きても元へ戻す。Hyprland の設定を変更したら `hyprctl reload` で反映する。

## cli-hud との連携

`voice-input` は `${XDG_RUNTIME_DIR}/voice-input/` に状態を置く。`~/.local/bin/hud-probe` がこれを読み、`~/.config/quickshell/cli-hud/shell.qml` が1秒ごとに `hud-probe` を実行して表示を更新する。

| 状態 | `voice-input` が書くファイル | `hud-probe` の判定 | HUD の表示 |
| --- | --- | --- | --- |
| 録音中 | `recording.pid` に録音処理の PID | ファイルがあり、PID が生きている | `● 音声入力: 録音中  (SUPER + H で確定)` |
| 文字起こし中 | `hud-status` に `<PID> transcribing` | PID が生きている | `音声入力: 文字起こし中…` |
| CPU へ切替 | 既存の `hud` と `hud-status` を呼び出す | 5 秒の通知と、終了までの状態表示 | `GPU処理失敗、CPUへ切替` / `CPUで処理中` |
| VRAM 不足 | 切替後の `whisper-cli` が `out of memory` で失敗したら `hud` を呼ぶ | 5 秒の通知 | `音声入力: VRAM不足で処理できません` |
| 清書評価 | 文字入力後に `voice-input-judge` が `hud` を呼ぶ | 評価成功時の通知 | `音声入力: 清書評価 85点（意味は保持）` / `音声入力: 清書評価 42点 要確認（重要な情報に差）` |
| 終了後 | 状態ファイルなし | 状態なし | 非表示 |

2回目の起動時に録音を止め、文字起こしが終わったら状態ファイルを消す。通常のデスクトップ通知は出さない。

## デモ録画

`ALT + Print` で範囲を選んで録画を開始する。録画中は HUD に経過時間と停止方法を表示する。終了はもう一度 `ALT + Print`、または端末から `screenrec stop`。直接 `wf-recorder` を起動した録画も HUD が検出し、`screenrec stop` で停止できる。録画していないときの `screenrec stop` は新しい録画を始めない。

`ALT + Print` の録画は映像のみ。音声入力のデモをマイク音声付きで撮る場合は、範囲を選び、次のように `wf-recorder` を起動する。

```sh
wf-recorder -c h264_nvenc -g "$(slurp)" \
  --audio="$(pactl get-default-source)" \
  -f "$HOME/Videos/voice-input-demo.mp4"
```

終了は別の端末から `screenrec stop`。録画中の音量は元の20%になるが、再生音がマイクに届けば動画にも入る。実演では音声入力HUDと、認識した文章が入力先に現れるところまで記録できる。

## テスト

`shellcheck` と `bats` を使う。

```sh
sudo pacman -S --needed shellcheck bats kakasi
make test
```

`make test` は `shellcheck voice-input voice-inputctl voice-input-judge deploy` の後に `tests/voice-input.bats` を実行する。GitHub Actions（`.github/workflows/test.yml`）でも push と pull request のたびに同じ `make test` を Ubuntu 上で実行する。テストでは `wpctl`、`pw-record`、`hyprctl`、`curl`、`whisper-cli`、`wl-copy`、`wtype`、`fcitx5-remote`、`hud`、`hud-status` を偽のコマンドに置き換える。実際の録音、GPU、Hyprland、入力先は使わない。`HOME`、`XDG_RUNTIME_DIR`、`XDG_STATE_HOME`、`XDG_CONFIG_HOME` もテストごとの一時ディレクトリに向けるので、実行中の音声入力の状態には触れない。CPU 版 CLI のパスは環境変数 `VOICE_INPUT_WHISPER_CLI` で差し替える（既定は `/usr/bin/whisper-cli`）。清書と履歴の成功・失敗・無効化、モデル設定、評価の記録と絞り込みを確認する。

主に確かめている内容:

- 録音開始時に出力音量を20%に下げ、停止時に戻す。ミュート中や既定の出力先がない場合も録音は始まる。
- GPU が失敗するか空の結果を返したら、HUD に表示して CPU で再処理する。
- 切替後の `whisper-cli` も VRAM 不足で失敗したら、HUD に表示して何も入力しない。
- 入力は `voice_input_typing` submap の中で行う。`voice_input_paste` があれば貼り付け、なければ `wtype` で打ち込む。失敗しても submap、IME、状態ファイルを元に戻す。

## 変更の反映

このディレクトリのスクリプトを編集したら、`deploy` で3コマンドを `~/.local/bin/` に、確認ダイアログを `${XDG_DATA_HOME:-$HOME/.local/share}/voice-input/` に反映する。別の配置先を使う場合は引数で指定できる。

```sh
./deploy
# 配置先を変える場合: ./deploy /path/to/bin
```

次の `SUPER + H` から新しい内容が使われる。`cli-hud` 側の表示文言や更新間隔を変える場合は `~/.config/quickshell/cli-hud/shell.qml`、状態の判定を変える場合は `~/.local/bin/hud-probe` を編集する。
