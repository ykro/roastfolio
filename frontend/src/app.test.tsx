import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import { Home } from './Home'
import { RoastPage } from './RoastPage'

const result = {
  name: 'María López',
  headline: 'Mucha sinergia, poca evidencia',
  roast: 'Tu perfil tiene más buzzwords que un pitch.',
  score: 4,
  tips: ['Consejo uno', 'Consejo dos', 'Consejo tres'],
}
const base = { id: 'abcdefghijklmnopqrstuv', intensity: 'brutal', source: 'pdf', expiresAt: new Date(Date.now() + 86_400_000).toISOString() }

function mockFetch(...responses: { status: number; body?: unknown }[]) {
  const fn = vi.fn()
  for (const r of responses) {
    fn.mockResolvedValueOnce(new Response(r.body === undefined ? null : JSON.stringify(r.body), { status: r.status }))
  }
  vi.stubGlobal('fetch', fn)
  return fn
}

describe('Home', () => {
  it('requires consent before sending', async () => {
    const fetch = mockFetch()
    render(<Home onCreated={() => {}} />)
    await userEvent.click(screen.getByRole('tab', { name: 'URL de LinkedIn' }))
    await userEvent.type(screen.getByPlaceholderText('linkedin.com/in/tu-usuario'), 'linkedin.com/in/ykro')
    await userEvent.click(screen.getByRole('button', { name: 'Roastear mi perfil' }))
    expect(screen.getByRole('alert')).toHaveTextContent('Marca la declaración')
    expect(fetch).not.toHaveBeenCalled()
  })

  it('sends a LinkedIn URL and reports the new id', async () => {
    const fetch = mockFetch({ status: 201, body: { id: 'newid' } })
    const onCreated = vi.fn()
    render(<Home onCreated={onCreated} />)
    await userEvent.click(screen.getByRole('tab', { name: 'URL de LinkedIn' }))
    await userEvent.type(screen.getByPlaceholderText('linkedin.com/in/tu-usuario'), 'linkedin.com/in/ykro')
    await userEvent.click(screen.getByText('Brutal'))
    await userEvent.click(screen.getByRole('checkbox'))
    await userEvent.click(screen.getByRole('button', { name: 'Roastear mi perfil' }))
    await waitFor(() => expect(onCreated).toHaveBeenCalledWith('newid'))
    const body = fetch.mock.calls[0][1].body as FormData
    expect(body.get('intensity')).toBe('brutal')
    expect(body.get('url')).toBe('linkedin.com/in/ykro')
    expect(body.get('consent')).toBe('true')
  })

  it('explains the Cloud Armor rate limit', async () => {
    mockFetch({ status: 429 })
    render(<Home onCreated={() => {}} />)
    await userEvent.click(screen.getByRole('tab', { name: 'URL de LinkedIn' }))
    await userEvent.type(screen.getByPlaceholderText('linkedin.com/in/tu-usuario'), 'linkedin.com/in/ykro')
    await userEvent.click(screen.getByRole('checkbox'))
    await userEvent.click(screen.getByRole('button', { name: 'Roastear mi perfil' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('5 roasts cada 10 minutos')
  })

  it('rejects files that are not PDFs', async () => {
    render(<Home onCreated={() => {}} />)
    const file = new File(['hola'], 'cv.docx', { type: 'application/msword' })
    await userEvent.upload(screen.getByLabelText('PDF de tu CV'), file, { applyAccept: false })
    expect(screen.getByRole('alert')).toHaveTextContent('tiene que ser un PDF')
  })
})

describe('RoastPage', () => {
  it('shows the roast while the card is still rendering, then the card', async () => {
    mockFetch(
      { status: 200, body: { ...base, status: 'rendering', result } },
      { status: 200, body: { ...base, status: 'done', result, cardUrl: '/cards/x.jpg' } },
    )
    render(<RoastPage id={base.id} onNew={() => {}} />)
    expect(await screen.findByText('Mucha sinergia, poca evidencia')).toBeInTheDocument()
    expect(screen.getByText('Imprimiendo tu certificado…')).toBeInTheDocument()
    expect(screen.getByText('Tu trámite está en proceso')).toBeInTheDocument()
    expect(await screen.findByRole('img', {}, { timeout: 4000 })).toHaveAttribute('src', '/cards/x.jpg')
    expect(screen.getByText('Consejo tres')).toBeInTheDocument()
    expect(screen.getByLabelText('Calificación: 4 de 10')).toBeInTheDocument()
    expect(screen.queryByText('Tu trámite está en proceso')).not.toBeInTheDocument()
  })

  it('shows the expired state for a missing roast', async () => {
    mockFetch({ status: 404, body: { detail: 'expired' } })
    render(<RoastPage id={base.id} onNew={() => {}} />)
    expect(await screen.findByText('Este roast ya expiró')).toBeInTheDocument()
  })

  it('shows the failure message from the worker', async () => {
    mockFetch({ status: 200, body: { ...base, status: 'failed', error: 'No encontramos ese perfil de LinkedIn o no es público.' } })
    render(<RoastPage id={base.id} onNew={() => {}} />)
    expect(await screen.findByRole('alert')).toHaveTextContent('No encontramos ese perfil')
  })
})
