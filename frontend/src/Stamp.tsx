import type { CSSProperties, ReactNode } from 'react'

export function Stamp({
  children,
  tilt = -8,
  animate = false,
  className = '',
}: {
  children: ReactNode
  tilt?: number
  animate?: boolean
  className?: string
}) {
  const style = { '--tilt': `${tilt}deg`, transform: `rotate(${tilt}deg)` } as CSSProperties
  return (
    <span className={`stamp ${animate ? 'stamp-in' : ''} ${className}`} style={style}>
      {children}
    </span>
  )
}
