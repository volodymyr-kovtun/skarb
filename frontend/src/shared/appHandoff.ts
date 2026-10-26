const APP_STATE_PREFIX = 'app:'

/**
 * Enable Banking returns every authorization to `/settings` — the one https redirect URL the
 * owner registered with it — including the ones started in the iPhone app. Those open the bank in
 * a browser sheet that holds no Skarb session, so this page could not finish them even if it
 * rendered: the sign-in screen would swallow the code. The server marks them with an `app:` state
 * (`EnableBankingState` in ConnectionEndpoints.cs), and they are handed to the app, query string
 * and all, before anything renders. The app completes the link with its own session.
 *
 * @returns true when the page was handed over and should not render itself.
 */
export function handOffToApp(location: Location = window.location): boolean {
  if (location.pathname !== '/settings') return false
  const state = new URLSearchParams(location.search).get('state')
  if (!state?.startsWith(APP_STATE_PREFIX)) return false
  location.replace(`skarb://enablebanking${location.search}`)
  return true
}

/**
 * What stays on screen if the hand-over goes nowhere — the link opened on a computer, say, where
 * no app answers to `skarb://`. Plain DOM, because none of the app is running to render it.
 */
export function renderHandoffNote(root: HTMLElement) {
  const note = document.createElement('p')
  note.textContent = 'Return to the Skarb app on your iPhone to finish linking your bank.'
  note.style.cssText = 'max-width:22rem;margin:30vh auto 0;padding:0 1.5rem;text-align:center;font:15px/1.5 system-ui,sans-serif'
  root.replaceChildren(note)
}
