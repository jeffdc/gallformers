import { phenologyState, readPoints, applySelection } from './phenology_state'

// Owns the "· N in selection" count and the Clear-selection
// button. Both are pure client state — they only exist when the user
// has an active selection, which the server doesn't track — so the host is
// `phx-update="ignore"` and we render the inner DOM ourselves.
//
// The CSV link's brush-aware href is handled by a sibling hook on the
// link element itself (see phenology_csv_link.js) — that one has to be
// server-rendered because its existence depends on display mode + obs
// presence.

export default {
  mounted() {
    this._unsubscribe = phenologyState.subscribe(() => this.applyBrush())
    this.render()
  },

  destroyed() {
    if (this._unsubscribe) this._unsubscribe()
  },

  render() {
    this.el.innerHTML =
      '<span id="phenology-brush-count" ' +
        'style="display: none; color: #2b5e3a; font-weight: 600;"></span>' +
      '<button id="phenology-brush-clear" type="button" ' +
        'style="display: none; font-size: 11px; padding: 1px 8px; ' +
        'border: 1px solid #ccc; background: #fff; border-radius: 3px; ' +
        'cursor: pointer;">Clear selection</button>'

    this._countEl = this.el.querySelector('#phenology-brush-count')
    this._clearBtn = this.el.querySelector('#phenology-brush-clear')

    this._clearBtn.addEventListener('click', () => {
      // The chart hook listens for this and clears the SVG rect, which
      // publishes the cleared brush state for subscribers.
      document.dispatchEvent(new CustomEvent('phenology:clear-brush'))
    })

    this.applyBrush()
  },

  applyBrush() {
    const brush = phenologyState.brush

    if (!brush && phenologyState.selection.mode === 'click_drag') {
      this._countEl.style.display = 'none'
      this._countEl.textContent = ''
      this._clearBtn.style.display = 'none'
      return
    }

    const n = applySelection(readPoints()).length

    this._countEl.style.display = ''
    this._countEl.textContent = `· ${n} in selection`
    this._clearBtn.style.display = ''
  },
}
