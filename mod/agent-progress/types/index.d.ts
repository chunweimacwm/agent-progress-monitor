export type StepStatus = 'pending' | 'in_progress' | 'completed' | 'deleted'
export type Step = { id: string; title: string; status: StepStatus }

// 寫進檔案的狀態；'idle' 由讀取端依時間推得
export type FileStatus = 'idle' | 'working' | 'waiting' | 'done' | 'aborted' | 'ended'
export type ShownStatus = 'working' | 'waiting' | 'done' | 'idle'

// 狀態檔格式 v1：~/.agent-progress/claude-code/<sessionId>.json，Swift 浮窗讀同一份
export type StatusRecord = {
  v: 1
  tool: 'claude-code'
  sessionId: string
  project: string
  // 桌面版對話串標題（custom-title）；舊檔或尚未命名時沒有
  title?: string | null
  // 桌面版內部 id（local_…），深層連結跳轉用；CLI 或舊檔沒有
  hostSessionId?: string | null
  status: FileStatus
  plan: Step[] | null
  turnStartedAt: number | null
  finishedAt: number | null
  updatedAt: number
  blocked: boolean
}

// 用量檔 v1：~/.agent-progress/usage/claude-code.json，帳號層級，最後寫入的 session 為準
export type UsageWindow = { kind: string; percentUsed: number; resetsAt: string | null }
export type UsageRecord = { v: 1; tool: 'claude-code'; updatedAt: number; windows: UsageWindow[] }

export type Row = { record: StatusRecord; status: ShownStatus }
export type View = { now: number; rows: Row[] }

declare module 'claude-code' {
  interface PluginState {
    'agent-progress': { self: StatusRecord | null; view: View }
  }
}
