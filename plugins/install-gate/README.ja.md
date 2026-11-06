# install-gate

English: [README.md](README.md)

Claude Code の plugin。Claude が機械の全体に入る道具を入れようとした時に、プロジェクトに在るその道具の audit の記録を見て、3 つのどれかにする。

| 記録の状態 | 起きること |
|---|---|
| 記録が無い・名前が一致しない・危険度の行が埋まっていない | 導入を止める。Claude には、同梱の skill で記録を書くよう伝わる |
| 記録が `Risk: LOW` | 導入が走る。何も出ない |
| 記録が `Risk: MID` か `Risk: HIGH` | 記録の場所と危険度を載せた確認が、あなたに出る |
| 導入のコマンドだが、何を入れるかを門が読めない (「コマンドの読み方」の節) | その旨を書いた確認が、あなたに出る |

同梱の skill `/install-gate:tool-audit` は、8 項目 (出どころ・ライセンス・鍵の置き場・規約・戻せるか など) を調べて記録を書く。

25h が自分たちの作業環境で使っている hook と skill を作り直したもの。

導入のコマンドに確認を付ける権限設定 (ask の rule) と何が違うか。記録がリポジトリに残る。同じ道具を次に入れる時、LOW の記録が在れば確認なしで通り、なぜ受け入れたかを誰でも読める。

## やらないこと

入れる前に読んでほしい。

- audit をしたことの証明にはならない。記録は Claude 自身が書ける。LOW と書かれた記録は確認なしで通る。門が見るのは 2 つだけ。ファイル名が道具の名前と厳密に一致すること、危険度の行がちょうど 1 つ在ること。全部の導入を自分に上げたい時は `ASK_ON_LOW = True` にする (「調整」の節)。
- 事故を防ぐ柵で、意図した迂回を止める壁ではない。次は見えない。
  - 別の言語の処理系を通した導入 (`python3 -c "..."`、`node -e "..."`) と、スクリプトファイルの中の導入 (`bash ./setup.sh`)
  - 管理ツールの名前が語として書かれていない形。変数に入れる (`$B install wget`)、引用符で割る (`br''ew`)、alias やシェルの関数を通す
  - 門が知らないプログラムに、引用符で囲んで渡したコマンド (`watch 'brew install wget'`)
- 見るのは機械の全体に入る導入だけ。次は見ない。
  - プロジェクトの依存 (`-g` の無い `npm install <名前>`、`--user` の無い `pip install`、requirements ファイルからの導入、`--system` の無い `uv pip install`、`uv sync`)
  - 1 回きりの実行 (`npx`、`uvx`)
  - ダウンロードしたスクリプトをそのままシェルへ流す形
  - コンテナの取得、`go install`、OS のパッケージ管理 (apt・dnf など)
  - 手元のパス (`brew install ./formula.rb`、`cargo install --path .`)
- 記録はプロジェクトごと。あるリポジトリで audit 済みの道具も、別のリポジトリでは、そこに記録が出来るまで止まる。

## 見るもの

| 管理ツール | 条件 | 記録と一致させる名前 |
|---|---|---|
| brew | `install`・`reinstall` | tap を含む名前の全部 (`user/tap/name`) |
| npm・pnpm・bun | `-g` か `--global` の付いた `install` / `i` / `add` | scope を含む名前の全部。末尾の版は外す |
| yarn | `global add` | npm と同じ |
| pipx | `install` | 版の指定を外した名前 |
| uv | `tool install`。`--system` か `--break-system-packages` の付いた `pip install`、または `sudo` の下の `pip install` | pipx と同じ |
| pip | `--user` か `--break-system-packages` の付いた `install`、または `sudo` の下 | pipx と同じ |
| cargo | `install` (`--path` つきは除く) | 版を外した crate の名前 |
| gem | `install` | gem の名前 |
| claude | `mcp add`・`mcp add-json`・`plugin install` | MCP はサーバーの名前。plugin は `名前@marketplace` の全部 |

名前からファイル名を作るには、小文字にして `/`・`@`・`:` を `-` に直し、末尾に `-audit.md` を付ける。

