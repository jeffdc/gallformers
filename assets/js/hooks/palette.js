// Palette hook (PaletteLive, the command palette; design system matter
// bc0d). `gf:open-palette` (the header's trigger, or `/` and `s` from
// search_shortcut.js) opens the palette. Enter in its search field follows
// the selected row (a click, so LiveView's own link handling applies), and
// the selected row is kept in view as the arrows move it.
//
// ↑ and ↓ move the selection (PaletteLive's phx-window-keydown), so in the
// search field their default is prevented: a text field's own ↑ moves the
// caret to the start (↓ to the end), and the next letters typed went in
// front of the query. The keys still bubble to the window.

const ARROWS = ['ArrowUp', 'ArrowDown']

const Palette = {
  mounted() {
    this.onOpen = () => this.pushEvent('open', {})
    this.onKeydown = (e) => {
      if (e.target.id !== 'palette-q') return
      if (ARROWS.includes(e.key)) return e.preventDefault()
      if (e.key !== 'Enter') return
      const row = this.el.querySelector('[aria-selected="true"]')
      if (!row) return
      e.preventDefault()
      row.click()
    }

    window.addEventListener('gf:open-palette', this.onOpen)
    this.el.addEventListener('keydown', this.onKeydown)
  },

  updated() {
    this.el.querySelector('[aria-selected="true"]')?.scrollIntoView?.({ block: 'nearest' })
  },

  destroyed() {
    window.removeEventListener('gf:open-palette', this.onOpen)
    this.el.removeEventListener('keydown', this.onKeydown)
  }
}

export default Palette
