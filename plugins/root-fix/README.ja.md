# root-fix

English: [README.md](README.md)

Claude Code の plugin。中身は skill が 1 本。同じミスが繰り返される時に使う。Claude に次の順で作業させる。

1. 報告された症状の元のファイルを開き、報告が事実かを確かめる。
2. 症状から、その値を書いた所、さらにそれを生成した所まで遡る。
3. 複数の症状を 1 点に絞る。生成器、ひな型、スクリプト、構造のどれか。
4. 同じ源が同じ欠陥を生んでいる他の場所を repo 全体から洗い、外した場所には理由を書く。
5. `--apply` を付けた時だけ、源を直し、欠陥が戻ったら落ちる検査を 1 つ足す。

25h が自分たちの作業環境で使っている skill を、単体で動く形に直したもの。25h の台帳・パス・他の skill の名前は抜いてある。

## しないこと

入れる前に読んでほしい。

- これはプロンプトで、何も強制しない。Claude が段を飛ばしても、plugin の側に止める仕組みは無い。
- 実物の Claude Code で確かめたのは 2026-10-19 (Claude Code 2.1.303)、2026-10-31 (2.1.314)、2026-11-01 (2.1.316)。新しい回は、要点 11 個のうち plugin ありで 11 個、なしで 8 個。下の「確かめ方」を参照。数は語の一致で、考えの筋の良し悪しは見ていない。
- ミスを自分では見つけない。繰り返しに気づくのは利用者か、linter か、レビュー。skill はそこから始まる。
- ミスが止まることを約束しない。源での修正と検査を Claude に求め、検査が何を見ているかを報告させる。
- 原因が分かっている 1 回きりの bug には向かない。skill 自身がそう書いていて、その場合は直接直すよう Claude に伝える。
- `--apply` が無い時はファイルを変えないよう指示してある。これは Claude への指示で、権限の設定ではない。強制したい時は Claude Code の権限設定を使う。

## 要る物

- Claude Code。確かめた版は 2.1.316。
- 検査のスクリプト 2 本は macOS か Linux。bash・grep・sed・awk・jq を使う。skill の本体は Markdown 1 枚で、この条件は要らない。

## 入れ方

次の 2 つを順に実行する。Claude Code は GitHub の `noes-25h/agent-kit` から plugin を取ってくる。この repository の別の plugin を入れた時に 1 つ目を済ませていれば、2 つ目だけでよい。

```bash
claude plugin marketplace add noes-25h/agent-kit
```

```bash
claude plugin install root-fix@25h-agent-kit
```

入ったかどうかは次で見られる。`root-fix@25h-agent-kit` が `enabled` と出ていれば入っている。

```bash
claude plugin list
```

開いている Claude Code のセッションには、開き直すか `/reload-plugins` を打つと効く。全部のプロジェクトに効く。

入れずに 1 回だけ試したい時は、この repository を clone し (`git clone https://github.com/noes-25h/agent-kit`)、その一番上のフォルダで、起動の時にフォルダを指す。

```bash
claude --plugin-dir ./plugins/root-fix
```

## 使い方

Claude Code のセッションの中で打つ。

```
/root-fix:root-fix 夜間のレポートがまた違う時間帯で走った
```

plugin に入っている skill は `/<plugin の名前>:<skill の名前>` で呼ぶ。ここではどちらも `root-fix` なので `/root-fix:root-fix` になる。公式の skills の頁によれば、同じ名前の別のコマンドが無ければ短い `/root-fix` でも呼べる。

渡せるもの:

- 症状の説明、`file:line`、または障害の記録のパス。
- `--apply`。診断で止めず、ファイルの編集まで進める。
- `--record <path>`。源を 1 件で残す記録の置き場。

自分のメッセージが skill の説明に合う時 (同じミスがまた起きた、と書いた時など) は、Claude が自分で skill を読み込むこともある。打ったコマンドでだけ動かしたい時は、`plugins/root-fix/skills/root-fix/SKILL.md` の frontmatter に `disable-model-invocation: true` を足す。

**記録の置き場。** skill は次の順で決める。引数の `--record`。次に、プロジェクトの根の `.claude/root-fix.json` の `record` (例: `{"record": "docs/root-causes.md"}`)。どちらも無ければファイルを作らず、記録は返答の中に書く。

**モデルと effort。** frontmatter は `model: inherit` と `effort: high`。セッションで使っているモデルのまま動く。変えたい時はこの 2 行を書き換える。

