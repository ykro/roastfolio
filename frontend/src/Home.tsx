import { useRef, useState, type FormEvent } from 'react'
import { ApiError, createRoast, type Intensity } from './api'
import { Stamp } from './Stamp'

const MAX_BYTES = 5 * 1024 * 1024

const LEVELS: { value: Intensity; label: string; note: string; tilt: number }[] = [
  { value: 'soft', label: 'Suave', note: 'Un amigo que te molesta con cariño.', tilt: -4 },
  { value: 'medium', label: 'Medio', note: 'Un reclutador cansado con buen humor.', tilt: 3 },
  { value: 'brutal', label: 'Brutal', note: 'Sin piedad con tus buzzwords.', tilt: -6 },
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

  return (
    <main className="mx-auto max-w-3xl px-4 pb-20 sm:px-8">
      <section className="pt-10 pb-10 sm:pt-16">
        <h1 className="display text-[clamp(3rem,11vw,6.5rem)] text-ink">
          Tu perfil profesional, revisado sin piedad.
        </h1>
        <p className="mt-6 max-w-xl text-lg leading-relaxed text-ink-soft">
          Sube tu CV o tu perfil de LinkedIn. Te devolvemos un roast con humor, una calificación del 1 al 10 y tres
          consejos que sí sirven. Todo se borra a las 24 horas.
        </p>
      </section>

      <form onSubmit={submit} noValidate className="border-2 border-ink bg-sheet">
        <div className="flex items-baseline justify-between border-b-2 border-ink px-5 py-3 sm:px-8">
          <span className="display text-2xl">Solicitud de roast</span>
          <span className="font-type text-sm text-ink-soft">Formulario R-24</span>
        </div>

        <fieldset className="border-b border-rule px-5 py-7 sm:px-8">
          <legend className="sr-only">Documento</legend>
          <FieldTitle n={1}>¿Qué vamos a revisar?</FieldTitle>
          <div role="tablist" aria-label="Tipo de documento" className="mt-4 flex gap-1">
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
                className={`rounded-t-md border-2 border-b-0 px-4 py-2 font-semibold transition-colors ${
                  mode === m ? 'border-ink bg-manila text-ink' : 'border-rule bg-transparent text-ink-soft hover:text-ink'
                }`}
              >
                {m === 'pdf' ? 'PDF de tu CV' : 'URL de LinkedIn'}
              </button>
            ))}
          </div>
          <div className="border-2 border-ink bg-manila/35 p-4 sm:p-5">
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
                className={`flex flex-col items-start gap-3 border-2 border-dashed p-5 ${
                  dragging ? 'border-stamp bg-sheet' : 'border-ink-soft/50'
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
                  <p className="font-type text-lg break-all">{pdf.name}</p>
                ) : (
                  <p className="text-ink-soft">Arrastra tu PDF aquí. Máximo 5 MB y 5 páginas.</p>
                )}
                <button
                  type="button"
                  onClick={() => fileInput.current?.click()}
                  className="border-2 border-ink px-4 py-1.5 font-semibold hover:bg-ink hover:text-sheet"
                >
                  {pdf ? 'Cambiar archivo' : 'Elegir archivo'}
                </button>
                <p className="text-sm text-ink-soft">
                  ¿Solo tienes LinkedIn? En tu perfil, abre “Más” y elige “Guardar en PDF”.
                </p>
              </div>
            ) : (
              <label className="block">
                <span className="text-ink-soft">Tu perfil público de LinkedIn</span>
                <input
                  type="url"
                  inputMode="url"
                  autoComplete="url"
                  placeholder="linkedin.com/in/tu-usuario"
                  value={url}
                  onChange={(e) => setUrl(e.target.value)}
                  className="ruled mt-1 block w-full bg-transparent font-type text-xl outline-none placeholder:text-ink-soft/50"
                />
              </label>
            )}
          </div>
        </fieldset>

        <fieldset className="border-b border-rule px-5 py-7 sm:px-8">
          <legend className="sr-only">Intensidad</legend>
          <FieldTitle n={2}>¿Qué tan fuerte?</FieldTitle>
          <div className="mt-5 grid gap-3 sm:grid-cols-3">
            {LEVELS.map((l) => {
              const on = intensity === l.value
              return (
                <label
                  key={l.value}
                  className={`relative flex cursor-pointer flex-col gap-3 border-2 p-4 transition-colors has-[:focus-visible]:outline-3 has-[:focus-visible]:outline-offset-3 has-[:focus-visible]:outline-stamp ${
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
                    <Stamp tilt={l.tilt} className="text-2xl">
                      {l.label}
                    </Stamp>
                  </span>
                  <span className="text-sm text-ink-soft">{l.note}</span>
                </label>
              )
            })}
          </div>
        </fieldset>

        <fieldset className="px-5 py-7 sm:px-8">
          <legend className="sr-only">Declaración</legend>
          <FieldTitle n={3}>Declaración</FieldTitle>
          <label className="mt-4 flex cursor-pointer items-start gap-3">
            <input
              type="checkbox"
              checked={consent}
              onChange={(e) => setConsent(e.target.checked)}
              className="mt-1 size-5 shrink-0 accent-stamp"
            />
            <span>Es mi perfil, o la persona me dio permiso de roastearlo. Entiendo que el roast es público por 24 horas.</span>
          </label>
        </fieldset>

        <div className="border-t-2 border-ink px-5 py-6 sm:px-8">
          {error && (
            <p role="alert" className="mb-4 border-l-4 border-stamp bg-stamp/8 px-3 py-2 font-medium text-stamp">
              {error}
            </p>
          )}
          <button
            type="submit"
            disabled={sending}
            className="display w-full bg-ink px-6 py-4 text-3xl text-sheet transition-colors hover:bg-stamp disabled:cursor-wait disabled:opacity-70 sm:w-auto"
          >
            {sending ? 'Enviando…' : 'Roastear mi perfil'}
          </button>
        </div>
      </form>

      <Footer />
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

export function Footer() {
  return (
    <footer className="mt-12 max-w-xl text-sm leading-relaxed text-ink-soft">
      Roastfolio es una demo del curso de Cloud. Tu perfil se procesa en Google Cloud y se borra a las 24 horas; nadie lo
      revisa a mano.
    </footer>
  )
}
