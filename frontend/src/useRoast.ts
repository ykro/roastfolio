import { useEffect, useState } from 'react'
import { getRoast, type Roast } from './api'

export type RoastState =
  | { kind: 'loading' }
  | { kind: 'expired' }
  | { kind: 'stalled' }
  | { kind: 'ready'; roast: Roast }

const POLL_MS = 2000
const GIVE_UP_MS = 5 * 60 * 1000

/** Polls GET /api/roasts/{id} every 2 s until the roast is done, failed or gone. */
export function useRoast(id: string, pollMs = POLL_MS): RoastState {
  const [state, setState] = useState<RoastState>({ kind: 'loading' })

  useEffect(() => {
    let cancelled = false
    let timer: ReturnType<typeof setTimeout>
    const started = Date.now()

    const tick = async () => {
      try {
        const roast = await getRoast(id)
        if (cancelled) return
        if (!roast) return setState({ kind: 'expired' })
        setState({ kind: 'ready', roast })
        if (roast.status === 'done' || roast.status === 'failed') return
      } catch {
        // transient network error: keep polling
      }
      if (Date.now() - started > GIVE_UP_MS) return setState({ kind: 'stalled' })
      timer = setTimeout(tick, pollMs)
    }
    tick()
    return () => {
      cancelled = true
      clearTimeout(timer)
    }
  }, [id, pollMs])

  return state
}