## 確かめ方

この節のコマンドは、この repository を clone した一番上のフォルダで打つ (`git clone https://github.com/noes-25h/agent-kit`)。

確かめる段は 2 つある。1 つ目だけで分かることは少ない。

**ファイル** — manifest、skill の frontmatter、必要な節と文、2 つ目の検査が採点に使う見本、を見る。42 項目。Claude Code は呼ばない。数秒で終わる。

```bash
bash ./plugins/root-fix/tests/selftest.sh
```

**実物の Claude Code** — 同じミスが 3 回記録されている小さな見本の repo を写し、skill ありと、素の依頼の 2 回 Claude Code を走らせ、期待する要点 11 個のうち何個を返答が満たしたかを数える。要点の一覧は `plugins/root-fix/tests/fixtures/three-repeats/expected.tsv`。2 回分の利用枠を使う。

```bash
bash ./plugins/root-fix/tests/live-check.sh
```

**25h が走らせた結果。** 新しい回は 2026-11-01 に Claude Code 2.1.316 で走らせた。要点 11 個のうち、plugin ありで 11 個、なしで 8 個。基準は 8 で、この回は基準では plugin の有無を分けられない。差は 11 と 8 の 3 点。2026-10-19 の回は、ありで 10 個、なしで 6 個だった。なしの数は比べるために出している。力のあるモデルは、skill が無くても要点をいくつか満たす。これは 1 台の機械での 1 回で、手元の結果は違いうる。

数字の意味。要点 1 つは語の一致で見ている。別の理由で触れただけの要点を数えることも、言い回しが違って落とすこともある。`expected.tsv` の基準 8 は読みで決めた値で、実走で合わせていない。1 回は 1 標本で、Claude は同じ返答を 2 度しない。スクリプトが作業フォルダに残す返答を自分で読むこと。

## 調整

skill は 1 枚: `plugins/root-fix/skills/root-fix/SKILL.md`。自由に書き換えてよい。

- 節の名前を変えたり消したりした時は、`tests/selftest.sh` の上の方にある `REQUIRED_SECTIONS` も同じに直す。直さないと selftest が落ちる。段が気づかないうちに消えるのを防ぐための一覧。
- `REQUIRED_PHRASES` も同じ。`--apply` が無い時に編集を禁じる文のように、1 文で規則を担っている所の一覧。
- 自分のプロジェクトの状況で採点したい時は、`tests/fixtures/three-repeats/` の隣に `repo/` と `expected.tsv` を持つフォルダを足し、`tests/live-check.sh` の `FIX` をそこへ向ける。

変える時は、この repository を clone して中のファイルを直し、GitHub からでなく clone から入れる (clone の 1 つ上で `claude plugin marketplace add ./agent-kit`)。plugin は clone から直接読まれる。 GitHub から入れ済みなら、登録先 `25h-agent-kit` が clone に付け替わり、入れ済みの plugin も以後は clone から更新される。戻す時は `claude plugin marketplace add noes-25h/agent-kit` を打ち直す。変えた内容は、Claude Code を開き直すか `/reload-plugins` を打つと効く。変えた後は selftest を走らせる。

## 外し方

```bash
claude plugin uninstall root-fix@25h-agent-kit
```

```bash
claude plugin marketplace remove 25h-agent-kit
```

2 つ目は、更新元として覚えた repository の登録を消す。この repository の別の plugin を使い続ける時は、2 つ目は打たない。

外した後、Claude Code の設定フォルダ (`~/.claude/plugins/cache/25h-agent-kit/`) に plugin の写しが残る。もう読まれない写しで、手で消してよい。`settings.json` には何も残らない。プロジェクトに作った `.claude/root-fix.json` と記録のファイルは利用者の物で、そのまま残る。

## 出どころ

plugin の構成、plugin の中の skill の呼び方、frontmatter の欄は、2026-10-09 に次の頁で確かめた。

- Plugins: https://code.claude.com/docs/en/plugins
- Skills (frontmatter の一覧、コマンド名の決まり方、置き換えられる文字列): https://code.claude.com/docs/en/skills
- Plugin manifest reference: https://code.claude.com/docs/en/plugins-reference
- 対話なしの実行 (live-check が使う): https://code.claude.com/docs/en/headless

## ライセンス

MIT。[LICENSE](LICENSE) を見る。
