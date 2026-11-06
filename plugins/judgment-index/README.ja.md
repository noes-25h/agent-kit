# judgment-index

English: [README.md](README.md)

Claude Code の plugin と、それが repo に展開する空の型。型は判断基準の索引で、AI が「これをしてよいか」と聞きそうな場面ごとに 1 行を持つ。1 行には、どう動くか、誰が決めるか、出どころ、反証を書く。

中身は 5 つ。

1. 索引と分類。`INDEX.md` と分類ファイル 15 本。分類は AI がこれから何をするかの動詞で、choose / set / publish / touch-live / unblock / reconcile / adopt / build / spend / respond / repair / assess / interpret / verify / allocate。各分類に見本の行が 1〜2 行入っている。
2. 道具。`judgment.py` 1 本で、Python の標準ライブラリだけで動く。行の形を検査し、各分類の頭に置く目次を生成する。
3. skill `consult`。Claude が「してよいか」と聞く前に `INDEX.md`、分類 1 本の頭、該当の 1 行の順に読む。行が無ければ、決まった手順で仮の 1 行を立てて進む。
4. skill `capture`。聞いて答えが出た場面を、後から行に起こす。答えが repo に残る。
5. 測る枠。シナリオの名簿 `_scenarios.md` と、それを実物の Claude Code に投げて索引が開かれたかを記録するコマンド。名簿には見本が入っている。

25h が自分たちの作業環境で使っている構造を、空の型にしたもの。25h の行は入っていない。埋めた中身は使う人のもの。

## やらないこと

入れる前に読んでほしい。

- Claude が聞くのを止めはしない。索引を引くことを強制する仕掛けは無い。skill は、Claude が関係があると判断した時に読み込む指示書である。
- 聞かれる回数がどれだけ変わるかは何も言わない。実物の Claude Code に通す検査 (`tests/live-check.sh`) は 2026-10-19 (Claude Code 2.1.303) と 2026-10-31 (Claude Code 2.1.314) に走らせた。測るのは索引が開かれるかで、聞く回数ではない。2026-10-31 の 3 回は、skill だけでは 3 つのシナリオのうち 1 回が 1 つ、2 回が 0 で開かれ、`CLAUDE.md` の 1 行を足すと 3 回とも 3 つ全部で開かれた。「確かめたこと」を参照。
- 権限の仕組みの代わりにはならない。決め手が `never` の行があっても、コマンドは止まらない。止めるには Claude Code の権限設定か hook を使う。
- 見本の行は、使う人の決定になっていない。全部が強度 C、つまり仮。直すか、昇格させるか、消す。
- 検査が見るのは形だけ。強度 A の行に確かめた反証が無いことは分かる。基準が正しいか、決め手の枝が全部の場合を覆っているかは分からない。
- 行を書かなければ索引は厚くならない。会話の中で答えが出ても、行に起こさなければ何も残らない。

## CLAUDE.md・rules との住み分け

2026-10-09 に公式の文書で確かめた。

| 置き場 | context に載る時 | 置くもの |
|---|---|---|
| `CLAUDE.md` | 毎セッション | 事実と「いつも X する」の 1 行。公式は 1 ファイル 200 行未満を目安にし、複数の手順は skill か paths つきの rule へ移すよう書いている |
| `.claude/rules/` | 毎セッション、または該当ファイルを開いた時 (`paths:`) | 常に効く制約、コードの一部にだけ効く制約 |
| skill | 説明文は毎セッション一覧に載る。本文は呼ばれた時 | 手順。ここでは場面の引き方と行の立て方 |
| 索引 (`judgment/`) | Claude が読んだ分だけ。`INDEX.md`、頭 1 つ、行 1 本 | 基準そのもの。1 場面 1 行 |

この plugin に効いてくる点が 3 つある。

- plugin は常時載る指示を足せない。plugin の直下に置いた `CLAUDE.md` は読み込まれない。毎セッション索引へ向かわせる 1 行は、使う人が自分の `CLAUDE.md` に足す。文面は `init` が出す。
- plugin の skill は `skills/<名前>/SKILL.md` に置き、名前は plugin 名つきになる。2 つの skill は `/judgment-index:consult` と `/judgment-index:capture`。
- skill を多く入れていると、Claude Code は一覧の文字数の枠に収めるために説明文を落とす。落ちる順は呼ばれた回数の少ない順。説明文が落ちると、Claude はその skill をいつ使うかを知らない。`CLAUDE.md` の 1 行はこの枠に左右されない。

`CLAUDE.md` や常時の rule に既に書いてある基準は、索引に写さない。強度 P の行で指す。指し先が無い時と、指し先が `paths:` つきの rule である時は、検査が落とす。

出どころ:

