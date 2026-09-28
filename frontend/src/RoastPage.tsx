import { useState, type ReactNode } from 'react'
import type { Roast, RoastResult, Status } from './api'
import { Footer } from './Home'
import { Stamp } from './Stamp'
import { useRoast } from './useRoast'

const STEPS: { status: Status; label: string }[] = [
  { status: 'extracting', label: 'Leyendo tu perfil' },
  { status: 'roasting', label: 'Escribiendo el roast' },
  { status: 'rendering', label: 'Imprimiendo tu certificado' },
]
const ORDER: Status[] = ['queued', 'extracting', 'roasting', 'rendering', 'done']

const INTENSITY_LABEL = { soft: 'Suave', medium: 'Medio', brutal: 'Brutal' } as const

export function RoastPage({ id, onNew }: { id: string; onNew: () => void }) {
  const state = useRoast(id)

  if (state.kind === 'loading') {
    return <Shell><p className="py-20 text-center text-ink-soft">Buscando tu trámite…</p></Shell>
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
    <Shell>
      {roast.status !== 'done' && <Progress status={roast.status} />}
      {roast.result && <Verdict roast={roast} result={roast.result} onNew={onNew} />}
    </Shell>
  )
}

function Shell({ children }: { children: ReactNode }) {
  return (
    <main className="mx-auto max-w-3xl px-4 pt-8 pb-20 sm:px-8 sm:pt-12">
      {children}
      <Footer />
    </main>
  )
}

function Progress({ status }: { status: Status }) {
  const current = ORDER.indexOf(status)
  return (
    <section aria-live="polite" className="mb-10 border-2 border-ink bg-sheet">
      <div className="border-b-2 border-ink px-5 py-3 sm:px-8">
        <h1 className="display text-3xl">Tu trámite está en proceso</h1>
      </div>
      <ol className="divide-y divide-rule">
        {STEPS.map((step) => {
          const idx = ORDER.indexOf(step.status)
          const done = current > idx
          const active = current === idx || (status === 'queued' && idx === 1)
          return (
            <li key={step.status} className="flex min-h-18 items-center justify-between gap-4 px-5 py-4 sm:px-8">
              <span className={`text-lg ${done || active ? 'text-ink' : 'text-ink-soft/50'}`}>
                {step.label}
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
  return (
    <article>
      <header className="relative border-b-2 border-ink pb-6">
        <p className="font-type text-ink-soft">
          Dictamen para <span className="text-ink">{result.name}</span>, intensidad {INTENSITY_LABEL[roast.intensity].toLowerCase()}
        </p>
        <h1 className="display mt-3 pr-28 text-[clamp(2.5rem,8vw,4.75rem)] sm:pr-40">{result.headline}</h1>
        <div className="absolute right-0 bottom-4 sm:bottom-6" aria-label={`Calificación: ${result.score} de 10`}>
          <Stamp animate tilt={-12} className="px-3 text-center text-[clamp(2.25rem,7vw,3.75rem)] leading-none">
            {result.score}/10
          </Stamp>
        </div>
      </header>

      <div className="mt-8 space-y-4 text-lg leading-relaxed">
        {result.roast.split(/\n+/).map((p, i) => (
          <p key={i}>{p}</p>
        ))}
      </div>

      <section className="mt-10 border-2 border-ink bg-sheet px-5 py-6 sm:px-8">
        <h2 className="display text-3xl">Ahora sí, en serio</h2>
        <ol className="mt-4 space-y-4">
          {result.tips.map((tip, i) => (
            <li key={i} className="flex gap-3 leading-relaxed">
              <span className="font-type font-bold text-stamp">{i + 1}.</span>
              <span>{tip}</span>
            </li>
          ))}
        </ol>
      </section>

      <section className="mt-10">
        <h2 className="sr-only">Tu certificado</h2>
        {roast.cardUrl ? (
          <img
            src={roast.cardUrl}
            alt={`Certificado de roast para ${result.name}: ${result.headline}, ${result.score}/10`}
            width={1200}
            height={630}
            className="stamp-in block h-auto w-full border-2 border-ink [--tilt:0deg]"
          />
        ) : (
          <div className="flex aspect-[1200/630] items-center justify-center border-2 border-dashed border-ink-soft/50 text-ink-soft">
            Imprimiendo tu certificado…
          </div>
        )}
      </section>

      {roast.status === 'done' && <ShareBar roast={roast} result={result} onNew={onNew} />}
    </article>
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

  const btn = 'border-2 border-ink px-4 py-2 font-semibold hover:bg-ink hover:text-sheet'
  return (
    <section className="mt-8 flex flex-col gap-4 border-t-2 border-ink pt-6">
      <div className="flex flex-wrap gap-2">
        <button type="button" onClick={copy} className={btn}>
          {copied ? 'Enlace copiado' : 'Copiar enlace'}
        </button>
        {'share' in navigator && (
          <button type="button" onClick={share} className={btn}>
            Compartir
          </button>
        )}
        {roast.cardUrl && (
          <a href={roast.cardUrl} download={`roastfolio-${roast.id}.jpg`} className={btn}>
            Descargar certificado
          </a>
        )}
        <button type="button" onClick={onNew} className={`${btn} bg-ink text-sheet hover:bg-stamp hover:border-stamp`}>
          Hacer otro roast
        </button>
      </div>
      <p className="text-sm text-ink-soft">Este roast y su enlace se borran en {hoursLeft(roast.expiresAt)}.</p>
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
          Los roasts se borran a las 24 horas, con todo y certificado. El tuyo todavía no existe.
        </p>
        <button type="button" onClick={onNew} className="display mt-8 bg-ink px-6 py-3 text-2xl text-sheet hover:bg-stamp">
          Hacer mi roast
        </button>
      </section>
    </Shell>
  )
}
