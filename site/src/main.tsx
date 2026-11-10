import { StrictMode } from 'react'
import { hydrateRoot } from 'react-dom/client'
import './styles/index.css'
import { App } from './App'

hydrateRoot(
  document.getElementById('root')!,
  <StrictMode>
    <App />
  </StrictMode>,
)
