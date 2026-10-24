import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, Timer } from 'claude-code'

import {
  applyToolCall,
  bar,
  continueUrl,
  HOST_ID,
  estimate,
  formatDuration,
  HEARTBEAT_MS,
  isPlanFinished,
  parseHostIdLine,
  parseRecord,
  parseTitleLine,
  setEnglish,
  t,
  toRows,
} from './progress'
import type { Row, ShownStatus, StatusRecord } from './progress'
import type { UsageRecord } from '../types'

const PANE = 'agent-progress'
const POLL_MS = 3_000

const self = atom({ plugin: 'agent-progress', key: 'self' } as const, null)
const view = atom({ plugin: 'agent-progress', key: 'view' } as const, { now: 0, rows: [] })

// 狀態檔放在 ~/.agent-progress/claude-code/，不寫進 ~/.claude
let home: string | null = null
let dir: string | null = null
let writes: Promise<void> = Promise.resolve()
let poll: Timer | null = null
let beat: Timer | null = null

// 其他對話串的標題與桌面版 id 快取：舊版 mod 寫的狀態檔沒有這兩欄，由 pane 自己查
type Meta = { title: string | null; hostSessionId: string | null; at: number }
const metas = new Map<string, Meta>()
const TITLE_TTL_MS = 60_000

// 只取對話紀錄裡最後一行 custom-title 的標題，不讀其他內容
const lookupTitle = async ($: EngineInterface, sessionId: string): Promise<string | null> => {
  if (!home || !/^[0-9a-f-]+$/.test(sessionId)) return null
  const script = 'grep -h \'"type":"custom-title"\' "$0"/.claude/projects/*/"$1".jsonl 2>/dev/null | tail -1'
  const { stdout } = await $.process.run(['/bin/sh', '-c', script, home, sessionId])
  return parseTitleLine(stdout)
}

// 舊檔沒有桌面版 id 時，從桌面版日誌的對應行補
const lookupHostId = async ($: EngineInterface, sessionId: string): Promise<string | null> => {
  if (!home || !/^[0-9a-f-]+$/.test(sessionId)) return null
  const script = 'grep -h "to CLI session $1" "$0"/Library/Logs/Claude/main1.log "$0"/Library/Logs/Claude/main.log 2>/dev/null | tail -1'
  const { stdout } = await $.process.run(['/bin/sh', '-c', script, home, sessionId])
  return parseHostIdLine(stdout)
}

// 用量（5 小時／每週額度）取自最近一次 API 回應，寫給浮窗讀
const writeUsage = async ($: EngineInterface) => {
  if (!home) return
  const { rateLimits } = await $.session.usage()
  if (rateLimits.length === 0) return
  const record: UsageRecord = {
    v: 1,
    tool: 'claude-code',
    updatedAt: await $.clock.now(),
    windows: rateLimits.map(w => ({ kind: w.kind, percentUsed: w.percentUsed, resetsAt: w.resetsAt ?? null })),
  }
  await $.fs.write(`${home}/.agent-progress/usage/claude-code.json`, JSON.stringify(record))
}

const refreshTitle = async ($: EngineInterface) => {
  const cur = await read($, self)
  if (!cur) return
  const title = await lookupTitle($, cur.sessionId)
  if (title && title !== cur.title) await patch($, () => ({ title }))
}

const readHostId = async ($: EngineInterface) => {
  const id = await $.env.get('CLAUDE_CODE_HOST_SESSION_ID')
  return id && HOST_ID.test(id) ? id : null
}

const basename = (p: string) => p.replace(/\/+$/, '').split('/').pop() || p

const persist = ($: EngineInterface, r: StatusRecord | null) => {
  if (!dir || !r) return
  const path = `${dir}/${r.sessionId}.json`
  const text = JSON.stringify(r)
  writes = writes.then(() => $.fs.write(path, text)).catch(() => undefined)
}

const patch = async ($: EngineInterface, change: (r: StatusRecord) => Partial<StatusRecord>) => {
  const now = await $.clock.now()
  const next = await update($, self, r => (r ? { ...r, ...change(r), updatedAt: now } : r))
  persist($, next)
}

