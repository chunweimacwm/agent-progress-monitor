// 純邏輯：計畫累加、進度估算、狀態判斷。不碰 $，方便單獨測試。
// 狀態檔格式（v1）也定義在這裡，Swift 浮窗之後讀同一份。

import type { Row, ShownStatus, Step, StatusRecord } from '../types'

export type { Row, ShownStatus, Step, StatusRecord }

export const PLAN_TOOL = 'mcp__ccd_turn__update_plan'
export const WRAP_TOOL = 'mcp__ccd_turn__wrap_up'

// 心跳間隔與判斷門檻（毫秒）
export const HEARTBEAT_MS = 30_000
export const STALE_MS = 120_000
export const IDLE_AFTER_DONE_MS = 10 * 60_000
export const HIDE_AFTER_MS = 6 * 60 * 60_000

const normStatus = (s: unknown): Step['status'] =>
  s === 'completed' || s === 'in_progress' || s === 'deleted' ? s : 'pending'

const asList = (v: unknown): Record<string, unknown>[] =>
  Array.isArray(v) ? v.filter((x): x is Record<string, unknown> => !!x && typeof x === 'object') : []

const live = (plan: Step[]) => plan.filter(s => s.status !== 'deleted')

// 桌面版 update_plan：items 全量取代，再依序套用 done／start／advance（皆為 1-based 位置）
const applyCcdPlan = (prev: Step[] | null, a: Record<string, unknown>): Step[] | null => {
  let plan = prev ? prev.map(s => ({ ...s })) : null
  const items = asList(a.items)
  if (items.length > 0) {
    plan = items.map((it, i) => ({ id: String(i + 1), title: String(it.content ?? ''), status: normStatus(it.status) }))
  }
  if (!plan) return plan
  const at = (n: unknown) => (typeof n === 'number' ? plan![n - 1] : undefined)
  if (Array.isArray(a.done)) for (const n of a.done) { const s = at(n); if (s) s.status = 'completed' }
  const started = at(a.start)
  if (started) started.status = 'in_progress'
  if (a.advance === true) {
    const cur = plan.find(s => s.status === 'in_progress')
    if (cur) cur.status = 'completed'
    const nxt = plan.find(s => s.status === 'pending')
    if (nxt) nxt.status = 'in_progress'
  }
  return plan
}

/**
 * 依一次工具呼叫更新計畫。回傳 undefined 表示這個工具和計畫無關。
 */
export const applyToolCall = (prev: Step[] | null, tool: string, a: Record<string, unknown>): Step[] | null | undefined => {
  switch (tool) {
    case PLAN_TOOL:
      return applyCcdPlan(prev, a)
    case WRAP_TOOL:
      // wrap_up 會順便勾完整份清單
      return prev ? prev.map(s => (s.status === 'deleted' ? s : { ...s, status: 'completed' })) : prev
    case 'TodoWrite':
      return asList(a.todos).map((t, i) => ({ id: String(i + 1), title: String(t.content ?? ''), status: normStatus(t.status) }))
    case 'TaskCreate': {
      const plan = prev ?? []
      return [...plan, { id: String(plan.length + 1), title: String(a.subject ?? ''), status: 'pending' }]
    }
    case 'TaskUpdate': {
      if (!prev) return prev
      const id = String(a.taskId ?? '')
      return prev.map(s => (s.id === id && a.status !== undefined ? { ...s, status: normStatus(a.status) } : s))
    }
    default:
      return undefined
  }
}

export const isPlanFinished = (plan: Step[] | null) =>
  !!plan && live(plan).length > 0 && live(plan).every(s => s.status === 'completed')

export type Progress = { step: number; total: number; percent: number; current: string | null }

/**
 * 有計畫時：完成步驟 ÷ 總步驟，進行中算半步；只有完成訊號才給 100%。
 * 沒有計畫回傳 null（介面不顯示百分比）。
 */
export const estimate = (plan: Step[] | null, isDone: boolean): Progress | null => {
  if (!plan) return null
  const steps = live(plan)
  if (steps.length === 0) return null
  const done = steps.filter(s => s.status === 'completed').length
  const cur = steps.find(s => s.status === 'in_progress') ?? null
  const raw = Math.round(((done + (cur ? 0.5 : 0)) / steps.length) * 100)
  return {
    step: Math.min(steps.length, done + (cur ? 1 : 0)),
    total: steps.length,
    percent: isDone ? 100 : Math.min(95, raw),
    current: cur?.title ?? null,
  }
}

/**
 * 讀取端的狀態判斷。回傳 null 表示不顯示（已結束或太久沒動）。
 */
export const shownStatus = (r: StatusRecord, now: number): ShownStatus | null => {
  if (r.status === 'ended' || now - r.updatedAt > HIDE_AFTER_MS) return null
  if (r.status === 'working' || r.status === 'waiting') {
    // 心跳停了：session 大概被關掉了
    return now - r.updatedAt > STALE_MS ? 'idle' : r.status
  }
  if (r.status === 'done') {
    return r.finishedAt !== null && now - r.finishedAt > IDLE_AFTER_DONE_MS ? 'idle' : 'done'
  }
  return 'idle'
}

export const parseRecord = (text: string): StatusRecord | null => {
  try {
    const o = JSON.parse(text) as StatusRecord
    return o && o.v === 1 && o.tool === 'claude-code' && typeof o.sessionId === 'string' ? o : null
  } catch {
    return null
  }
}

const ORDER: Record<ShownStatus, number> = { waiting: 0, working: 1, done: 2, idle: 3 }


export const toRows = (records: StatusRecord[], now: number): Row[] =>
  records
    .map(record => ({ record, status: shownStatus(record, now) }))
    .filter((r): r is Row => r.status !== null)
    .sort((a, b) => ORDER[a.status] - ORDER[b.status] || b.record.updatedAt - a.record.updatedAt)

// 桌面版的深層連結只收內部 id（local_…），不收 Claude Code 的 session id
export const HOST_ID = /^local_[A-Za-z0-9-]{1,64}$/

export const continueUrl = (hostSessionId: string) =>
  `claude://code/continue?session=${encodeURIComponent(hostSessionId)}&source=spotlight`

// 桌面版日誌的對應行：「Mapping internal session local_x to CLI session y」
export const parseHostIdLine = (line: string): string | null => {
  const m = /Mapping internal session (local_[A-Za-z0-9-]{1,64}) to CLI session/.exec(line)
  return m?.[1] ?? null
}

// 從對話紀錄的 custom-title 行取標題；格式不對就回 null
export const parseTitleLine = (line: string): string | null => {
  try {
    const o = JSON.parse(line.trim()) as { type?: unknown; customTitle?: unknown }
    return o.type === 'custom-title' && typeof o.customTitle === 'string' && o.customTitle.trim() ? o.customTitle.trim() : null
  } catch {
    return null
  }
}

// 介面語言：由 register 依 userConfig 設定
let english = false
export const setEnglish = (on: boolean) => {
  english = on
}
export const t = (zh: string, en: string) => (english ? en : zh)

export const formatDuration = (ms: number): string => {
  const min = Math.floor(Math.max(0, ms) / 60_000)
  if (min < 1) return t('不到 1 分', '<1m')
  if (min < 60) return t(`${min} 分`, `${min}m`)
  return t(`${Math.floor(min / 60)} 時 ${min % 60} 分`, `${Math.floor(min / 60)}h ${min % 60}m`)
}

export const bar = (percent: number, width = 12): string => {
  const full = Math.round((percent / 100) * width)
  return '█'.repeat(full) + '░'.repeat(width - full)
}
