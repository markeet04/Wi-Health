import { useEffect, useRef, useState } from 'react'
import './KonamiEasterEgg.css'
import { useKonamiCode } from '../../hooks/useKonamiCode'

// Served straight from public/ rather than imported, so the 7 MB file is never
// pulled into the JS bundle and isn't fetched at all until the egg is unlocked.
const VIDEO_SRC = '/easter-egg.mp4'

function KonamiEasterEgg() {
  const [isOpen, setIsOpen] = useState(false)
  const [isMuted, setIsMuted] = useState(false)
  const videoRef = useRef(null)

  useKonamiCode(() => setIsOpen(true))

  // Escape closes, and the page behind is frozen so scrolling the overlay
  // doesn't scroll the dashboard underneath it.
  useEffect(() => {
    if (!isOpen) return undefined

    const handleKeyDown = (event) => {
      if (event.key === 'Escape') setIsOpen(false)
    }
    window.addEventListener('keydown', handleKeyDown)

    const previousOverflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'

    return () => {
      window.removeEventListener('keydown', handleKeyDown)
      document.body.style.overflow = previousOverflow
    }
  }, [isOpen])

  // Browsers block audio on media the user hasn't clearly interacted with.
  // Keystrokes usually count, but when they don't, play() rejects — fall back to
  // muted playback and offer a sound button rather than showing a frozen frame.
  useEffect(() => {
    if (!isOpen) return

    const video = videoRef.current
    if (!video) return

    video.currentTime = 0
    video.muted = false
    setIsMuted(false)

    video.play().catch(() => {
      video.muted = true
      setIsMuted(true)
      video.play().catch(() => {})
    })
  }, [isOpen])

  if (!isOpen) return null

  const close = () => setIsOpen(false)

  const enableSound = (event) => {
    event.stopPropagation()
    const video = videoRef.current
    if (!video) return
    video.muted = false
    setIsMuted(false)
  }

  return (
    <div className="konami" role="dialog" aria-modal="true" aria-label="Easter egg" onClick={close}>
      <video
        ref={videoRef}
        className="konami__video"
        src={VIDEO_SRC}
        preload="auto"
        playsInline
        onEnded={close}
      />

      {/* The controls live in positioned wrappers rather than being positioned
          themselves: the chromatic theme sets `position: relative` on every
          button at a specificity these classes can't outrank, which would drag
          them out of the corners. */}
      <div className="konami__corner">
        <button type="button" className="konami__close" onClick={close} aria-label="Close video">
          ✕
        </button>
      </div>

      <div className="konami__footer">
        {isMuted ? (
          <button type="button" className="konami__sound" onClick={enableSound}>
            Click for sound
          </button>
        ) : null}
        <p className="konami__hint">Esc or click anywhere to close</p>
      </div>
    </div>
  )
}

export default KonamiEasterEgg
