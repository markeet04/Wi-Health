import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.jsx'
// Imported after App so the chromatic overrides land last in the bundle.
import './styles/chromatic.css'
import { PreferencesProvider } from './context/PreferencesContext.jsx'
import KonamiEasterEgg from './components/KonamiEasterEgg/KonamiEasterEgg.jsx'

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <PreferencesProvider>
      <App />
      {/* Mounted beside App, not inside it, so the egg works on the boot screen
          and the login page too — App returns early for both. */}
      <KonamiEasterEgg />
    </PreferencesProvider>
  </StrictMode>,
)
