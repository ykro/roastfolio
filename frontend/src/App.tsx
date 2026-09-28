import { useEffect, useState } from 'react'
import { Home } from './Home'
import { RoastPage } from './RoastPage'

function roastIdFrom(path: string): string | null {
  const m = path.match(/^\/r\/([A-Za-z0-9_-]+)\/?$/)
  return m ? m[1] : null
}

export function App() {
  const [path, setPath] = useState(window.location.pathname)

  useEffect(() => {
    const onPop = () => setPath(window.location.pathname)
    window.addEventListener('popstate', onPop)
    return () => window.removeEventListener('popstate', onPop)
  }, [])

  function go(to: string) {
    window.history.pushState(null, '', to)
    setPath(to)
    window.scrollTo(0, 0)
  }

  const id = roastIdFrom(path)
  return (
    <>
      <nav className="mx-auto flex max-w-3xl items-center justify-between px-4 pt-5 sm:px-8">
        <a
          href="/"
          onClick={(e) => {
            e.preventDefault()
            go('/')
          }}
          className="display text-2xl"
        >
          Roastfolio
        </a>
      </nav>
      {id ? <RoastPage key={id} id={id} onNew={() => go('/')} /> : <Home onCreated={(rid) => go(`/r/${rid}`)} />}
    </>
  )
}