- Plugins: https://code.claude.com/docs/en/plugins
- Plugins reference (構成、`${CLAUDE_PLUGIN_ROOT}`、plugin 直下の `CLAUDE.md` の扱い): https://code.claude.com/docs/en/plugins-reference
- Skills (plugin の skill の置き場と名前、frontmatter、一覧の枠): https://code.claude.com/docs/en/skills
- Memory (`CLAUDE.md` と `.claude/rules/` がいつ載るか): https://code.claude.com/docs/en/memory

## 要る物

- Claude Code。確かめた版は 2.1.314。
- 道具に Python 3.8 以上。パッケージは入れない。確かめた版は 3.9.6。
- `tests/` の shell script 2 本は macOS か Linux。道具そのものは shell に依らない。

## 入れ方

次の 2 つを順に実行する。Claude Code は GitHub の `noes-25h/agent-kit` から plugin を取ってくる。この repository の別の plugin を入れた時に 1 つ目を済ませていれば、2 つ目だけでよい。

```bash
claude plugin marketplace add noes-25h/agent-kit
```

```bash
claude plugin install judgment-index@25h-agent-kit
```

次のコマンドで `judgment-index@25h-agent-kit` が `enabled` と出れば入っている。

```bash
claude plugin list
```

開いたままの Claude Code には、開き直すか `/reload-plugins` で反映される。

## 索引を project に展開する

索引は repo の中のフォルダである。project の一番上で、この repository を clone した先 (`git clone https://github.com/noes-25h/agent-kit`) への path をつけて `init` を実行する。

```bash
python3 /path/to/agent-kit/plugins/judgment-index/scripts/judgment.py init
```

`judgment/` が出来て、`INDEX.md`、分類ファイル 15 本、`_scenarios.md`、`_inbox.md`、道具の写し `_judgment.py` が入る。既に在るファイルは上書きしない。道具の写しを入れるのは、plugin を持たない同僚や CI でも索引を検査できるようにするため。

別の場所に置くなら `--dir` を渡す。場所は project の一番上の `.judgment-index` という 1 行のファイルに記録され、skill と道具はそこから読む。

```bash
python3 /path/to/agent-kit/plugins/judgment-index/scripts/judgment.py init --dir docs/judgment
```

`init` は最後に `CLAUDE.md` 用の 1 行を出す。手で足す。`init` は `CLAUDE.md` を書き換えない。

```
Before you ask whether you may or should do something, look the scene up in `judgment/INDEX.md`: pick a category, read only the head of that category file, then read the one matching row. If no row matches, follow the steps in `judgment/INDEX.md` to add one row and continue.
```

そのあと `judgment/INDEX.md` を開き、"Where decisions live" の一覧を、自分の決定が記録されている場所に直す。

## 確かめ方

この節のコマンドは、この repository を clone した一番上のフォルダで打つ (`git clone https://github.com/noes-25h/agent-kit`)。

2 段ある。1 段目だけでは、索引が使われることは分からない。

道具の検査。正しい行と欠けた行を検査に流し、続けて空の project からコマンドを順に打つ。検査の検査が 68 個、手順が 13 個。Claude Code は呼ばず、数秒で終わる。

```bash
bash ./plugins/judgment-index/tests/selftest.sh
```

実物の Claude Code での検査。25h で走らせた (結果は「確かめたこと」)。見本の索引を空のフォルダに展開し、シナリオ 3 つを 3 通りで Claude Code に投げる。索引のファイルだけ、plugin あり、plugin と `CLAUDE.md` の 1 行あり、の 3 通り。呼び出しごとに道具の使用記録を読み、`INDEX.md` と分類ファイルが開かれたかを記録する。利用枠を 9 回分使う。

```bash
bash ./plugins/judgment-index/tests/live-check.sh
```

終了コード 0 は、plugin と `CLAUDE.md` の 1 行がある時に全部のシナリオで索引が開かれた。1 は開かれなかった。2 は判定できない。呼び出しが最後まで走らなかった時と、plugin が既に自分の環境に入っている時がこれに当たる。入っていると plugin なしの側が対照にならないので、検査の間だけ外す。plugin なしでも同じ回数だけ開かれた時と、`CLAUDE.md` の 1 行が要った時は、出力にそう書く。

自分の索引を自分のシナリオで測るには次のとおり。

```bash
python3 judgment/_judgment.py measure --plugin-dir /path/to/agent-kit/plugins/judgment-index --n 3
```

## 日々の使い方

行の形。

```markdown
### PB03 — a correction to a page that is already public

- **Rule**: Prepare the corrected text and the diff. Do not publish it.
- **Decider**: owner
- **Strength**: B
- **Source**: owner decision 2026-10-09 (n=1)
```

