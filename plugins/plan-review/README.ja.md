# plan-review

English: [README.md](README.md)

Claude Code の plugin。出来上がった計画を、その計画を作った会話に居なかったレビュー役 2 体に読ませる。そのあと、計画を書いたセッションに、指摘の 1 件ずつへ文字で答えさせる。

1. skill が 1 本。`/plan-review:plan-review`。レビュー役 2 体を同時に起動し、指摘ごとに裁き (採用・反論・後回し・人に上げる) を付け、計画ファイルの末尾に書き足す。
2. レビュー役の定義が 2 本。`plan-review:adversarial-reviewer` は、この計画を通してはいけない理由を探す。`plan-review:best-path-reviewer` は、この計画の上に立って、もっと良い結論を探す。

25h が自分たちの計画に使っているレビューから、25h のファイルを指す部分を抜いたもの。

## やらないこと

入れる前に読んでほしい。

- **実物の Claude Code に通す検査は、3 回通っただけ。** 25h で `tests/live-check.sh` を 2026-10-19 に Claude Code 2.1.303 で、2026-10-20 に 2.1.304 で、2026-10-31 に 2.1.314 で走らせた。どの回も、2 体とも plugin の名前で同じメッセージの中から起動し、model と effort を上書きした起動は 0。2 体とも埋めた欠陥 3 つをすべて名指し、計画ファイルに 2 つの節が足された。10/19 の通った回の前の 1 回は 3 つ中 0 と数えた。検査が報告の本体でなく 350 バイトの札を読んでいたためで、検査を直してから通した。名指したかは語の一致で数えているので、報告は自分で読んでほしい。3 回は 3 標本。2026-10-31 の先の 1 回は終了コード 1 で、3 つ中 0 と数えた。レビュー役が背景で走り、検査が 1,122 バイトの起動の知らせだけを読んでいたため。検査を直してから通した。
- 中身はプロンプト。レビューの質を保証する仕掛けは無い。レビュー役は欠陥を見落とすことがあり、無い欠陥を報告することもある。skill が「裁く前に指摘を実物に当てて確かめる」と書いているのはそのため。
- 「この計画をレビューして」と 1 回頼むだけの場合より多く見つかる、ということは示していない。同梱の見本の計画が測るのは、配線が通って、埋めた欠陥 3 つを名指す報告が返るかどうか。比較ではない。
- レビュー役は Bash を使える。道具の一覧から Write・Edit・NotebookEdit・Agent は外してあるが、Bash を読み取り専用にする手段は道具の一覧に無い。書き込まないように頼んでいるのはプロンプトの 1 行だけ。Bash を外す方法は「調整」に書いた。
- 定義に書いた model と effort は既定値で、鍵ではない。別の値が勝つ場合は「公式ドキュメントで確かめたこと」に書いた。
- レビュー役には、実行したフォルダのプロジェクト指示 (CLAUDE.md) が渡る。ほかのサブエージェントと同じ。会話は渡らない。
- 利用枠を使う。1 回のレビューで、effort high のサブエージェントが 2 体 (Sonnet と Opus) 走り、それぞれが計画と指した資料を読む。

## 要る物

- Claude Code。確かめた版は 2.1.314。
- Sonnet と Opus の両方を使えるアカウント。片方が使えない時は Claude Code が別のモデルに置き換えるので、2 体が同じモデルになることがある。
- 2 つの検査にだけ: bash・jq・grep・sed・awk。macOS か Linux。plugin 本体にスクリプトは無く、Claude Code が動く所なら動く。

## 入れ方

次の 2 つを順に実行する。Claude Code は GitHub の `noes-25h/agent-kit` から plugin を取ってくる。この repository の別の plugin を入れた時に 1 つ目を済ませていれば、2 つ目だけでよい。

```bash
claude plugin marketplace add noes-25h/agent-kit
```

```bash
claude plugin install plan-review@25h-agent-kit
```

入ったかどうかは次で見られる。`plan-review@25h-agent-kit` が `enabled` と出ていれば入っている。

```bash
claude plugin list
```

開いている Claude Code のセッションには、開き直すか `/reload-plugins` を打つと効く。全部のプロジェクトに効く。

入れずに 1 回だけ試したい時は、この repository を clone し (`git clone https://github.com/noes-25h/agent-kit`)、その一番上のフォルダで、起動の時にフォルダを指す。

```bash
claude --plugin-dir ./plugins/plan-review
```

## 確かめ方

この節のコマンドは、この repository を clone した一番上のフォルダで打つ (`git clone https://github.com/noes-25h/agent-kit`)。

