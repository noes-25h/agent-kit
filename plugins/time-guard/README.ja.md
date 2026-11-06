# time-guard

English: [README.md](README.md)

Claude Code の plugin。Claude Code は今日の日付を Claude に渡すが、今の時刻は渡さない。長いセッションでは、会話に出た古い時刻を今として使ったり、時計を見ないまま「今朝」と書いたりすることが起きうる。この plugin はそこに 3 つのことをする。

1. プロンプトのたびに、そしてセッションの開始・再開・圧縮の時に、システムの時計を読んで今の日付と時刻を Claude に渡す。
2. Claude が書こうとしている文章に、時刻や日付の裏づけが無い時間の言い回し (「今朝」「明日」「何時間も」) があれば、今の時刻を載せた知らせを Claude に足す。書き込みは止めない。
3. skill を 1 つ足す。`/time-guard:now` は呼ばれた時点の時計を読む。

25h が自分たちの作業環境で使っている hook を、単体で動く形に直したもの。

**今の状態: 実物の Claude Code での検査は、この版 (0.1.1) で 2026-10-31 に Claude Code 2.1.314 で通った。** hook 単体と入れ方は空の環境で確かめ、この plugin を入れた Claude Code が時刻と知らせを実際に Claude へ渡すことは `tests/live-check.sh` で確かめた (「確かめ方」を参照)。1 台の機械での 1 回なので、Claude Code を更新したら走らせ直してほしい。

## 届かない所

入れる前に読んでほしい。

- 長い 1 ターンの途中。時計を読むのはプロンプトを送った時。そのあと Claude が新しいプロンプト無しで 1 時間作業すれば、その値は 1 時間古い。書き込みの時の知らせと skill は新しい時刻を持つが、他には無い。
- ファイルの道具を通らない文章。言い回しの検査が見るのは Write・Edit・MultiEdit・NotebookEdit。コミットメッセージ、シェルのコマンドで書いたファイル、チャットの返答は見ない。
- 対象の外のファイル。既定では、名前が `.md` `.mdx` `.txt` `.rst` `.org` `.adoc` で終わるファイルだけを見る。
- 表に無い言い回し。表は 7 行で、英語と日本語。`plugins/time-guard/scripts/config.sh` に在る。
- 間違った時刻。検査が探すのは、値が添えられていない言い回し。`14:30` が正しい時刻かどうかは分からない。1 つの文に時刻か日付が在れば、その文では時間帯の行は働かない。
- 今を指さない時間帯の語。「夕方の判断は遅い」も「今朝」と同じく知らせが出る。見分けられない。
- 年も「月」「日」も無い日付。`5/9` のような書き方は日付と見なさない。
- Claude がそれをどう使うか。plugin は値と知らせを渡すだけで、使うことを強制しない。
- 再開したセッション。Claude Code は前のターンの時刻の行を、記録に残った当時のまま再生する。いちばん新しい行が今の値で、どの行にもいつ読んだかが書いてある。

plugin はプロンプトごとに約 300 文字の文脈を足す。skill の説明文はセッションごとに 150 トークン未満を足す (`claude plugin details` の表示)。

## 要る物

- Claude Code。確かめた版は 2.1.314。
- macOS か Linux。bash・date・grep・sed・awk・tr・jq を使う。Windows は対象外。
- jq が無い場合、プロンプトごとの時計は動く。言い回しの検査は動かず、書き込みのたびに知らせが出る。

## 入れ方

次の 2 つを順に実行する。Claude Code は GitHub の `noes-25h/agent-kit` から plugin を取ってくる。この repository の別の plugin を入れた時に 1 つ目を済ませていれば、2 つ目だけでよい。

```bash
claude plugin marketplace add noes-25h/agent-kit
```

```bash
claude plugin install time-guard@25h-agent-kit
```

入ったかどうかは次で見られる。`time-guard@25h-agent-kit` が `enabled` と出ていれば入っている。

```bash
claude plugin list
```

開いている Claude Code のセッションには、開き直すか `/reload-plugins` を打つと効く。全部のプロジェクトに効く。自分の `settings.json` の hook は書き換えない。

