import { useEffect, useState, type ReactNode } from 'react'
import type { Burn, Roast, RoastResult, Status, Tip } from './api'
import { Footer } from './Home'
import { Stamp } from './Stamp'
import { useRoast } from './useRoast'

type Step = 'extracting' | 'roasting' | 'rendering'

const STEPS: { status: Step; label: string }[] = [
  { status: 'extracting', label: 'Leyendo tu perfil' },
  { status: 'roasting', label: 'Escribiendo el roast' },
  { status: 'rendering', label: 'Imprimiendo tu certificado' },
]
const ORDER: Status[] = ['queued', 'extracting', 'roasting', 'rendering', 'done']

/** Typical seconds per step, measured in production. They only drive the progress bar. */
const EXPECTED_S: Record<Roast['source'], Record<Step, number>> = {
  pdf: { extracting: 6, roasting: 12, rendering: 7 },
  url: { extracting: 30, roasting: 12, rendering: 7 },
}

const QUIPS: Record<Step, string[]> = {
  extracting: [
    'Sacando tu perfil del fólder manila.',
    'Contando cuántas veces dice “apasionado”.',
    'Buscando logros medibles. Seguimos buscando.',
    'Sumando cuántos meses duraste en cada trabajo.',
  ],
  roasting: [
    'Afilando los remates.',
    'El comité de Recursos Humanos ya se está riendo.',
    'Traduciendo tus buzzwords al español.',
    'Escribiendo las correcciones serias. Sí, también hay de esas.',
  ],
  rendering: ['Calentando la cera del sello.', 'Falsificando la firma del comité.', 'Secando la tinta.'],
}

const INTENSITY_LABEL = { soft: 'suave', medium: 'media', brutal: 'brutal' } as const

export function RoastPage({ id, onNew }: { id: string; onNew: () => void }) {
  const state = useRoast(id)

  if (state.kind === 'loading') {
    return (
      <Shell>
        <p className="py-20 text-center text-ink-soft">Buscando tu trámite…</p>
      </Shell>
    )
  }
  if (state.kind === 'expired') return <Expired onNew={onNew} />
  if (state.kind === 'stalled') {
    return (
      <Shell>
        <Notice title="Esto está tardando demasiado" onNew={onNew}>
          Tu roast sigue en proceso pero ya pasaron cinco minutos. Recarga la página en un rato o haz uno nuevo.
        </Notice>
      </Shell>
    )
  }

  const { roast } = state
  if (roast.status === 'failed') {
    return (
      <Shell>
        <Notice title="No pudimos terminar tu roast" onNew={onNew}>
          {roast.error}
        </Notice>
      </Shell>
    )
  }

  return (
    <Shell wide={Boolean(roast.result)}>
      {roast.result ? <Verdict roast={roast} result={roast.result} onNew={onNew} /> : <Progress roast={roast} />}
    </Shell>
  )
}

function Shell({ children, wide = false }: { children: ReactNode; wide?: boolean }) {
  return (
    <main className={`mx-auto px-4 pt-8 pb-16 sm:px-8 sm:pt-12 ${wide ? 'max-w-6xl' : 'max-w-2xl'}`}>
      {children}
      <Footer />
    </main>
  )
}

function useSeconds() {
  const [started] = useState(() => Date.now())
  const [now, setNow] = useState(started)
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 1000)
    return () => clearInterval(t)
  }, [])
  return Math.floor((now - started) / 1000)
}