確かめる段は 2 つある。1 つ目だけでは足りない。

**ファイルの形** — manifest・skill・定義 2 本・見本の計画を読んで、114 項目を検査する。frontmatter が Claude Code の読める形か。必須の節が在るか。skill がレビュー役を起動する時の名前が、定義と一致するか。2 つ目の段の集計を、手で書いたセッションの記録に当てることもする。Claude Code は呼ばない。数秒で終わる。

```bash
bash ./plugins/plan-review/tests/selftest.sh
```

**実物のレビュー** — 欠陥を 3 つ埋めた見本の計画を空のフォルダに写し、plugin を付けた Claude Code を 1 回走らせて、セッションの記録を読む。2 体が plugin の名前つきで起動されたか。3 つの欠陥のうち何個を、それぞれの報告が名指したか。計画ファイルに 2 つの節が書き足されたか。数分かかり、セッション 1 回とレビュー役 2 体ぶんの利用枠を使う。

```bash
bash ./plugins/plan-review/tests/live-check.sh
```

2 つ目が要る理由。この plugin は、ファイルが全部正しい形のまま、レビューが何もしていない状態になり得る。1 つ目の検査が確かめるのは、ファイルの中の名前が互いに、そして公式の説明と合っていることまで。セッションがその名前でレビュー役を起動するか、レビュー役が何を返すかは見えない。

2 つ目の読み方:

- 欠陥の数は、語を数えたもの。報告の 1 行に、欠陥の対象を指す語と「おかしい」を指す語の両方が在れば「名指した」と数える。数字に頼る前に、作業フォルダに残る報告を自分で読んでほしい。
- 1 回の実行は 1 つの標本。同じモデルが、ある回は欠陥を見落とし、次の回は名指すことがある。
- 3 つの欠陥は `tests/fixtures/flaws.tsv` に書いてある。レビュー役にこのファイルは渡らない。

## 使い方

計画を 1 つのファイルに書く。そのあと、書いたセッションの中で:

```
/plan-review:plan-review path/to/plan.md
```

「plan-review でこの計画をレビューして」と言葉で頼んでもよい。計画が合っていなければならない資料 (プロジェクトの指示・過去の決定・実装の現物・公式ドキュメント) を名指す。

## 何が起きるか

1. レビュー役 2 体が、同じメッセージの中で起動される。渡るのは、計画ファイルのパスと資料のパスだけ。計画がどう出来たかは渡らない。
2. それぞれが 600 語以内の要約を返す。通してはいけない理由を探す役は、指摘ごとに重さ (fail・fix・note)、代案、そして「この指摘が外れる条件」を付ける。もっと良い結論を探す役は、提案ごとに見込みの効果と外れる条件を付け、最後に自分ならどう組むかを書く。
3. セッションが指摘の 1 件ずつを裁く。採用する (adopt)。理由を付けて反論する (rebut)。記録して後に回す (defer)。閉じた問い 1 つにして人に上げる (escalate)。
4. 計画ファイルの末尾に 2 つの節が書き足される。指摘 1 件が表の 1 行。

```
## Adversarial review (2026-10-09, adversarial-reviewer, ran on <model> / effort <effort>)
## Best-path review (2026-10-09, best-path-reviewer, ran on <model> / effort <effort>)
```

この 2 節が無い計画ファイルは、レビューを通っていない。ファイルに書き足すのはそのため。後から検索で確かめられる。

## 調整

- **model と effort** — `plugins/plan-review/agents/*.md` の frontmatter の `model` と `effort` を変える。2 体のモデルを分けてあるのはわざと。モデルが違えば見落とす所も違う、という見込みによる。この plugin はそれを測っていない。
- **見る観点** — 各定義の "What to look for" の番号つきの一覧を変える。繰り返し起きている失敗に合う観点を足す。
- **報告の長さ** — 各定義の "at most 600 words" を変える。
- **読み取り専用にする** — 各定義の `tools` から `Bash` を消す。レビュー役は行数を数えたり、コマンドが在るかを確かめたりできなくなる。
- **ネットワークを閉じる** — レビュー役は `WebFetch` と `Bash` で外に出られるので、計画の文面が手元の外へ出うる。閉じるには 2 つとも消す。
- **CLAUDE.md を読ませない** — 各定義の frontmatter に `omitClaudeMd: true` を足す (Claude Code 2.1.271 以降)。

model か effort を変えた時は、`tests/selftest.sh` の冒頭近くにある控え (`PR_EXPECT_MODEL_...` と `PR_EXPECT_EFFORT`) も同じに直す。直さないと selftest が落ちる。定義が気づかないうちに変わるのを防ぐための控え。