入れずに 1 回だけ試したい時は、この repository を clone し (`git clone https://github.com/noes-25h/agent-kit`)、その一番上のフォルダで、起動の時にフォルダを指す。

```bash
claude --plugin-dir ./plugins/time-guard
```

## 確かめ方

この節のコマンドは、この repository を clone した一番上のフォルダで打つ (`git clone https://github.com/noes-25h/agent-kit`)。

確かめる段は 2 つある。1 つ目だけでは足りない。

**hook 単体。** Claude Code が渡すのと同じ入力を hook に流し、117 通りを検査する。時刻がシステムの時計と合うか、時間帯が環境と設定に従うか、返す値が受け取られる形か、言い回しの検査が一度も止めないか。Claude Code は呼ばない。数秒で終わる。

```bash
bash ./plugins/time-guard/tests/selftest.sh
```

**実物の Claude Code。** plugin ありで 2 回、なしで 2 回、Claude Code を走らせる。手元の機械と違う時間帯の時刻を分まで Claude に答えさせ、書き込みの後に知らせを復唱させる。数分かかり、利用枠を 4 回分使う。

```bash
bash ./plugins/time-guard/tests/live-check.sh
```

素の端末から走らせる。結果は 3 つに分かれる。終了コード 0 は、hook が動いて、時刻と知らせは Claude に届いている。1 は、hook が動いたのに、時刻か知らせが届いていない。2 は判定できない。呼び出しが最後まで走らなかった時、plugin なしの側が比較にならない時、hook が動かなかった時がこれに当たる。

検査は、Claude Code が記録する hook の行を数えている。この plugin の hook が 1 回も最後まで動いていなければ、理由を 1 行で出し、判定は出さない。sandbox の中から走らせた時がこうなる。Claude Code のセッションの中から走らせた時もそう。Claude Code が plugin の置き場 `~/.claude/plugins/data/` を作れず、hook を起こさないので、Claude には何も届かない。その時の失敗の行には `EPERM` か `operation not permitted` と出る。素の端末を開いて走らせ直す。

2 つ目が要る理由: hook が返す値の形が少しでも違うと、Claude Code は黙って捨てる。エラーは出ない。1 つ目が全部通っていても、Claude には何も届いていないことがある。Claude Code を更新した後は 2 つ目を走らせ直す。

2 つ目は、25h で 2026-10-31 に Claude Code 2.1.314 で走らせた (版 0.1.1)。plugin に渡した時間帯は UTC。終了コード 0 で終わった。plugin ありでは、答えた時刻が UTC のシステムの時計と合い、知らせの言い回しが返答に出た。なしでは、どちらも出なかった。ファイルはどちらの側でも書かれた。知らせは止める物ではないため。hook は 5 回起き、5 回とも最後まで走った。

## 何が起きるか

**プロンプトのたび。** Claude は次のような 1 行を受け取る。画面には何も出ない。

```
Current local time: 2026-10-09 (Fri) 07:04:31, UTC+09:00 (JST). This value was read from the system clock when this prompt was submitted (time zone of this machine). Dates and times that appear earlier in this conversation were read earlier and are older than this value.
```

**裏づけの無い時間の言い回しを書いた時。** 書き込みは実行される。Claude は書き込みの結果と一緒に次の知らせを受け取る。

```
time-guard: the text being written to notes.md has time wording that is not backed by a value in the same text: 'this morning' (no clock time or date in the same sentence). Current local time: 2026-10-09 (Fri) 07:04:31, UTC+09:00 (JST) (time zone of this machine). The write was not blocked.
```

言い回しは 3 種類。

| 種類 | 例 | 見逃す時 |
|---|---|---|
| 時間帯 | 今朝、午後、深夜、this morning、last night | 同じ文に時刻 (`14:30` や `9時` や `6 pm`) か日付が在る |
| 相対の日 | 昨日、明日、yesterday、tomorrow | 文章のどこかに日付 (`2026-10-09` や `10月9日`) が在る。見出しの日付は文章全体に掛かる |
| 長さ | 何時間も、丸一日、for hours | 見逃さない |