// /clear 會換 session id；每輪開始時對一次，換了就把舊檔標成結束
const ensureSelf = async ($: EngineInterface) => {
  const id = await $.session.id()
  const cur = await read($, self)
  if (cur?.sessionId === id) return
  const now = await $.clock.now()
  if (cur) persist($, { ...cur, status: 'ended', updatedAt: now })
  const fresh: StatusRecord = {
    v: 1,
    tool: 'claude-code',
    sessionId: id,
    project: basename(await $.session.cwd()),
    title: null,
    hostSessionId: await readHostId($),
    status: 'idle',
    plan: null,
    turnStartedAt: null,
    finishedAt: null,
    updatedAt: now,
    blocked: false,
  }
  await update($, self, () => fresh)
  persist($, fresh)
}

const refresh = async ($: EngineInterface) => {
  if (!dir) return
  const entries = await $.fs.list(dir).catch(() => [])
  const texts = await Promise.all(
    entries
      .filter(f => f.kind === 'file' && f.name.endsWith('.json'))
      .map(f => $.fs.read(`${dir}/${f.name}`).catch(() => '')),
  )
  const records = texts.map(t => (typeof t === 'string' ? parseRecord(t) : null)).filter((r): r is StatusRecord => r !== null)
  const now = await $.clock.now()
  const rows = toRows(records, now)
  for (const { record } of rows) {
    if (record.title && record.hostSessionId) continue
    const hit = metas.get(record.sessionId)
    if (!hit || now - hit.at > TITLE_TTL_MS) {
      metas.set(record.sessionId, {
        title: record.title ? null : await lookupTitle($, record.sessionId).catch(() => null),
        hostSessionId: record.hostSessionId ? null : await lookupHostId($, record.sessionId).catch(() => null),
        at: now,
      })
    }
  }
  const named = rows.map(row => {
    const meta = metas.get(row.record.sessionId)
    const r = row.record

    return { ...row, record: { ...r, title: r.title ?? meta?.title ?? null, hostSessionId: r.hostSessionId ?? meta?.hostSessionId ?? null } }
  })
  await update($, view, () => ({ now, rows: named }))
}

const label = (s: ShownStatus): { text: string; color: string } =>
  ({
    working: { text: t('● 工作中', '● Working'), color: 'claude' },
    waiting: { text: t('◆ 等你', '◆ Needs you'), color: 'warning' },
    done: { text: t('✓ 完成', '✓ Done'), color: 'success' },
    idle: { text: t('○ 閒置', '○ Idle'), color: 'inactive' },
  })[s]

const timeText = (row: Row, now: number) => {
  const r = row.record
  if (row.status === 'working' || row.status === 'waiting') {
    return r.turnStartedAt ? t(`已 ${formatDuration(now - r.turnStartedAt)}`, formatDuration(now - r.turnStartedAt)) : ''
  }
  if (r.finishedAt) return t(`${formatDuration(now - r.finishedAt)}前`, `${formatDuration(now - r.finishedAt)} ago`)
  return ''
}

