// Tri-state checkbox: sets the indeterminate DOM property from data attribute
// (HTML has no attribute for indeterminate — it's JS-only)
const IndeterminateCheckbox = {
  mounted() { this.el.indeterminate = this.el.dataset.indeterminate === "true" },
  updated() { this.el.indeterminate = this.el.dataset.indeterminate === "true" }
}

export default IndeterminateCheckbox