文の切れ目は、改行、`。` の後ろ、空白が続く `.` `!` `?` の後ろ。議事録の頭に「14:00 開始。」と在っても、別の文の「今朝」には知らせが出る。「3時間」のような長さは時刻と見なさない。

そういう言い回しを消す編集には知らせを出さない。置き換えられて消える側の文字列は見ない。

**時計を読めなかった時。** プロンプトには何も足さない。作り物の時刻より、無い方がよい。

**時間の言い回しが無い書き込み。** 何も起きない。何も出ない。

## 調整

触るのは `plugins/time-guard/scripts/config.sh` だけ。

- 時間帯。既定では機械の時間帯を使う。環境変数 `TZ` が在ればそれに従う。別の時間帯に固定するには `TG_TZ` に `Europe/Berlin` のような IANA の名前を書く。環境変数 `TIME_GUARD_TZ` は `TG_TZ` より優先される。機械が知らない名前は使わず、システムの時間帯を示して、そのことを文に書く。
- 見るファイル。`TG_PATHS` はファイル名のパターンの並び。`*` にすると全部のファイルを見る。
- 画面への知らせ。`TG_SHOW_USER` を 1 にすると、言い回しを見つけるたびに 1 行が画面に出る。既定では Claude だけが知らせを受け取る。
- 言い回しの表。1 行が 1 パターンで、3 列 (種類・名前・正規表現)。見るのをやめるには行を消す。足すには 1 行足し、同じ名前の見本を `tests/selftest.sh` の `tg_sample` に足す。見本の無い行があると selftest が落ちる。

行を足したり消したりした時は、`tests/selftest.sh` の終わり近くに在る控え (`TG_EXPECT_ROWS`) も同じに直す。直さないと selftest の最後の検査が落ちる。行が知らないうちに消えるのを防ぐための控え。

変える時は、この repository を clone して中のファイルを直し、GitHub からでなく clone から入れる (clone の 1 つ上で `claude plugin marketplace add ./agent-kit`)。plugin は clone から直接読まれる。 GitHub から入れ済みなら、登録先 `25h-agent-kit` が clone に付け替わり、入れ済みの plugin も以後は clone から更新される。戻す時は `claude plugin marketplace add noes-25h/agent-kit` を打ち直す。変更は、Claude Code を開き直すか、セッションで `/reload-plugins` を打つと効く。変えるたびに selftest を走らせる。最初の節に、今効いている設定が出る。

## 外し方

```bash
claude plugin uninstall time-guard@25h-agent-kit
```

```bash
claude plugin marketplace remove 25h-agent-kit
```

2 つ目は、更新元として覚えた repository の登録を消す。この repository の別の plugin を使い続ける時は、2 つ目は打たない。

外した後、Claude Code の設定フォルダ (`~/.claude/plugins/cache/25h-agent-kit/`) に plugin の写しが残る。もう読まれないので、手で消してよい。`settings.json` には何も残らない。

## 配線

使うイベントと、hook が返す値の形は、公式の hooks リファレンスに合わせた: https://code.claude.com/docs/en/hooks (2026-10-09 に読んだ)。

| イベント | スクリプト | 返す物 |
|---|---|---|
| `UserPromptSubmit` | `scripts/now.sh` | `hookSpecificOutput.additionalContext`。プロンプトと一緒に足される |
| `SessionStart` | `scripts/now.sh` | `hookSpecificOutput.additionalContext`。会話の頭に足される。再開と圧縮の後にもう一度走る |
| `PreToolUse` (Write・Edit・MultiEdit・NotebookEdit) | `scripts/check-write.sh` | `hookSpecificOutput.additionalContext`。道具の結果と一緒に足される。`permissionDecision` は返さないので、権限の流れには触らない |

skill は、skills のページに在る `${CLAUDE_PLUGIN_ROOT}` と `` !`command` `` の形を使う: https://code.claude.com/docs/en/skills 。設定で `disableSkillShellExecution` が入になっていると、skill は自分で時計を読めず、Claude に `date` を実行するよう伝える。

## ライセンス

MIT。[LICENSE](LICENSE) を見る。
