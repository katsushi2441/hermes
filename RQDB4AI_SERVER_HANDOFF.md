# RQDB4AI Server Codex Handoff

目的:
RQDB4AI本体をworker個別対応の無限修正から外し、全workerを共通result仕様で扱う。

前提:
- RQDB4AI本体は別サーバで稼働する。
- このWEB/APIサーバ側では、Hermes enqueueと各project側job wrapperだけを管理する。
- RQDB4AI本体にはAIxEC/Horizon/URL2AI/BuzBlogger固有のdashboard判定ロジックを入れない。

最新取得:

```bash
cd /home/kojima/work/rqdb4ai
git pull origin main

cd /home/kojima/work/aixec
git pull origin main

cd /home/kojima/work/horizon
git pull origin main

cd /home/kojima/work/url2ai
git pull origin main
```

共通result仕様:

```json
{
  "ok": true,
  "status": "ok",
  "items": 1,
  "metrics": {
    "created": 1,
    "updated": 0,
    "skipped": 0,
    "failed": 0
  },
  "note": "short summary",
  "artifacts": [],
  "error": null
}
```

RQDB4AI本体でやること:

1. job detail / queue UI / lifecycle / dashboard API は、上記resultだけを見る。
2. `items` は `result.items` のみを使う。
3. 詳細件数は `result.metrics` のみを表示する。
4. 成功判定は以下に統一する。
   - RQ statusが `finished`
   - `result.ok === true`
   - `result.status` が `ok` または `warn`
5. `enqueue成功`、`外部worker起動成功`、`RQ finishedだけ` を業務成功扱いしない。
6. worker名ごとの特別処理を削除する。
7. stdoutから件数を正規表現で拾う処理を削除する。
8. `created`, `registered`, `success_count`, `selected` など旧top-level件数をdashboard判定に使わない。

禁止:

- `if function == "horizon_jobs.worker_auto_cycle_job"` のような分岐
- `if function == "aixec_market_jobs.register_market_worker_job"` のような分岐
- stdout_tail解析
- API response構造のworker別解析
- RQDB4AI本体へのproject固有business logic追加

project側の対応状況:

- `katsushi2441/hermes`
  - `RQDB4AI_RESULT_SPEC.md` 追加済み
  - `scripts/rqdb4ai_status_sync.sh` は共通resultだけを見るよう修正済み
- `katsushi2441/aixec`
  - `aixec_market_jobs.py` は共通result形式で返すよう修正済み
- `katsushi2441/horizon`
  - `horizon_jobs.py` は共通result形式で返すよう修正済み
- `katsushi2441/url2ai`
  - `oss_jobs.py`
  - `finreport_jobs.py`
  - `polymarket_jobs.py`
  - 上記は共通result形式で返すよう修正済み

検証:

```bash
# RQDB4AI側で各jobをdry-runまたは少量実行し、resultの形だけ確認
curl -sS "$RQDB4AI_API_URL/api/jobs?limit=20" \
  -H "Authorization: Bearer $RQDB4AI_API_TOKEN" | jq '.jobs[] | {id,status,function:.task.name,result}'
```

合格条件:

- すべてのjob resultに `ok/status/items/metrics/note/artifacts/error` がある。
- dashboardに表示される件数は `result.items` と一致する。
- RQDB4AI本体コードにworker名別の件数補正がない。
- 新workerを追加してもRQDB4AI本体を変更しない。
