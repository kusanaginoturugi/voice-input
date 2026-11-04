// voice-input の確認ダイアログ。認識結果を直してから貼り付けるために使う。
// Enter は改行、Ctrl+Enter で送信、Esc で何も貼らずにやめる。Emacs の基本的なキーバインドで編集できる。
// VOICE_INPUT_DIALOG_IN の文を表示し、送信したら VOICE_INPUT_DIALOG_OUT に書いて終わる。
// やめたときは VOICE_INPUT_DIALOG_CANCEL を作って終わる。どちらもなければ、起動か保存に失敗している。
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    readonly property string inPath: Quickshell.env("VOICE_INPUT_DIALOG_IN") || ""
    readonly property string outPath: Quickshell.env("VOICE_INPUT_DIALOG_OUT") || ""
    readonly property string cancelPath: Quickshell.env("VOICE_INPUT_DIALOG_CANCEL") || ""

    FileView {
        id: input
        path: root.inPath
        blockLoading: true
    }

    FileView {
        id: output
        path: root.outPath
        preload: false
        onSaved: Qt.quit()
        onSaveFailed: Qt.exit(1)
    }

    FileView {
        id: cancelled
        path: root.cancelPath
        preload: false
        onSaved: Qt.quit()
        onSaveFailed: Qt.exit(1)
    }

    PanelWindow {
        id: window

        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "voice-input-dialog"
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        implicitWidth: 760
        implicitHeight: 300

        Rectangle {
            anchors.fill: parent
            radius: 12
            color: "#1e1e2e"
            border.color: "#89b4fa"
            border.width: 2

            Column {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10

                Text {
                    text: "音声入力: 直してから Ctrl+Enter で貼り付け（Enter は改行、Esc でやめる）"
                    color: "#a6adc8"
                    font.pixelSize: 13
                }

                ScrollView {
                    width: parent.width
                    height: parent.height - 33

                    TextArea {
                        id: editor

                        // Emacs のマーク。-1 ならマークなし
                        property int mark: -1
                        // C-n / C-p を続けたときに保つ横位置
                        property real goalX: -1
                        property string killBuffer: ""

                        text: input.text().replace(/\n$/, "")
                        wrapMode: TextEdit.Wrap
                        color: "#cdd6f4"
                        selectionColor: "#585b70"
                        selectedTextColor: "#cdd6f4"
                        font.pixelSize: 18
                        focus: true
                        background: null
                        Component.onCompleted: {
                            forceActiveFocus()
                            cursorPosition = length
                        }

                        // マークがあれば、マークから pos までを選択する
                        function go(pos) {
                            pos = Math.max(0, Math.min(length, pos))
                            if (mark >= 0) {
                                cursorPosition = mark
                                moveCursorSelection(pos, TextEdit.SelectCharacters)
                            } else {
                                cursorPosition = pos
                            }
                        }

                        function clearMark() {
                            if (mark >= 0) {
                                const pos = cursorPosition
                                deselect()
                                cursorPosition = pos
                                mark = -1
                            }
                        }

                        function lineStart(pos) {
                            return text.lastIndexOf("\n", pos - 1) + 1
                        }

                        function lineEnd(pos) {
                            const i = text.indexOf("\n", pos)
                            return i < 0 ? length : i
                        }

                        // 表示上の次の行・前の行へ動く（折り返しも1行として数える）
                        function lineMove(direction) {
                            const r = positionToRectangle(cursorPosition)
                            if (goalX < 0)
                                goalX = r.x
                            const y = direction > 0 ? r.y + r.height * 1.5 : r.y - r.height * 0.5
                            if (y < 0)
                                return 0
                            if (y > contentHeight)
                                return length
                            return positionAt(goalX, y)
                        }

                        // 単語の区切りは文字の種類が変わるところ。0 は空白・記号
                        function charClass(c) {
                            if (/[\s\p{P}\p{S}]/u.test(c)) return 0
                            if (/\p{Script=Hiragana}/u.test(c)) return 1
                            if (/[\p{Script=Katakana}ー]/u.test(c)) return 2
                            if (/\p{Script=Han}/u.test(c)) return 3
                            return 4
                        }

                        function wordForward(pos) {
                            while (pos < length && charClass(text[pos]) === 0) pos++
                            const c = pos < length ? charClass(text[pos]) : 0
                            while (pos < length && charClass(text[pos]) === c) pos++
                            return pos
                        }

                        function wordBackward(pos) {
                            while (pos > 0 && charClass(text[pos - 1]) === 0) pos--
                            const c = pos > 0 ? charClass(text[pos - 1]) : 0
                            while (pos > 0 && charClass(text[pos - 1]) === c) pos--
                            return pos
                        }

                        function kill(start, end) {
                            if (start === end) return
                            const from = Math.min(start, end)
                            const to = Math.max(start, end)
                            killBuffer = text.slice(from, to)
                            clearMark()
                            remove(from, to)
                            cursorPosition = from
                        }

                        function emacsKey(event) {
                            const ctrl = event.modifiers & Qt.ControlModifier
                            const alt = event.modifiers & Qt.AltModifier
                            const pos = cursorPosition
                            const key = event.key
                            if (ctrl && !alt) {
                                switch (key) {
                                case Qt.Key_F: go(pos + 1); return true
                                case Qt.Key_B: go(pos - 1); return true
                                case Qt.Key_N: go(lineMove(1)); return "keepGoal"
                                case Qt.Key_P: go(lineMove(-1)); return "keepGoal"
                                case Qt.Key_A: go(lineStart(pos)); return true
                                case Qt.Key_E: go(lineEnd(pos)); return true
                                case Qt.Key_D: clearMark(); remove(pos, Math.min(length, pos + 1)); return true
                                case Qt.Key_H: clearMark(); if (pos > 0) remove(pos - 1, pos); return true
                                case Qt.Key_K: {
                                    const end = lineEnd(pos)
                                    kill(pos, end === pos ? Math.min(length, pos + 1) : end)
                                    return true
                                }
                                case Qt.Key_W:
                                    if (mark >= 0) kill(mark, pos)
                                    return true
                                case Qt.Key_Y:
                                    clearMark()
                                    if (killBuffer !== "") insert(cursorPosition, killBuffer)
                                    else paste()
                                    return true
                                case Qt.Key_Space:
                                case Qt.Key_At:
                                    mark = pos
                                    return true
                                case Qt.Key_G: clearMark(); return true
                                case Qt.Key_J: clearMark(); insert(cursorPosition, "\n"); return true
                                case Qt.Key_Slash:
                                case Qt.Key_Underscore:
                                    clearMark(); undo(); return true
                                }
                            } else if (alt && !ctrl) {
                                switch (key) {
                                case Qt.Key_F: go(wordForward(pos)); return true
                                case Qt.Key_B: go(wordBackward(pos)); return true
                                case Qt.Key_D: kill(pos, wordForward(pos)); return true
                                case Qt.Key_Backspace: kill(wordBackward(pos), pos); return true
                                case Qt.Key_Less: go(0); return true
                                case Qt.Key_Greater: go(length); return true
                                case Qt.Key_W:
                                    if (mark >= 0) {
                                        killBuffer = text.slice(Math.min(mark, pos), Math.max(mark, pos))
                                        clearMark()
                                    }
                                    return true
                                }
                            }
                            return false
                        }

                        Keys.onPressed: event => {
                            // SKK の変換中はキーを横取りしない（Esc で変換をやめたつもりが、ダイアログごと閉じないように）
                            if (preeditText !== "")
                                return
                            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                    && (event.modifiers & Qt.ControlModifier)) {
                                output.setText(text)
                                event.accepted = true
                                return
                            }
                            if (event.key === Qt.Key_Escape) {
                                cancelled.setText("")
                                event.accepted = true
                                return
                            }
                            const handled = emacsKey(event)
                            if (handled !== "keepGoal")
                                goalX = -1
                            if (handled) {
                                event.accepted = true
                            } else if (mark >= 0 && event.text !== "") {
                                // 選択中に文字を打っても、選択範囲を消さない（Emacs と同じ）
                                clearMark()
                            }
                        }
                    }
                }
            }
        }
    }
}