function Progress({ roast }: { roast: Roast }) {
  const elapsed = useSeconds()
  const current = ORDER.indexOf(roast.status === 'queued' ? 'extracting' : roast.status)
  const expected = EXPECTED_S[roast.source]
  const total = STEPS.reduce((sum, s) => sum + expected[s.status], 0)
  const doneBefore = STEPS.filter((s) => ORDER.indexOf(s.status) < current).reduce((sum, s) => sum + expected[s.status], 0)
  // Never reach 100 % before the worker says so; ease toward 95 % if a step runs long.
  const guess = Math.min(doneBefore + expected[ORDER[current] as Step] * 0.9, Math.max(doneBefore, elapsed))
  const pct = Math.min(95, Math.round((guess / total) * 100))
  const step = ORDER[current] as Step
  const quip = QUIPS[step][Math.floor(elapsed / 4) % QUIPS[step].length]

  return (
    <section aria-live="polite" className="border-2 border-ink bg-sheet">
      <div className="border-b-2 border-ink px-5 py-4 sm:px-8">
        <h1 className="display text-3xl sm:text-4xl">Tu trámite está en proceso</h1>
        <p className="mt-2 text-ink-soft">
          Suele tardar unos {total} segundos{roast.source === 'url' ? ' con LinkedIn' : ''}. Puedes dejar esta pestaña
          abierta y volver.
        </p>
      </div>
      <div className="px-5 pt-5 sm:px-8">
        <div
          role="progressbar"
          aria-label="Avance del roast"
          aria-valuenow={pct}
          aria-valuemin={0}
          aria-valuemax={100}
          className="h-3 border-2 border-ink bg-paper"
        >
          <div className="h-full bg-stamp transition-[width] duration-1000 ease-linear" style={{ width: `${pct}%` }} />
        </div>
        <p className="mt-2 flex justify-between font-type text-sm text-ink-soft">
          <span>{quip}</span>
          <span className="shrink-0 pl-3">{elapsed} s</span>
        </p>
      </div>
      <ol className="mt-3 divide-y divide-rule border-t border-rule">
        {STEPS.map((s) => {
          const idx = ORDER.indexOf(s.status)
          const done = current > idx
          const active = current === idx
          return (
            <li key={s.status} className="flex min-h-16 items-center justify-between gap-4 px-5 py-3 sm:px-8">
              <span className={`text-lg ${done || active ? 'text-ink' : 'text-ink-soft/50'}`}>
                {s.label}
                {active && (
                  <span className="typing ml-1" aria-hidden>
                    <span>.</span>
                    <span>.</span>
                    <span>.</span>
                  </span>
                )}
              </span>
              {done && (
                <Stamp animate tilt={-7} className="text-lg">
                  Listo
                </Stamp>
              )}
            </li>
          )
        })}
      </ol>
    </section>
  )
}

function Verdict({ roast, result, onNew }: { roast: Roast; result: RoastResult; onNew: () => void }) {
  const burns = result.burns ?? []
  return (
    <article>
      <header className="border-b-2 border-ink pb-6">
        <p className="font-type text-ink-soft">
          Dictamen para <span className="text-ink">{result.name}</span>, intensidad {INTENSITY_LABEL[roast.intensity]}
        </p>
        <div className="mt-3 flex items-end justify-between gap-4">
          <h1 className="display max-w-4xl text-[clamp(2.25rem,7vw,4.75rem)] text-balance">{result.headline}</h1>
          <div className="shrink-0 pb-1" aria-label={`Calificación: ${result.score} de 10`}>
            <Stamp animate tilt={-12} className="px-2 text-center text-[clamp(1.75rem,6vw,3.75rem)] leading-none">
              {result.score}/10
            </Stamp>
          </div>
        </div>
      </header>

      <div className="mt-8 grid gap-x-12 gap-y-10 lg:grid-cols-[minmax(0,1fr)_22rem] xl:grid-cols-[minmax(0,1fr)_26rem]">
        <div className="min-w-0">
          <div className="max-w-2xl space-y-4 text-xl leading-relaxed">
            {result.roast.split(/\n+/).map((p, i) => (
              <p key={i}>{p}</p>
            ))}
          </div>

          {burns.length > 0 && <Findings burns={burns} />}

          {result.closer && (
            <p className="display mt-8 max-w-2xl border-l-4 border-stamp pl-4 text-3xl text-stamp sm:text-4xl">
              {result.closer}
            </p>
          )}

          <Corrections tips={result.tips} />
        </div>

        <aside className="lg:sticky lg:top-6 lg:self-start">
          <h2 className="sr-only">Tu certificado</h2>
          {roast.cardUrl ? (
            <img
              src={roast.cardUrl}
              alt={`Certificado de roast para ${result.name}: ${result.headline}, ${result.score}/10`}
              width={1200}
              height={630}
              className="stamp-in block h-auto w-full border-2 border-ink shadow-[5px_5px_0_var(--color-ink)] [--tilt:0deg]"
            />
          ) : (
            <div className="flex aspect-[1200/630] flex-col items-center justify-center gap-2 border-2 border-dashed border-ink-soft/60 bg-sheet text-center text-ink-soft">
              <span className="animate-pulse text-lg">Imprimiendo tu certificado…</span>
              <span className="text-sm">Unos segundos más</span>
            </div>
          )}
          {roast.status === 'done' ? (
            <ShareBar roast={roast} result={result} onNew={onNew} />
          ) : (
            <p className="mt-4 text-sm text-ink-soft">Cuando el certificado esté listo podrás compartirlo o descargarlo.</p>
          )}
        </aside>
      </div>
    </article>
  )
}

