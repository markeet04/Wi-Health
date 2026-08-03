import { useEffect, useRef } from 'react'

// The classic sequence. Letters are compared lowercased so Caps Lock or a held
// Shift doesn't quietly break the run.
const KONAMI = [
  'ArrowUp',
  'ArrowUp',
  'ArrowDown',
  'ArrowDown',
  'ArrowLeft',
  'ArrowRight',
  'ArrowLeft',
  'ArrowRight',
  'b',
  'a',
]

// Calls onUnlock when the Konami code is typed anywhere in the app.
export function useKonamiCode(onUnlock) {
  const progress = useRef(0)
  const handler = useRef(onUnlock)

  // Kept in a ref so a caller passing an inline arrow function doesn't rebind
  // the window listener on every render.
  useEffect(() => {
    handler.current = onUnlock
  }, [onUnlock])

  useEffect(() => {
    const handleKeyDown = (event) => {
      // Never read keys out of a field someone is typing or arrowing around in.
      const target = event.target
      const tag = target?.tagName
      if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || target?.isContentEditable) {
        return
      }

      const key = event.key.length === 1 ? event.key.toLowerCase() : event.key

      if (key === KONAMI[progress.current]) {
        progress.current += 1
        if (progress.current === KONAMI.length) {
          progress.current = 0
          handler.current?.()
        }
        return
      }

      // A wrong key can still be the first key of a fresh attempt — pressing
      // ArrowUp a third time should leave the run at 1, not throw it away.
      progress.current = key === KONAMI[0] ? 1 : 0
    }

    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [])
}
