# secret-guard

English: [README.md](README.md)

Claude Code の plugin。API の鍵が Claude の手で外へ出ていくのを 2 か所で受け止める。

1. 鍵の形をした文字列を含む操作を、実行の前に止める。対象は Bash の実行と、ファイルへの書き込み・編集。
2. 成功した Bash の出力に鍵の形が出たら、Claude に渡る前にその部分を伏せ字に差し替える。

25h が自分たちの作業環境で使っている hook を、単体で動く形に直したもの。

## 守らない所

入れる前に読んでほしい。ここに書いた経路では、鍵は Claude に渡る。

- 失敗したコマンドの出力。終了コードが 0 でない Bash の出力は、Claude Code の仕様で差し替えられない。鍵の形があれば知らせは出るが、Claude には渡っている。
- Read や Grep で読んだファイルの中身。`.env` を Claude に読ませないようにするには、Claude Code 標準の権限設定で読み取りを拒否する。
- 自分でプロンプトに貼った鍵。
- 生の記録。伏せ字になるのは Claude に渡る分だけで、手元の記録ファイル (transcript) には元の出力が残る。
- 表に無い形の鍵。見ているのは 15 種 (多くは決まった接頭辞を持つ) と PEM 形式の秘密鍵だけ。一覧は `plugins/secret-guard/scripts/patterns.sh`。

伏せ字になっても、本物の鍵が出力に出たなら発行し直すのが安全。この plugin は発行し直す回数を減らす物で、不要にする物ではない。

## 要る物

- Claude Code。確かめた版は 2.1.316。
- macOS か Linux。bash・grep・sed・awk・jq を使う。Windows は対象外。
- jq が無い場合、実行前に止める側は動くが、出力の伏せ字は動かない。その時は毎回知らせが出る。

## 入れ方

次の 2 つを順に実行する。Claude Code は GitHub の `noes-25h/agent-kit` から plugin を取ってくる。この repository の別の plugin を入れた時に 1 つ目を済ませていれば、2 つ目だけでよい。

```bash
claude plugin marketplace add noes-25h/agent-kit
```

```bash
claude plugin install secret-guard@25h-agent-kit
```

入ったかどうかは次で見られる。`secret-guard@25h-agent-kit` が `enabled` と出ていれば入っている。

```bash
claude plugin list
```

開いている Claude Code のセッションには、開き直すか `/reload-plugins` を打つと効く。全部のプロジェクトに効く。自分の `settings.json` の hook は書き換えない。

入れずに 1 回だけ試したい時は、この repository を clone し (`git clone https://github.com/noes-25h/agent-kit`)、その一番上のフォルダで、起動の時にフォルダを指す。

```bash
claude --plugin-dir ./plugins/secret-guard
```

## 確かめ方

この節のコマンドは、この repository を clone した一番上のフォルダで打つ (`git clone https://github.com/noes-25h/agent-kit`)。

確かめる段は 2 つある。1 つ目だけでは足りない。

**hook の中身** — 偽の鍵を流して、止まる・通る・伏せ字になる、を 95 項目で検査する。Claude Code は呼ばない。数秒で終わる。

```bash
bash ./plugins/secret-guard/tests/selftest.sh
```

**実物の Claude Code** — Claude Code を plugin あり・なしで 3 回ずつ走らせ、Claude に渡った結果に偽の鍵が何件残ったかを数える。数分かかり、6 回分の利用枠を使う。

```bash
bash ./plugins/secret-guard/tests/live-check.sh
```

素の端末から走らせる。結果は 3 つに分かれる。終了コード 0 は、hook が動いて、鍵は止まっている。1 は、hook が動いたのに、鍵が通った。2 は判定できない。呼び出しが最後まで走らなかった時、plugin なしの側が比較にならない時、hook が動かなかった時がこれに当たる。

検査は、Claude Code が記録する hook の行を数えている。この plugin の hook が 1 回も最後まで動いていなければ、理由を 1 行で出し、判定は出さない。sandbox の中から走らせた時がこうなる。Claude Code のセッションの中から走らせた時もそう。Claude Code が plugin の置き場 `~/.claude/plugins/data/` を作れず、hook を起こさないまま道具を通す。その時の失敗の行には `EPERM` か `operation not permitted` と出る。素の端末を開いて走らせ直す。

2 つ目が要る理由。hook は、返す値の形が少し違うだけで Claude Code に黙って捨てられる。エラーは出ない。1 つ目の検査は全部通るのに、実際には何も伏せられていない、という状態が起こる。Claude Code の版が上がった後にも、2 つ目を走らせると確かめられる。

## 何が起きるか

**止まった時。** Claude が鍵を含むコマンドやファイルを書こうとすると、その操作は実行されない。Claude には次の文が渡る。hook が出す文は英語。

```
secret-guard: blocked this call because it contains a string that matches the github-token key pattern. Do not write the value inline; read it from an environment variable or a secret store instead.
```

鍵を消す編集は止まらない。置き換えられて消える側の文字列は見ていない。jq が無い時は呼び出し全体を見るので、この編集も止まる。

**伏せ字になった時。** コマンドは最後まで実行される。Claude に渡る出力だけが変わる。

```
元の出力:        token: ghp_xxxxxxxx…
Claude に渡る分:  token: [REDACTED-BY-SECRET-GUARD]
```

画面には、伏せ字にしたことと、生の記録には残っていることが 1 行で出る。

**失敗したコマンドに鍵が出た時。** 伏せられない。画面に知らせが出て、Claude には「その値を引用・再利用しない」という注意が渡る。

**鍵の無い操作。** 何も起きない。画面にも何も出ない。

## 調整

`plugins/secret-guard/scripts/patterns.sh` の表だけを触る。1 行が 1 種類の鍵。

- 止めたくない種類は、行の `B` を `R` に変える。伏せ字だけになる。
- 見なくてよい種類は、行を消す。
- 足す時は、名前・段・正規表現の 3 列を 1 行足し、`tests/selftest.sh` の `sg_sample` に同じ名前の見本を足す。見本の無い行があると selftest が落ちる。
- `"password": "..."` のような書き方も止めたい時は、`SG_BLOCK_LITERALS` を 1 にする。テスト用のデータや設定の見本でも止まるようになる。

段を変えたり行を消したりした時は、`tests/selftest.sh` の末尾近くにある控え (`SG_EXPECT_B` と `SG_EXPECT_R`) も同じに直す。直さないと selftest の最後の検査が落ちる。止める行が気づかないうちに減るのを防ぐための控え。

変える時は、この repository を clone して中のファイルを直し、GitHub からでなく clone から入れる (clone の 1 つ上で `claude plugin marketplace add ./agent-kit`)。plugin は clone から直接読まれる。 GitHub から入れ済みなら、登録先 `25h-agent-kit` が clone に付け替わり、入れ済みの plugin も以後は clone から更新される。戻す時は `claude plugin marketplace add noes-25h/agent-kit` を打ち直す。変えた内容は、Claude Code を開き直すか、セッションの中で `/reload-plugins` を打つと効く。変えた後は selftest を走らせる。

## 外し方

```bash
claude plugin uninstall secret-guard@25h-agent-kit
```

```bash
claude plugin marketplace remove 25h-agent-kit
```

2 つ目は、更新元として覚えた repository の登録を消す。この repository の別の plugin を使い続ける時は、2 つ目は打たない。

外した後、Claude Code の設定フォルダ (`~/.claude/plugins/cache/25h-agent-kit/`) に hook の写しが残る。もう読まれない写しで、手で消してよい。`settings.json` には何も残らない。

## ライセンス

MIT。[LICENSE](LICENSE) を見る。
