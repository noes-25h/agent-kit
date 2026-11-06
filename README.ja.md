# 25h Agent Kit

API キーの漏れ、誰も読んでいない計画、文脈の無い次のセッション、Claude が日付を推測する失敗。繰り返す失敗に 1 つずつ備える、Claude Code の小さな plugin 8 本です。

ほとんどは助言で、止めるのは secret-guard と install-gate の 2 本だけです。各 plugin の説明に、守らない所を書いています。

English: [README.md](README.md)

作ったのは、一人の人間と AI で営む小さな事業 25h です。ここの hook と skill は、私たちが毎日の仕事で使っている物を、単体で動く形に直した版です。MIT ライセンスです。

## 8 本

| plugin | 効く場面 | 種類 |
|---|---|---|
| [secret-guard](plugins/secret-guard/README.ja.md) | 鍵が道具の呼び出しに入りそう、またはコマンドの出力に出てきた | hook |
| [install-gate](plugins/install-gate/README.ja.md) | 監査の記録なしに、Claude がマシン全体へ道具を入れようとしている | hook と skill |
| [time-guard](plugins/time-guard/README.ja.md) | Claude が今の時刻を知らない、日付なしで「今朝」と書く | hook と skill |
| [session-memory](plugins/session-memory/README.ja.md) | 新しいセッションが、作業の現在地を知らずに始まる | hook と skill |
| [handoff](plugins/handoff/README.ja.md) | 作業が残ったままセッションを閉じ、次のセッションは文脈を持たない | skill |
| [plan-review](plugins/plan-review/README.ja.md) | 計画はできたが、文脈を持たない目がまだ読んでいない | skill とサブエージェント |
| [root-fix](plugins/root-fix/README.ja.md) | 同じミスが繰り返される | skill |
| [judgment-index](plugins/judgment-index/README.ja.md) | 答えたことのある問いを Claude がまた聞いてくる | skill とスクリプト |

要る物だけ入れてください。1 本ずつ独立して動きます。

## 入れ方

Claude Code の中では、同じ 2 行を `claude plugin` の代わりに `/plugin` で始めます。

```bash
claude plugin marketplace add noes-25h/agent-kit
```

続けて、要る物を入れます。`secret-guard` を入れたい plugin の名前に替えてください。

```bash
claude plugin install secret-guard@25h-agent-kit
```

## 確かめ方

各 plugin の `tests/` に、2 段の検査があります。

- `selftest.sh` はファイルとスクリプトを確かめます。Claude Code は呼びません。
- `live-check.sh` は実物の Claude Code を走らせ、起きたことを読みます。利用枠を使います。

2 段目を置いた理由は、ここの hook の 1 本の元の版が、自分の検査に通ったまま 3 か月半、何もしていなかったからです。hook の返す値の形が少し違うと、Claude Code はエラーを出さずに捨てます。

8 本とも `live-check.sh` が終了コード 0 で終わりました (2026-10-31 に Claude Code 2.1.314 で install-gate・time-guard・plan-review・session-memory・judgment-index、2026-11-01 に Claude Code 2.1.316 で root-fix・handoff、2026-11-02 に Claude Code 2.1.316 で secret-guard)。plan-review は同じ日の 2 回目です。1 回目は検査が起動の知らせだけを読んで終了コード 1 になり、検査を直してから通しました。何が分かるかは plugin ごとに違い、各 README の「確かめ方」に測った物を書いています。たとえば judgment-index は、`CLAUDE.md` の 1 行がある時にだけ、全部の場面で索引が開かれました。1 台の機械での少ない回数です。手元でも走らせ、Claude Code を更新したらまた走らせてください。

## 問い合わせ

Issue を開いてください。このまま共有している物で、返答や直す日の約束はしません。

## ライセンス

MIT。[LICENSE](LICENSE) を見てください。
