// The site theme (design system, matter bc0d; docs/design-system/foundations.md,
// "Dark mode"). A chosen theme is saved as "gf-theme" ("light" or "dark") and
// set as data-theme on <html>; with none saved the page follows the OS
// setting (no data-theme). data-theme-choice ("system", "light", "dark")
// tells the theme switch what to show. The root layout's #theme-init script
// does what applyTheme does, before the page paints.

const KEY = "gf-theme"
const THEMES = ["light", "dark"]

function saved(storage) {
  try {
    const value = storage.getItem(KEY)
    return THEMES.includes(value) ? value : null
  } catch (_e) {
    return null
  }
}

function apply(root, theme) {
  if (theme) root.dataset.theme = theme
  else root.removeAttribute("data-theme")
  root.dataset.themeChoice = theme || "system"
}

export function syncThemeOptions(doc = document) {
  const choice = doc.documentElement.dataset.themeChoice || "system"
  doc.querySelectorAll("[data-theme-option]").forEach(option => {
    option.setAttribute("aria-checked", String(option.dataset.themeOption === choice))
  })
}

export function applyTheme(root = document.documentElement, storage = window.localStorage) {
  apply(root, saved(storage))
}

export function setTheme(choice, root = document.documentElement, storage = window.localStorage) {
  const theme = THEMES.includes(choice) ? choice : null
  try {
    if (theme) storage.setItem(KEY, theme)
    else storage.removeItem(KEY)
  } catch (_e) {
    // Private mode: the choice holds for this page only.
  }
  apply(root, theme)
  syncThemeOptions(root.ownerDocument)
}

// The theme switch's options dispatch "gf:set-theme" with {theme}.
export function listen(win = window) {
  win.addEventListener("gf:set-theme", e => setTheme(e.detail.theme))
  // LiveView re-renders the header on navigation; check the right option again.
  win.addEventListener("phx:page-loading-stop", () => syncThemeOptions())
  syncThemeOptions()
}