function Findings({ burns }: { burns: Burn[] }) {
  return (
    <section className="mt-10 max-w-2xl">
      <h2 className="display text-3xl">Observaciones del revisor</h2>
      <ul className="mt-5 space-y-6">
        {burns.map((b, i) => (
          <li key={i} className="border-l-2 border-rule pl-4">
            {b.quote && (
              <p className="font-type text-ink-soft [overflow-wrap:anywhere]">
                <q className="underline decoration-stamp decoration-wavy decoration-2 underline-offset-4">{b.quote}</q>
              </p>
            )}
            <p className="mt-2 text-lg leading-relaxed">{b.joke}</p>
          </li>
        ))}
      </ul>
    </section>
  )
}

function Corrections({ tips }: { tips: (Tip | string)[] }) {
  return (
    <section className="mt-12 border-2 border-ink bg-sheet">
      <div className="border-b-2 border-ink px-5 py-4 sm:px-7">
        <h2 className="display text-3xl">Ahora sí, en serio</h2>
        <p className="mt-1 text-ink-soft">Tres cambios, del que más impacto tiene al que menos.</p>
      </div>
      <ol className="divide-y divide-rule">
        {tips.map((tip, i) => (
          <li key={i} className="flex gap-3 px-5 py-6 sm:gap-4 sm:px-7">
            <span className="font-type text-xl font-bold text-stamp">{i + 1}.</span>
            <div className="min-w-0 flex-1">{typeof tip === 'string' ? <p className="leading-relaxed">{tip}</p> : <TipBody tip={tip} />}</div>
          </li>
        ))}
      </ol>
    </section>
  )
}

function TipBody({ tip }: { tip: Tip }) {
  const [copied, setCopied] = useState(false)
  const missing = /^no existe\.?$/i.test(tip.before.trim())

  async function copy() {
    try {
      await navigator.clipboard.writeText(tip.after)
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    } catch {
      /* clipboard blocked: the text is still selectable */
    }
  }

  return (
    <>
      <h3 className="text-xl leading-snug font-bold">{tip.title}</h3>
      <p className="mt-1 leading-relaxed text-ink-soft">{tip.why}</p>
      <div className="mt-4 grid gap-3 md:grid-cols-2">
        <div className="border border-rule px-4 py-3">
          <p className="text-sm font-semibold text-ink-soft">Hoy dice</p>
          <p className={`mt-1 text-ink-soft [overflow-wrap:anywhere] ${missing ? 'italic' : 'font-type text-[0.95rem]'}`}>
            {missing ? 'Esta sección no existe en tu perfil.' : tip.before}
          </p>
        </div>
        <div className="border-2 border-ink bg-manila/30 px-4 py-3">
          <div className="flex items-center justify-between gap-2">
            <p className="text-sm font-semibold">Cámbialo por</p>
            <button
              type="button"
              onClick={copy}
              className="border border-ink px-2 py-0.5 text-sm font-semibold hover:bg-ink hover:text-sheet"
            >
              {copied ? 'Copiado' : 'Copiar'}
            </button>
          </div>
          <p className="mt-1 [overflow-wrap:anywhere]">{tip.after}</p>
        </div>
      </div>
    </>
  )
}

