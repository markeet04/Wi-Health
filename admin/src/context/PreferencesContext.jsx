import { createContext, useContext, useEffect, useMemo, useState } from 'react'

// App-wide UI preferences (theme + font scale), persisted to localStorage and
// applied to the <html> element so every screen picks them up via CSS:
//   theme      -> data-theme="light|dark" (resolved from light/dark/system)
//   fontScale  -> --font-scale multiplier consumed by index.css
const THEME_KEY = 'wi-netra-admin-theme'

const THEMES = ['light', 'dark', 'system']
const FONT_KEY = 'wi-netra-admin-font-scale'

const FONT_MIN = 0.85
const FONT_MAX = 1.3
const FONT_STEP = 0.05
const FONT_DEFAULT = 1

const clampFont = (value) => Math.min(FONT_MAX, Math.max(FONT_MIN, Math.round(value * 100) / 100))

const PreferencesContext = createContext(null)

function readTheme() {
  const stored = localStorage.getItem(THEME_KEY)
  return THEMES.includes(stored) ? stored : 'system'
}

function readFontScale() {
  const stored = Number(localStorage.getItem(FONT_KEY))
  return Number.isFinite(stored) && stored > 0 ? clampFont(stored) : FONT_DEFAULT
}

// Resolve to the base palette the CSS variables build on. 'system' follows the OS.
function resolveTheme(theme) {
  if (theme === 'system') {
    return window.matchMedia?.('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'
  }
  return theme
}

export function PreferencesProvider({ children }) {
  const [theme, setThemeState] = useState(readTheme)
  const [fontScale, setFontScaleState] = useState(readFontScale)

  // Apply the resolved theme to <html> and keep it in sync if the OS theme
  // changes while 'system' is selected.
  useEffect(() => {
    const apply = () => {
      document.documentElement.setAttribute('data-theme', resolveTheme(theme))
    }
    apply()

    if (theme !== 'system' || !window.matchMedia) return undefined
    const media = window.matchMedia('(prefers-color-scheme: dark)')
    media.addEventListener('change', apply)
    return () => media.removeEventListener('change', apply)
  }, [theme])

  useEffect(() => {
    document.documentElement.style.setProperty('--font-scale', String(fontScale))
  }, [fontScale])

  const value = useMemo(() => ({
    theme,
    fontScale,
    fontMin: FONT_MIN,
    fontMax: FONT_MAX,
    fontDefault: FONT_DEFAULT,
    setTheme: (next) => {
      setThemeState(next)
      localStorage.setItem(THEME_KEY, next)
    },
    increaseFont: () => setFontScaleState((current) => {
      const next = clampFont(current + FONT_STEP)
      localStorage.setItem(FONT_KEY, String(next))
      return next
    }),
    decreaseFont: () => setFontScaleState((current) => {
      const next = clampFont(current - FONT_STEP)
      localStorage.setItem(FONT_KEY, String(next))
      return next
    }),
    resetFont: () => {
      setFontScaleState(FONT_DEFAULT)
      localStorage.setItem(FONT_KEY, String(FONT_DEFAULT))
    },
  }), [theme, fontScale])

  return <PreferencesContext.Provider value={value}>{children}</PreferencesContext.Provider>
}

// eslint-disable-next-line react-refresh/only-export-components
export function usePreferences() {
  const context = useContext(PreferencesContext)
  if (!context) {
    throw new Error('usePreferences must be used within a PreferencesProvider')
  }
  return context
}
