import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.jsx'
// Imported after App so the chromatic overrides land last in the bundle.
import './styles/chromatic.css'
import { PreferencesProvider } from './context/PreferencesContext.jsx'

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <PreferencesProvider>
      <App />
    </PreferencesProvider>
  </StrictMode>,
)