変える時は、この repository を clone して中のファイルを直し、GitHub からでなく clone から入れる (clone の 1 つ上で `claude plugin marketplace add ./agent-kit`)。plugin は clone から直接読まれる。 GitHub から入れ済みなら、登録先 `25h-agent-kit` が clone に付け替わり、入れ済みの plugin も以後は clone から更新される。戻す時は `claude plugin marketplace add noes-25h/agent-kit` を打ち直す。変えた内容は、Claude Code を開き直すか、セッションの中で `/reload-plugins` を打つと効く。変えた後は selftest を走らせる。

## 外し方

```bash
claude plugin uninstall plan-review@25h-agent-kit
```

```bash
claude plugin marketplace remove 25h-agent-kit
```

2 つ目は、更新元として覚えた repository の登録を消す。この repository の別の plugin を使い続ける時は、2 つ目は打たない。

外した後、Claude Code の設定フォルダ (`~/.claude/plugins/cache/25h-agent-kit/`) に plugin の写しが残る。もう読まれない写しで、手で消してよい。計画ファイルに書き足されたレビューの節は、そのまま残る。

## 公式ドキュメントで確かめたこと

2026-10-09 に読んだ。下の各文は、頁の本文に当てて確かめた。

- **plugin に入れた agent の呼び方** — Claude Code は、plugin の部品すべてに plugin の名前を前置きする。plugin `plan-review` の agent `adversarial-reviewer` は `plan-review:adversarial-reviewer` になる。agent の名前に `:` は使えない。plugin の skill は `/plugin-name:skill-name`。出典: https://code.claude.com/docs/en/plugins-reference (`name` の欄)、https://code.claude.com/docs/en/sub-agents ("Supported frontmatter fields"・"Invoke subagents explicitly")、https://code.claude.com/docs/en/skills ("How a skill gets its command name")。
- **定義で model と effort を固定できるか** — サブエージェントの定義は `model` と `effort` を受け付ける。plugin のサブエージェントで無視されるのは `hooks`・`mcpServers`・`permissionMode`・`initialPrompt`。`model`・`effort`・`tools`・`disallowedTools` はその一覧に無い。出典: https://code.claude.com/docs/en/sub-agents ("Choose the subagent scope"・"Supported frontmatter fields")。
- **定義が勝たない場合** — model は、呼び出しで渡した `model` が先で、定義はその次。`CLAUDE_CODE_SUBAGENT_MODEL_FORCE` を設定していると定義は無視される。`opus` のような別名は、主の会話のモデルが同じ系列の時、主の会話のモデルそのものになる。組織の許可リストが別のモデルに置き換えることがある。effort は、呼び出しで渡した `effort` が定義に勝ち (Claude Code 2.1.292 以降)、環境変数 `CLAUDE_CODE_EFFORT_LEVEL` はその両方に勝つ。skill が「どちらも渡さない」「実際に走った値を書き残す」と指示しているのはこのため。出典: https://code.claude.com/docs/en/sub-agents ("Choose a model"・"Choose an effort level")。
- **レビュー役がさらにサブエージェントを起動するのを止める書き方** — 既定では、サブエージェントは主の会話の 3 層下までサブエージェントを起動できる。1 体だけ止めるには、その `tools` に `Agent` を入れないか、`disallowedTools` に `Agent` を足す。定義 2 本は両方をしている。出典: https://code.claude.com/docs/en/sub-agents ("Let subagents spawn their own subagents")。
- **実際に走った値の見方** — `/tasks` は、サブエージェントごとの行にモデルを出し、effort が設定されていればそれも出す (Claude Code 2.1.242 以降)。記録は `~/.claude/projects/{project}/{sessionId}/subagents/` に残る。出典: https://code.claude.com/docs/en/sub-agents 。
- **plugin の置き方** — plugin の直下の `agents/` と `skills/<name>/SKILL.md` は、`plugin.json` に書かなくても見つけられる。出典: https://code.claude.com/docs/en/plugins と https://code.claude.com/docs/en/plugins-reference 。

説明書に書いてあることと、セッションが実際にすることは別。後の方を確かめるのが `tests/live-check.sh` で、通った回は 2026-10-19 (2.1.303)、2026-10-20 (2.1.304)、2026-10-31 (2.1.314) に 1 回ずつ。その前に、10/19 に最後まで届かなかった回が 2 回ある。0 of 3 だった回 (10/19 と 10/31) は「やらないこと」に書いた。

## ライセンス

MIT。[LICENSE](LICENSE) を見る。
