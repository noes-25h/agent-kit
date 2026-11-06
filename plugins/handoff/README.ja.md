# handoff

English: [README.md](README.md)

Claude Code の plugin。中身は skill が 1 本。作業を残したままセッションが終わる時に使う。次のセッションはこの会話を何も持たずに始まるので、残った作業を、何も知らない所から実行できる形に Claude に直させる。

残った項目は 3 つの出口のどれかに送られる。

1. **指示書** — 完了をコマンドで確かめられ、途中で人の判断が要らないもの。ファイルとして書く。止める条件、手順、触ってよいパスとだめなパス、諦める条件が入る。
2. **単発のプロンプト** — 小さな 1 回の作業。返答の中に出るので、新しいセッションにそのまま貼れる。
3. **申し送り** — それ以外。最初の 1 文に、何が決まっていないかを書く。

指示書は必ず「Re-check at start」という節で始まる。指示書が前提にした事実と、それを確かめるコマンドの表。1 つでも崩れていたら、直し方をその場で作らず、止まって報告する、という指示になっている。

25h が自分たちの作業環境で使っている skill を、単体で動く形に直したもの。25h の台帳・パス・道具の名前は抜いてある。

## しないこと

入れる前に読んでほしい。

- これはプロンプトで、何も強制しない。Claude が節を落としても、plugin の側に止める仕組みは無い。
- 実物の Claude Code で確かめたのは 2026-10-19 (Claude Code 2.1.303)、2026-10-31 (2.1.314)、2026-11-01 (2.1.316)。新しい回は、要点 14 個のうち plugin ありで 14 個、なしで 8 個。下の「確かめ方」を参照。数は語の一致で、書いた指示書を新しいセッションが実行できるかは測っていない。
- 残った作業そのものはしない。次の実行も始めない。指示書を書き、始めるための 1 行を渡す所まで。
- セッションで何が起きたかの記録は作らない。日誌ではない。
- 次のセッションがうまくいくことを約束しない。指示書は、次のセッションが推測する量を減らす物。前提がまだ成り立つかは、実行した時に分かる。
- 呼ばれたセッションの会話を読む。新しいセッションで呼んでも、記録を指さない限り渡す物が無い。

## 要る物

- Claude Code。確かめた版は 2.1.316。
- 検査のスクリプト 2 本は macOS か Linux。bash・grep・sed・awk・jq を使う。skill の本体は Markdown 1 枚で、この条件は要らない。

## 入れ方

次の 2 つを順に実行する。Claude Code は GitHub の `noes-25h/agent-kit` から plugin を取ってくる。この repository の別の plugin を入れた時に 1 つ目を済ませていれば、2 つ目だけでよい。

```bash
claude plugin marketplace add noes-25h/agent-kit
```

```bash
claude plugin install handoff@25h-agent-kit
```

入ったかどうかは次で見られる。`handoff@25h-agent-kit` が `enabled` と出ていれば入っている。

```bash
claude plugin list
```

開いている Claude Code のセッションには、開き直すか `/reload-plugins` を打つと効く。全部のプロジェクトに効く。

入れずに 1 回だけ試したい時は、この repository を clone し (`git clone https://github.com/noes-25h/agent-kit`)、その一番上のフォルダで、起動の時にフォルダを指す。

```bash
claude --plugin-dir ./plugins/handoff
```

## 使い方

終わろうとしている Claude Code のセッションの中で打つ。

```
/handoff:handoff
```

plugin に入っている skill は `/<plugin の名前>:<skill の名前>` で呼ぶ。ここではどちらも `handoff` なので `/handoff:handoff` になる。公式の skills の頁によれば、同じ名前の別のコマンドが無ければ短い `/handoff` でも呼べる。

渡せるもの:

- 何を渡すかの説明。残っている物の一部だけを渡したい時に。
- `--plans-dir <dir>`。指示書の置き場。
- `--tasks-file <path>`。決まっていない項目の申し送りの置き場。

自分のメッセージが skill の説明に合う時 (次のセッションへの引き継ぎを頼んだ時など) は、Claude が自分で skill を読み込むこともある。打ったコマンドでだけ動かしたい時は、`plugins/handoff/skills/handoff/SKILL.md` の frontmatter に `disable-model-invocation: true` を足す。

**置き場。** 2 つの置き場それぞれを、skill は次の順で決める。引数。次に、プロジェクトの根の `.claude/handoff.json` (例: `{"plans_dir": "docs/handoff", "tasks_file": "TODO.md"}`)。どちらも無い時、指示書は `docs/handoff/` に置かれ、申し送りはファイルを作らず返答の中に書かれる。