- Decider (決め手) は 5 語。`agent`、`agent (reversible only)`、`owner`、`hands` (決めるのは AI、人は手を 1 つ貸す)、`never` (承認があってもやらない)。場面が割れる時は枝で書く。例: `agent (local copy) / owner (anything live)`。
- Strength (強度) は A / B / C / P。A は `Counter` が必須で、確かめた内容と結果を `->` の後ろに書く。C は仮で、`Source` の代わりに `Derived from` でよい。P は毎セッション載っている指示への案内。

定義の全文と、行を立てる 7 つの手順は `judgment/INDEX.md` に在る。欄の名前は英語で固定してある。行の本文は何語で書いてもよい。本文を読む検査は「consider で終わる基準」の 1 つだけで、これは英語しか見ない。

行を書いたら、目次を作り直して検査する。

```bash
python3 judgment/_judgment.py toc
```

```bash
python3 judgment/_judgment.py check
```

目次は生成する。手では書かない。目次に載っていない行は取り出されない。行が無いより悪い。`check` が終了コード 1 を返すのは、目次が行とずれている時、行の形が崩れている時、`INDEX.md` と分類ファイルが食い違う時、名簿が存在しない分類や出口を指している時。pre-commit や CI に置ける。

skill。`consult` は Claude が聞く前に自分で呼ぶ。`/judgment-index:consult` と打っても呼べる。Claude に判断を聞かれたセッションの終わりに `/judgment-index:capture` を実行する。

数の読み方。`check` は強度ごとの行数を出す。C だけが増えて A と B が増えないなら、AI が 1 人で決めていて、誰も確かめていない。

## 調整

- 分類の名前を変える、外す。ファイル名、`INDEX.md` の表の行、`_scenarios.md` の分類の 3 か所を直す。3 つが揃うまで `check` が落ちる。
- 分類を足す。`NN_verb.md` を作り、目次の印の 2 行を他の分類から写す。`INDEX.md` に 1 行足す。ID の頭 2 文字は他と重ならないものにする。
- 道具の写しを新しくする。plugin を更新したら `judgment/_judgment.py` を消して `init` をもう一度実行する。他のファイルはそのまま残る。

## 外し方

```bash
claude plugin uninstall judgment-index@25h-agent-kit
```

```bash
claude plugin marketplace remove 25h-agent-kit
```

2 つ目は、更新元として覚えた repository の登録を消す。この repository の別の plugin を使い続ける時は、2 つ目は打たない。Claude Code の設定フォルダに plugin の写しが残る (`~/.claude/plugins/cache/25h-agent-kit/`)。もう読まれないので、手で消してよい。

repo の索引には触れない。索引は使う人のもので、中の `_judgment.py` は plugin が無くても動く。使うのをやめる時は `CLAUDE.md` の 1 行を消す。

## 確かめたこと

2026-10-09、どの repo にも属さない空のフォルダと、空の Claude Code 設定フォルダで、英語の README を上から順に打った。

- `claude plugin validate`、marketplace の追加、導入、一覧。`claude plugin details` は 2 つの skill を部品として表示し、常時載る分を 1 セッションあたり 300 トークン未満と見積もった (説明文 2 つ)。
- 空の project への `init`、`--dir` で別の場所への `init`、`check`
- 行を 1 本書く、`toc`、`check`。反証の無い強度 A の行が落ちること
- `tests/selftest.sh`。68 個と 13 個、全部が期待どおり
- 外す手順。外した後も project の索引は検査を通る

道具をわざと 18 か所、1 つずつ壊した。18 通り全部で selftest が落ちた。

2026-10-31、ログイン済みの Claude Code 2.1.314 で `tests/live-check.sh` を走らせ、終了コード 0 で終わった。plugin を読み込む 2 通りでは起動時に skill が載り、plugin なしでは載らなかった。

- 索引のファイルだけ: `INDEX.md` が開かれたのは 3 つのうち 0。
- plugin あり: 1 回は 3 つのうち 1、残りの 2 回は 3 つのうち 0。
- plugin と `CLAUDE.md` の 1 行あり: 3 つのうち 3。毎回、分類ファイルまで読んだ。

つまり `CLAUDE.md` の 1 行が要った。skill の説明文だけでは、セッションを索引まで連れて来るのに足りない。セッションが最後に自分で書いた行は、1 行ありでは 3 つとも期待した出口 (進む・聞く・断る) と合い、他の 2 通りでは 3 つのうち 2 つ。断るはずの場面で聞いた。この出口はセッションの自己申告で、実際にした事ではない。

確かめていないこと。実際の作業で聞く回数が減るか。これは 1 台の機械で、3 つのシナリオを 3 回走らせた結果。2026-10-19 の回 (Claude Code 2.1.303) も、1 行ありで 3 つとも開かれ、plugin だけでは 3 つのうち 0 だった。

## ライセンス

MIT。[LICENSE](LICENSE) を見る。