| 導入のコマンド | 記録 |
|---|---|
| `brew install jq` | `docs/tool-audits/jq-audit.md` |
| `brew install user/tap/jq` | `docs/tool-audits/user-tap-jq-audit.md` |
| `npm install -g @scope/pkg` | `docs/tool-audits/scope-pkg-audit.md` |
| `claude plugin install name@market` | `docs/tool-audits/name-market-audit.md` |

先頭に日付を付けてよい (`2026-01-02_jq-audit.md`)。tap・scope・marketplace が違えば別の道具で、別の記録が要る。

## コマンドの読み方

門は、コマンドをシェルと同じやり方で語に分け、中のコマンドを 1 つずつ見る。導入の言い回しを文字列として探してはいない。引用符の中の文で、表示するだけ・保存するだけのものは導入として扱わない。

次の場所に在る導入は、単独で打った時と同じに扱う (記録に応じて、止める・通す・確認)。

- `;`・`&&`・`||`・`|` の後ろ、次の行、行の継続 (行末の `\`) をまたぐ形
- `( ... )`・`{ ...; }`・`if` / `then` / `else`・`for` / `while ... do` の中、`!` の後ろ
- `$( ... )` とバッククォートの中。二重引用符の中に在る時も読む
- `sudo`・`doas`・`env`・`command`・`exec`・`time`・`nice`・`nohup`・`timeout`・`arch`・`caffeinate`・`stdbuf`・変数の代入 の後ろ
- シェルに渡す文 (`sh -c "..."`、`bash <<< "..."`、シェルに流す heredoc)、`eval` に渡す文、`ssh ホスト ...` の先。別の機械への導入も、このプロジェクトの記録で引く

導入だと分かるが読み切れない時は、確認を出す。黙って通すことも、止めることもしない。

- 名前がコマンドに書かれていない。変数や置換から来る (`brew install $PKG`、`brew install $(cat tools.txt)`)、標準入力から来る (`... | xargs brew install`)。
- 門が知らないプログラムの後ろに導入が在る (`watch -n 5 brew install wget`)。シェルへパイプで流す文に導入が在る (`echo "brew install wget" | sh`)。そこに出てくる道具の全部に LOW の記録が在れば通る。
- コマンドを語に分けられず (引用符が閉じていない等)、管理ツールの名前と導入の語が在る。

## 要る物

- Claude Code。確かめた版は 2.1.314。
- macOS か Linux。bash と python3 (3.9 で確かめた)。Windows は対象外。
- python3 が無い・動かない時、門は判定できない。その時は、管理ツールの名前が出てくるコマンドに確認を出す。黙って通すことはしない。
- 単体の検査には jq も使う。

## 入れ方

次の 2 つを順に実行する。Claude Code は GitHub の `noes-25h/agent-kit` から plugin を取ってくる。この repository の別の plugin を入れた時に 1 つ目を済ませていれば、2 つ目だけでよい。

```bash
claude plugin marketplace add noes-25h/agent-kit
```

```bash
claude plugin install install-gate@25h-agent-kit
```

入ったかどうかは次で見られる。`install-gate@25h-agent-kit` が `enabled` と出ていれば入っている。

```bash
claude plugin list
```

開いている Claude Code のセッションには、開き直すか `/reload-plugins` を打つと効く。全部のプロジェクトに効く。

門が掛かるのは Claude が実行するコマンドだけ。自分の端末で打つコマンドには掛からない。

## 確かめ方

この節のコマンドは、この repository を clone した一番上のフォルダで打つ (`git clone https://github.com/noes-25h/agent-kit`)。

確かめる段は 2 つある。1 つ目だけでは足りない。

**hook の中身** — コマンドを文字列として hook に渡し、判定を 1 つずつ確かめる。全部で 271 項目。何も導入しない。Claude Code は呼ばない。数秒で終わる。

```bash
bash ./plugins/install-gate/tests/selftest.sh
```

**実物の Claude Code** — Claude Code に、偽の `brew` (印のファイルを作るだけのスクリプト) を 3 回実行させ、印が出来たかを見る。本物は何も導入しない。数分かかり、3 回分の利用枠を使う。

```bash
bash ./plugins/install-gate/tests/live-check.sh
```

素の端末から走らせる。結果は 3 つに分かれる。終了コード 0 は、hook が動いて、導入は止まっている。1 は、hook が動いたのに、結果が違った。2 は判定できない。呼び出しが最後まで走らなかった時、plugin なしの側が比較にならない時、hook が動かなかった時がこれに当たる。

検査は、Claude Code が記録する hook の行を数えている。この plugin の hook が 1 回も最後まで動いていなければ、理由を 1 行で出し、判定は出さない。sandbox の中から走らせた時がこうなる。Claude Code のセッションの中から走らせた時もそう。Claude Code が plugin の置き場 `~/.claude/plugins/data/` を作れず、hook を起こさないまま道具を通す。その時の失敗の行には `EPERM` か `operation not permitted` と出る。素の端末を開いて走らせ直す。

1 つ目で分かるのは、スクリプトの判定が正しいことまで。Claude Code が実際に呼んでいるかは 2 つ目でしか分からない。

## 何が起きるか

**記録が無い時。** 導入は実行されない。Claude には次のような文が渡る。hook が出す文は英語。

```
install-gate: blocked this install. No usable audit record for: wget (brew; no record; expected docs/tool-audits/wget-audit.md). Run /install-gate:tool-audit <tool name> to research the tool and write the record. ...
```

**記録が MID か HIGH の時。** `[plugin:install-gate]` の印が付いた確認が出る。

```
install-gate: ripgrep is marked MID in docs/tool-audits/ripgrep-audit.md. Read the audit record before you approve.
```

**導入だが読み切れない時。** 次のどちらかの形の確認が出る。

```
install-gate: this command installs something (brew), but the names are not in the command text (a variable, a substitution or standard input). Check the command before you approve.
```

```
install-gate: this looks like an install of wget (brew) inside a command the gate cannot fully read, and there is no usable audit record for it. Check the command before you approve.
```

人の居ない実行 (`claude -p`) では確認に答える人が居ないので、導入は拒否になる。

**記録が LOW の時。** 導入が走る。何も出ない。

**導入でないコマンド。** 何も起きない。導入に触れているだけの文 (`echo`、コミットの文、heredoc で書いた文書) は導入として扱わない。

## audit の記録

記録は `docs/tool-audits/` に置く Markdown で、危険度の行をちょうど 1 つ持つ。

```
Risk: LOW
```

ほかの値は `Risk: MID` と `Risk: HIGH`。危険度の行が無い・2 つ以上在る・ひな型の行のまま、のファイルは記録として扱わない。

skill が記録を書く。

```
/install-gate:tool-audit ripgrep
```

skill はセッションのモデルをそのまま使い (`model: inherit`)、`effort: high` で動く。変える時は `plugins/install-gate/skills/tool-audit/SKILL.md` の frontmatter を直す。

## 調整

`plugins/install-gate/scripts/gate.py` の先頭に切り替えが 2 つ在る。

- `ASK_ON_LOW = True` にすると、LOW の記録でも確認が出る。門が見る導入が全部、自分に上がる。
- `GATE_ALL_PIP = True` にすると、仮想環境への導入を含めて `pip install <名前>` と `uv pip install <名前>` を全部見る。requirements ファイルと手元のパスは通る。

変える時は、この repository を clone して中のファイルを直し、GitHub からでなく clone から入れる (clone の 1 つ上で `claude plugin marketplace add ./agent-kit`)。plugin は clone から直接読まれる。 GitHub から入れ済みなら、登録先 `25h-agent-kit` が clone に付け替わり、入れ済みの plugin も以後は clone から更新される。戻す時は `claude plugin marketplace add noes-25h/agent-kit` を打ち直す。変えた内容は、Claude Code を開き直すか `/reload-plugins` を打つと効く。

selftest は切り替えが 2 つとも切の状態を前提にしている。切り替えを入れると、それで判定が変わる項目が落ちたと表示される (たとえば LOW の記録が `ask` になる)。それ以外は通ったままのはず。

## 外し方

```bash
claude plugin uninstall install-gate@25h-agent-kit
```

```bash
claude plugin marketplace remove 25h-agent-kit
```

2 つ目は、更新元として覚えた repository の登録を消す。この repository の別の plugin を使い続ける時は、2 つ目は打たない。Claude Code の設定フォルダ (`~/.claude/plugins/cache/25h-agent-kit/`) に plugin の写しが残る。もう読まれない写しで、手で消してよい。`docs/tool-audits/` の記録はあなたの物で、そのまま残る。

## ライセンス

MIT。[LICENSE](LICENSE) を見る。