function hoursLeft(expiresAt: string) {
  const h = Math.max(0, Math.ceil((new Date(expiresAt).getTime() - Date.now()) / 3_600_000))
  return h === 1 ? '1 hora' : `${h} horas`
}

function ShareBar({ roast, result, onNew }: { roast: Roast; result: RoastResult; onNew: () => void }) {
  const [copied, setCopied] = useState(false)
  const link = `${window.location.origin}/r/${roast.id}`

  async function copy() {
    try {
      await navigator.clipboard.writeText(link)
      setCopied(true)
      setTimeout(() => setCopied(false), 2500)
    } catch {
      window.prompt('Copia tu enlace', link)
    }
  }

  async function share() {
    try {
      await navigator.share({ title: `Roastfolio: ${result.headline}`, text: `Me dieron ${result.score}/10 en Roastfolio`, url: link })
    } catch {
      /* user closed the share sheet */
    }
  }

  const btn = 'border-2 border-ink px-4 py-2.5 text-center font-semibold hover:bg-ink hover:text-sheet'
  return (
    <section className="mt-6">
      <h2 className="sr-only">Compartir</h2>
      <div className="grid grid-cols-2 gap-2">
        {'share' in navigator ? (
          <button type="button" onClick={share} className={`${btn} bg-ink text-sheet hover:border-stamp hover:bg-stamp`}>
            Compartir
          </button>
        ) : null}
        <button type="button" onClick={copy} className={btn}>
          {copied ? 'Enlace copiado' : 'Copiar enlace'}
        </button>
        {roast.cardUrl && (
          <a href={roast.cardUrl} download={`roastfolio-${roast.id}.jpg`} className={btn}>
            Descargar certificado
          </a>
        )}
        <button type="button" onClick={onNew} className={btn}>
          Hacer otro roast
        </button>
      </div>
      <p className="mt-3 text-sm text-ink-soft">Este roast y su enlace se borran en {hoursLeft(roast.expiresAt)}.</p>
    </section>
  )
}

function Notice({ title, children, onNew }: { title: string; children: ReactNode; onNew: () => void }) {
  return (
    <section role="alert" className="border-2 border-stamp bg-sheet px-5 py-8 sm:px-8">
      <h1 className="display text-4xl text-stamp">{title}</h1>
      <p className="mt-4 max-w-xl text-lg">{children}</p>
      <button type="button" onClick={onNew} className="display mt-6 bg-ink px-6 py-3 text-2xl text-sheet hover:bg-stamp">
        Hacer otro roast
      </button>
    </section>
  )
}

function Expired({ onNew }: { onNew: () => void }) {
  return (
    <Shell>
      <section className="py-12 text-center sm:py-20">
        <Stamp animate tilt={-10} className="text-[clamp(2.5rem,10vw,5rem)] leading-none">
          Archivado
        </Stamp>
        <h1 className="display mt-16 text-5xl">Este roast ya expiró</h1>
        <p className="mx-auto mt-4 max-w-md text-lg text-ink-soft">
          Los roasts se borran a las 24 horas, con todo y certificado. Haz uno nuevo: tarda menos de un minuto.
        </p>
        <button type="button" onClick={onNew} className="display mt-8 bg-ink px-6 py-3 text-2xl text-sheet hover:bg-stamp">
          Hacer mi roast
        </button>
      </section>
    </Shell>
  )
}