**実行を始める。** skill は指示書ごとに `/goal` で始まる 1 行を出す。`/goal` は、条件が成り立つまでセッションを働かせ続ける Claude Code のコマンド (https://code.claude.com/docs/en/goal)。始めたい時に、新しいセッションへその行を貼る。skill は始めない。

**モデルと effort。** frontmatter は `model: inherit` と `effort: medium`。セッションで使っているモデルのまま動く。変えたい時はこの 2 行を書き換える。

## 確かめ方

この節のコマンドは、この repository を clone した一番上のフォルダで打つ (`git clone https://github.com/noes-25h/agent-kit`)。

確かめる段は 2 つある。1 つ目だけで分かることは少ない。

**ファイル** — manifest、skill の frontmatter、必要な節と文、2 つ目の検査が採点に使う見本、を見る。49 項目。Claude Code は呼ばない。数秒で終わる。

```bash
bash ./plugins/handoff/tests/selftest.sh
```

**実物の Claude Code** — 5 件中 2 件で止まった移行作業の小さな見本の repo を写す。判断が要る項目が 1 つ、小さな単発が 1 つ入っている。skill ありと、素の依頼の 2 回 Claude Code を走らせ、期待する要点 14 個のうち何個を、書かれたファイルと返答が満たしたかを数える。要点の一覧は `plugins/handoff/tests/fixtures/stopped-session/expected.tsv`。2 回分の利用枠を使う。

```bash
bash ./plugins/handoff/tests/live-check.sh
```

**25h が走らせた結果。** 新しい回は 2026-11-01 に Claude Code 2.1.316 で走らせた。要点 14 個のうち、plugin ありで 14 個、なしで 8 個。基準は 10。なしの数は比べるために出している。力のあるモデルは、skill が無くても要点をいくつか満たす。これは 1 台の機械での 1 回で、手元の結果は違いうる。

数字の意味。要点 1 つは語の一致で見ている。別の理由で触れただけの要点を数えることも、言い回しが違って落とすこともある。`expected.tsv` の基準 10 は読みで決めた値で、実走で合わせていない。1 回は 1 標本で、Claude は同じ返答を 2 度しない。もう 1 つ、この数は本当の問い (新しいセッションがその指示書を実行できるか) には答えない。それを見るには、スクリプトが残す作業フォルダで新しいセッションを開き、指示書を渡す。

## 調整

skill は 1 枚: `plugins/handoff/skills/handoff/SKILL.md`。自由に書き換えてよい。指示書のひな型はその中の「Step 3A」にある。

- 節の名前を変えたり消したりした時は (ひな型の節も含む)、`tests/selftest.sh` の上の方にある `REQUIRED_SECTIONS` も同じに直す。直さないと selftest が落ちる。節が気づかないうちに消えるのを防ぐための一覧。
- `REQUIRED_PHRASES` も同じ。前提が崩れたら止まる、という文のように、1 文で規則を担っている所の一覧。
- 自分のプロジェクトの状況で採点したい時は、`tests/fixtures/stopped-session/` の隣に `repo/` と `expected.tsv` を持つフォルダを足し、`tests/live-check.sh` の `FIX` をそこへ向ける。

変える時は、この repository を clone して中のファイルを直し、GitHub からでなく clone から入れる (clone の 1 つ上で `claude plugin marketplace add ./agent-kit`)。plugin は clone から直接読まれる。 GitHub から入れ済みなら、登録先 `25h-agent-kit` が clone に付け替わり、入れ済みの plugin も以後は clone から更新される。戻す時は `claude plugin marketplace add noes-25h/agent-kit` を打ち直す。変えた内容は、Claude Code を開き直すか `/reload-plugins` を打つと効く。変えた後は selftest を走らせる。

## 外し方

```bash
claude plugin uninstall handoff@25h-agent-kit
```

```bash
claude plugin marketplace remove 25h-agent-kit
```

2 つ目は、更新元として覚えた repository の登録を消す。この repository の別の plugin を使い続ける時は、2 つ目は打たない。

外した後、Claude Code の設定フォルダ (`~/.claude/plugins/cache/25h-agent-kit/`) に plugin の写しが残る。もう読まれない写しで、手で消してよい。`settings.json` には何も残らない。プロジェクトに出来た指示書・申し送り・`.claude/handoff.json` は利用者の物で、そのまま残る。

## 出どころ

plugin の構成、plugin の中の skill の呼び方、frontmatter の欄は、2026-10-09 に次の頁で確かめた。

- Plugins: https://code.claude.com/docs/en/plugins
- Skills (frontmatter の一覧、コマンド名の決まり方、置き換えられる文字列): https://code.claude.com/docs/en/skills
- Plugin manifest reference: https://code.claude.com/docs/en/plugins-reference
- `/goal`: https://code.claude.com/docs/en/goal
- 対話なしの実行 (live-check が使う): https://code.claude.com/docs/en/headless

## ライセンス

MIT。[LICENSE](LICENSE) を見る。