export const register: Register = (on, options) => {
  const autoOpen = options?.autoOpen !== false
  setEnglish(options?.language === 'en')
  const paneTitle = t('Agent 進度', 'Agent Monitor')

  on('session.start', async ($, e, next) => {
    const result = await next(e)
    home = (await $.env.get('HOME')) ?? null
    dir = home ? `${home}/.agent-progress/claude-code` : null
    await ensureSelf($)
    // hot reload 時舊紀錄可能沒有桌面版 id
    const hostSessionId = await readHostId($)
    if (hostSessionId && (await read($, self))?.hostSessionId !== hostSessionId) await patch($, () => ({ hostSessionId }))
    void refreshTitle($).catch(() => undefined)
    await $.command.register({ name: 'progress', description: t('打開所有 Claude Code 對話串的進度 pane', 'Open the progress pane for all Claude Code threads') })
    poll?.cancel()
    beat?.cancel()
    poll = $.clock.every(POLL_MS, () => void refresh($))
    beat = $.clock.every(HEARTBEAT_MS, () => {
      void patch($, () => ({}))
      // 額度在一輪進行中也會變，順便更新
      void writeUsage($).catch(() => undefined)
    })
    void refresh($)
    if (autoOpen) void $.ui.open({ id: PANE, title: paneTitle })

    return result
  })

  on('command.run', { command: 'progress' }, async $ => {
    await $.ui.open({ id: PANE, title: paneTitle })

    return { text: t('已打開進度 pane。', 'Progress pane opened.') }
  })

  on('session.end', async ($, e, next) => {
    const cur = await read($, self)
    if (cur) persist($, { ...cur, status: 'ended', updatedAt: await $.clock.now() })
    await writes

    return next(e)
  })

  on('turn.start', async ($, e, next) => {
    if (e.agentId === undefined) {
      await ensureSelf($)
      const now = await $.clock.now()
      await patch($, r => ({
        status: 'working',
        turnStartedAt: now,
        finishedAt: null,
        blocked: false,
        // 上一輪的計畫已經做完就清掉，新的一輪重新算
        plan: isPlanFinished(r.plan) ? null : r.plan,
      }))
    }

    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    const result = await next(e)
    if (e.agentId === undefined) {
      const now = await $.clock.now()
      await patch($, r => ({
        status: e.reason === 'answer' ? (r.blocked ? 'waiting' : 'done') : 'aborted',
        finishedAt: now,
      }))
      // 桌面版在第一輪後才會產生標題
      void refreshTitle($).catch(() => undefined)
      void writeUsage($).catch(() => undefined)
    }

    return result
  })

  // 權限對話框真的要問人時才算「等你」；tool.check 的 ask 在 auto 模式下會被分類器接手，不能用
  on('classic.PermissionRequest', async ($, e, next) => {
    if (e.agent_id === undefined) await patch($, () => ({ status: 'waiting' })).catch(() => undefined)

    return next(e)
  })

  on('tool.call', async ($, e, next) => {
    if (e.agentId !== undefined) return next(e)
    const args = e as unknown as Record<string, unknown>
    const asks = e.tool === 'AskUserQuestion'
    if (asks) await patch($, () => ({ status: 'waiting' })).catch(() => undefined)
    const result = await next(e)
    const cur = await read($, self).catch(() => null)
    const plan = cur ? applyToolCall(cur.plan, e.tool, args) : undefined
    const blocked = e.tool === 'mcp__ccd_turn__wrap_up' && args.blocked === true
    if (plan !== undefined || blocked || cur?.status === 'waiting') {
      await patch($, r => ({
        ...(plan !== undefined ? { plan } : {}),
        ...(blocked ? { blocked: true } : {}),
        ...(r.status === 'waiting' ? { status: 'working' } : {}),
      })).catch(() => undefined)
    }

    return result
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Button } = $.ui.resolve(e)
    const { now, rows } = await read($, view)
    const me = (await read($, self))?.sessionId
    const busy = rows.filter(r => r.status === 'working' || r.status === 'waiting').length

    return (
      <Box flexDirection="column" gap={1}>
        <Text dimColor>
          Claude Code · {t(`${rows.length} 個對話串`, `${rows.length} threads`)}{busy > 0 ? t(` · ${busy} 個進行中`, ` · ${busy} active`) : ''}
        </Text>
        {rows.length === 0 && <Text dimColor>{t('還沒有對話串的狀態。', 'No thread status yet.')}</Text>}
        {rows.map(row => {
          const r = row.record
          // 完成後轉成閒置仍算收到完成訊號
          const p = estimate(r.plan, r.status === 'done')
          const l = label(row.status)

          return (
            <Box flexDirection="column">
              <Text>
                <Text color={l.color}>{l.text}</Text>
                <Text dimColor> · {timeText(row, now)}</Text>
              </Text>
              {r.sessionId === me || !r.hostSessionId ? (
                <Text>
                  <Text bold>{r.title ?? r.project}</Text>
                  {r.sessionId === me && <Text dimColor>{t(' （這裡）', ' (here)')}</Text>}
                </Text>
              ) : (
                // 點一下用桌面版深層連結跳到該對話串
                <Button
                  key={r.sessionId}
                  plain
                  onPress={() => void $.process.run(['open', continueUrl(r.hostSessionId!)]).catch(() => undefined)}
                >
                  <Text bold>↗ {r.title ?? r.project}</Text>
                </Button>
              )}
              <Text dimColor wrap="truncate-end">
                {r.title ? `${r.project} · ` : ''}
                {r.sessionId.slice(0, 4)}
              </Text>
              {p ? (
                <Text>
                  <Text color={l.color}>{bar(p.percent)}</Text> {t(`步驟 ${p.step}/${p.total} · 約 ${p.percent}%`, `Step ${p.step}/${p.total} · ~${p.percent}%`)}
                </Text>
              ) : (
                <Text dimColor>{row.status === 'working' ? t('進行中（沒有列計畫，不估百分比）', 'Working (no plan, no percentage)') : t('沒有列計畫', 'No plan')}</Text>
              )}
              {p?.current && row.status !== 'done' && (
                <Text dimColor wrap="truncate-end">
                  → {p.current}
                </Text>
              )}
            </Box>
          )
        })}
      </Box>
    )
  })
}
