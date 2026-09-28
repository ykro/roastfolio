export type Intensity = 'soft' | 'medium' | 'brutal'
export type Status = 'queued' | 'extracting' | 'roasting' | 'rendering' | 'done' | 'failed'

export interface Burn {
  quote: string
  joke: string
}

export interface Tip {
  title: string
  why: string
  before: string
  after: string
}

export interface RoastResult {
  name: string
  headline: string
  /** Opening lines. */
  roast: string
  burns: Burn[]
  closer: string
  score: number
  tips: Tip[]
}

export interface Roast {
  id: string
  status: Status
  intensity: Intensity
  source: 'pdf' | 'url'
  expiresAt: string
  result?: RoastResult
  cardUrl?: string
  /** True when Nano Banana failed and the worker used the pre-made generic certificate. */
  cardGeneric?: boolean
  error?: string
}

export class ApiError extends Error {}

export async function createRoast(input: {
  intensity: Intensity
  consent: boolean
  pdf?: File | null
  url?: string
}): Promise<string> {
  const form = new FormData()
  form.set('intensity', input.intensity)
  form.set('consent', String(input.consent))
  if (input.pdf) form.set('pdf', input.pdf)
  if (input.url) form.set('url', input.url)

  let res: Response
  try {
    res = await fetch('/api/roasts', { method: 'POST', body: form })
  } catch {
    throw new ApiError('No hay conexión con el servidor. Revisa tu internet e intenta otra vez.')
  }
  if (res.status === 429) {
    throw new ApiError('Llegaste al límite de 5 roasts cada 10 minutos. Espera un rato y vuelve a intentarlo.')
  }
  const body = await res.json().catch(() => ({}))
  if (!res.ok) {
    // Cloud Armor blocks come back as 403 without a JSON body.
    throw new ApiError(body.detail ?? 'No pudimos recibir tu solicitud. Intenta de nuevo.')
  }
  return body.id as string
}

/** Returns null when the roast doesn't exist or already expired. */
export async function getRoast(id: string): Promise<Roast | null> {
  const res = await fetch(`/api/roasts/${encodeURIComponent(id)}`)
  if (res.status === 404) return null
  if (!res.ok) throw new ApiError(`HTTP ${res.status}`)
  return res.json()
}
