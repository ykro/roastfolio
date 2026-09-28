import { useRef, useState, type FormEvent } from 'react'
import { ApiError, createRoast, type Intensity } from './api'
import { Stamp } from './Stamp'

const MAX_BYTES = 5 * 1024 * 1024

const LEVELS: { value: Intensity; label: string; note: string; tilt: number }[] = [
  { value: 'soft', label: 'Suave', note: 'Un amigo que te molesta con cariño. Arde poquito.', tilt: -4 },
  { value: 'medium', label: 'Medio', note: 'Un reclutador que ya leyó 400 CVs hoy. Sarcasmo seco.', tilt: 3 },
  { value: 'brutal', label: 'Brutal', note: 'Sin piedad con tus buzzwords. Cero consuelo.', tilt: -6 },
]

export function Home({ onCreated }: { onCreated: (id: string) => void }) {
  const [mode, setMode] = useState<'pdf' | 'url'>('pdf')
  const [pdf, setPdf] = useState<File | null>(null)
  const [url, setUrl] = useState('')
  const [intensity, setIntensity] = useState<Intensity>('medium')
  const [consent, setConsent] = useState(false)
  const [error, setError] = useState('')
  const [sending, setSending] = useState(false)
  const [dragging, setDragging] = useState(false)
  const fileInput = useRef<HTMLInputElement>(null)

  function pickFile(file: File | undefined) {
    setError('')
    if (!file) return
    if (file.type !== 'application/pdf' && !file.name.toLowerCase().endsWith('.pdf')) {
      return setError('El archivo tiene que ser un PDF.')
    }
    if (file.size > MAX_BYTES) return setError('El PDF pesa más de 5 MB.')
    setPdf(file)
  }

  async function submit(e: FormEvent) {
    e.preventDefault()
    setError('')
    if (mode === 'pdf' && !pdf) return setError('Elige el PDF de tu CV o de tu perfil de LinkedIn.')
    if (mode === 'url' && !url.trim()) return setError('Pega la URL de tu perfil de LinkedIn.')
    if (!consent) return setError('Marca la declaración para continuar.')
    setSending(true)
    try {
      const id = await createRoast({
        intensity,
        consent,
        pdf: mode === 'pdf' ? pdf : null,
        url: mode === 'url' ? url.trim() : undefined,
      })
      onCreated(id)
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Algo falló. Intenta de nuevo.')
      setSending(false)
    }
  }

  const level = LEVELS.find((l) => l.value === intensity)!

  return (
    <main className="mx-auto grid max-w-6xl gap-x-14 px-4 pb-16 sm:px-8 lg:grid-cols-[minmax(0,1fr)_minmax(0,33rem)] xl:gap-x-20">
      <section className="pt-8 pb-8 sm:pt-12 lg:pt-16">
        <h1 className="display text-[clamp(2.75rem,9vw,5.25rem)] text-ink">Tu perfil profesional, revisado sin piedad.</h1>
        <p className="mt-5 max-w-lg text-lg leading-relaxed text-ink-soft">
          Sube tu CV o pega tu LinkedIn. Te devolvemos un roast que cita tu propio perfil, una calificación del 1 al 10,
          tres correcciones listas para copiar y un certificado para presumir. Todo se borra a las 24 horas.
        </p>
      </section>

      <form
        onSubmit={submit}
        noValidate
        className="self-start border-2 border-ink bg-sheet lg:sticky lg:top-6 lg:col-start-2 lg:row-span-2 lg:row-start-1 lg:mt-16"
      >
        <div className="flex items-baseline justify-between gap-3 border-b-2 border-ink px-5 py-3 sm:px-7">
          <span className="display text-2xl">Solicitud de roast</span>
          <span className="font-type text-sm text-ink-soft">Formulario R-24</span>
        </div>

        <fieldset className="border-b border-rule px-5 py-6 sm:px-7">
          <legend className="sr-only">Documento</legend>
          <FieldTitle n={1}>¿Qué vamos a revisar?</FieldTitle>
          <div role="tablist" aria-label="Tipo de documento" className="mt-4 grid grid-cols-2 gap-1">
            {(['pdf', 'url'] as const).map((m) => (
              <button
                key={m}
                type="button"
                role="tab"
                aria-selected={mode === m}
                onClick={() => {
                  setMode(m)
                  setError('')
                }}
                className={`rounded-t-md border-2 border-b-0 px-3 py-2 font-semibold transition-colors ${
                  mode === m ? 'border-ink bg-manila text-ink' : 'border-rule bg-transparent text-ink-soft hover:text-ink'
                }`}
              >
                {m === 'pdf' ? 'PDF de tu CV' : 'URL de LinkedIn'}
              </button>
            ))}
          </div>
          <div className="border-2 border-ink bg-manila/35 p-3 sm:p-4">
            {mode === 'pdf' ? (
              <div
                onDragOver={(e) => {
                  e.preventDefault()
                  setDragging(true)
                }}
                onDragLeave={() => setDragging(false)}
                onDrop={(e) => {
                  e.preventDefault()
                  setDragging(false)
                  pickFile(e.dataTransfer.files[0])
                }}
                onClick={() => fileInput.current?.click()}
                className={`flex cursor-pointer flex-col items-center gap-2 border-2 border-dashed px-4 py-6 text-center transition-colors ${
                  dragging ? 'border-stamp bg-sheet' : pdf ? 'border-ink bg-sheet/60' : 'border-ink-soft/50 hover:border-ink'
                }`}
              >
                <input
                  ref={fileInput}
                  type="file"
                  accept="application/pdf,.pdf"
                  className="sr-only"
                  aria-label="PDF de tu CV"
                  onChange={(e) => pickFile(e.target.files?.[0])}
                />
                {pdf ? (
                  <>
                    <p className="font-type text-lg break-all">{pdf.name}</p>
                    <span className="text-sm text-ink-soft">{(pdf.size / 1024).toFixed(0)} KB · toca para cambiarlo</span>
                  </>
                ) : (
                  <>
                    <span className="border-2 border-ink bg-sheet px-4 py-1.5 font-semibold">Elegir PDF</span>
                    <span className="text-sm text-ink-soft">
                      <span className="hidden sm:inline">o arrástralo aquí. </span>Máximo 5 MB y 5 páginas.
                    </span>
                  </>
                )}
              </div>
            ) : (
              <label className="block px-1 py-2">
                <span className="text-ink-soft">Tu perfil público de LinkedIn</span>
                <input
                  type="url"
                  inputMode="url"
                  autoComplete="url"
                  autoCapitalize="none"
                  spellCheck={false}
                  placeholder="linkedin.com/in/tu-usuario"
                  value={url}
                  onChange={(e) => setUrl(e.target.value)}
                  className="ruled mt-1 block w-full bg-transparent font-type text-xl outline-none placeholder:text-ink-soft/50"
                />
              </label>
            )}
          </div>
          <p className="mt-3 text-sm text-ink-soft">
            {mode === 'pdf'
              ? '¿Solo tienes LinkedIn? En tu perfil, abre “Más” y elige “Guardar en PDF”. Es la opción más rápida.'
              : 'El perfil tiene que ser público. Leer LinkedIn toma unos 30 segundos más que un PDF.'}
          </p>
        </fieldset>

        <fieldset className="border-b border-rule px-5 py-6 sm:px-7">
          <legend className="sr-only">Intensidad</legend>
          <FieldTitle n={2}>¿Qué tan fuerte?</FieldTitle>
          <div className="mt-4 grid grid-cols-3 gap-2">
            {LEVELS.map((l) => {
              const on = intensity === l.value
              return (
                <label
                  key={l.value}
                  className={`flex cursor-pointer items-center justify-center border-2 px-1 py-3 transition-colors has-[:focus-visible]:outline-3 has-[:focus-visible]:outline-offset-3 has-[:focus-visible]:outline-stamp ${
                    on ? 'border-stamp bg-sheet' : 'border-rule hover:border-ink-soft'
                  }`}
                >
                  <input
                    type="radio"
                    name="intensity"
                    value={l.value}
                    checked={on}
                    onChange={() => setIntensity(l.value)}
                    className="sr-only"
                  />
                  <span className={on ? '' : 'opacity-35 grayscale'}>
                    <Stamp tilt={l.tilt} className="text-xl sm:text-2xl">
                      {l.label}
                    </Stamp>
                  </span>
                </label>
              )
            })}
          </div>
          <p aria-live="polite" className="mt-3 min-h-6 text-ink-soft">
            {level.note}
          </p>
        </fieldset>

        <fieldset className="px-5 py-6 sm:px-7">
          <legend className="sr-only">Declaración</legend>
          <label className="flex cursor-pointer items-start gap-3">
            <input
              type="checkbox"
              checked={consent}
              onChange={(e) => setConsent(e.target.checked)}
              className="mt-0.5 size-5 shrink-0 accent-stamp"
            />
            <span>Es mi perfil, o la persona me dio permiso de roastearlo. Entiendo que el roast es público por 24 horas.</span>
          </label>
        </fieldset>

        <div className="border-t-2 border-ink px-5 py-5 sm:px-7">
          {error && (
            <p role="alert" className="mb-4 border-l-4 border-stamp bg-stamp/8 px-3 py-2 font-medium text-stamp">
              {error}
            </p>
          )}
          <button
            type="submit"
            disabled={sending}
            className="display w-full bg-ink px-6 py-4 text-3xl text-sheet transition-colors hover:bg-stamp disabled:cursor-wait disabled:opacity-70"
          >
            {sending ? 'Enviando…' : 'Roastear mi perfil'}
          </button>
          <p className="mt-3 text-center text-sm text-ink-soft">
            Listo en unos {mode === 'pdf' ? '25' : '50'} segundos.
          </p>
        </div>
      </form>

      <figure className="mt-10 lg:col-start-1 lg:row-start-2 lg:mt-0">
        <img
          src="/muestra.jpg"
          alt="Muestra: certificado de roast para María Fernanda López, 'Gurú certificada en buzzwords sin resultados', 3 de 10"
          width={1200}
          height={630}
          className="block h-auto w-full border-2 border-ink shadow-[4px_4px_0_var(--color-ink)] lg:-rotate-1 lg:shadow-[6px_6px_0_var(--color-ink)]"
        />
        <figcaption className="mt-4 text-sm text-ink-soft">
          Certificado de muestra de un perfil inventado, intensidad brutal. El tuyo sale con tu titular y tu nota.
        </figcaption>
      </figure>

      <Footer className="lg:col-start-1" />
    </main>
  )
}

function FieldTitle({ n, children }: { n: number; children: string }) {
  return (
    <h2 className="flex items-baseline gap-3 text-xl font-bold">
      <span className="font-type text-base text-ink-soft">{n}.</span>
      {children}
    </h2>
  )
}

export function Footer({ className = '' }: { className?: string }) {
  return (
    <footer className={`mt-12 max-w-xl text-sm leading-relaxed text-ink-soft ${className}`}>
      Roastfolio es una demo del curso de Cloud. Tu perfil se procesa en Google Cloud y se borra a las 24 horas; nadie lo
      revisa a mano.
    </footer>
  )
}
