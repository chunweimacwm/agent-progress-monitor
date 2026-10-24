import { expect, test } from 'claude-code/testing'

import { applyToolCall, continueUrl, estimate, parseHostIdLine, parseTitleLine, PLAN_TOOL, shownStatus, toRows, WRAP_TOOL } from './progress'
import type { StatusRecord, Step } from './progress'

const items = [
  { content: 'A', status: 'in_progress' },
  { content: 'B', status: 'pending' },
  { content: 'C', status: 'pending' },
]

test('update_plan：items 全量，advance 往前一步', async () => {
  const p1 = applyToolCall(null, PLAN_TOOL, { items }) as Step[]
  expect(p1.map(s => s.status)).toEqual(['in_progress', 'pending', 'pending'])
  const p2 = applyToolCall(p1, PLAN_TOOL, { advance: true }) as Step[]
  expect(p2.map(s => s.status)).toEqual(['completed', 'in_progress', 'pending'])
  const p3 = applyToolCall(p2, PLAN_TOOL, { done: [2], start: 3 }) as Step[]
  expect(p3.map(s => s.status)).toEqual(['completed', 'completed', 'in_progress'])
  expect(p2.map(s => s.status)).toEqual(['completed', 'in_progress', 'pending'])
})

test('wrap_up 勾完清單；無關工具不動', async () => {
  const p = applyToolCall(null, PLAN_TOOL, { items }) as Step[]
  expect((applyToolCall(p, WRAP_TOOL, {}) as Step[]).every(s => s.status === 'completed')).toBe(true)
  expect(applyToolCall(p, 'Bash', { command: 'ls' })).toBe(undefined)
})

test('CLI 的 TaskCreate／TaskUpdate 累加與 TodoWrite', async () => {
  let p = applyToolCall(null, 'TaskCreate', { subject: 'A' }) as Step[]
  p = applyToolCall(p, 'TaskCreate', { subject: 'B' }) as Step[]
  p = applyToolCall(p, 'TaskUpdate', { taskId: '1', status: 'completed' }) as Step[]
  p = applyToolCall(p, 'TaskUpdate', { taskId: '2', status: 'deleted' }) as Step[]
  expect(estimate(p, false)).toEqual({ step: 1, total: 1, percent: 95, current: null })
  const t = applyToolCall(null, 'TodoWrite', { todos: [{ content: 'X', status: 'completed' }, { content: 'Y', status: 'pending' }] })
  expect(estimate(t ?? null, false)?.percent).toBe(50)
})

test('進度：進行中算半步、沒計畫不給百分比、只有完成才 100%', async () => {
  const p = applyToolCall(null, PLAN_TOOL, {
    items: [
      { content: 'A', status: 'completed' },
      { content: 'B', status: 'completed' },
      { content: 'C', status: 'in_progress' },
      { content: 'D', status: 'pending' },
      { content: 'E', status: 'pending' },
    ],
  }) as Step[]
  expect(estimate(p, false)).toEqual({ step: 3, total: 5, percent: 50, current: 'C' })
  expect(estimate(null, false)).toBe(null)
  expect(estimate(p, true)?.percent).toBe(100)
})

const rec = (patch: Partial<StatusRecord>): StatusRecord => ({
  v: 1, tool: 'claude-code', sessionId: 's', project: 'p', status: 'working', plan: null,
  turnStartedAt: 0, finishedAt: null, updatedAt: 0, blocked: false, ...patch,
})

test('狀態：心跳停了變閒置、完成久了變閒置、結束不顯示', async () => {
  expect(shownStatus(rec({ updatedAt: 1000 }), 2000)).toBe('working')
  expect(shownStatus(rec({ updatedAt: 0 }), 200_000)).toBe('idle')
  expect(shownStatus(rec({ status: 'done', finishedAt: 0, updatedAt: 0 }), 60_000)).toBe('done')
  expect(shownStatus(rec({ status: 'done', finishedAt: 0, updatedAt: 0 }), 11 * 60_000)).toBe('idle')
  expect(shownStatus(rec({ status: 'ended' }), 0)).toBe(null)
  const rows = toRows([rec({ sessionId: 'a', status: 'done', finishedAt: 0 }), rec({ sessionId: 'b', status: 'waiting' })], 1000)
  expect(rows.map(r => r.record.sessionId)).toEqual(['b', 'a'])
})

test('標題行解析與跳轉連結', async () => {
  expect(parseTitleLine('{"type":"custom-title","customTitle":"MODs","sessionId":"x"}\n')).toBe('MODs')
  expect(parseTitleLine('')).toBe(null)
  expect(parseTitleLine('{"type":"agent-name","agentName":"x"}')).toBe(null)
  expect(continueUrl('local_c452-bb')).toBe('claude://code/continue?session=local_c452-bb&source=spotlight')
  expect(parseHostIdLine('2026-10-24 [info] Mapping internal session local_c452-bb to CLI session 6c1f\n')).toBe('local_c452-bb')
  expect(parseHostIdLine('')).toBe(null)
})
