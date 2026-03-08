// AdminNav hook - highlights the active nav link based on the current URL path
const AdminNav = {
  mounted() { this.highlight() },
  updated() { this.highlight() },
  highlight() {
    const path = window.location.pathname
    this.el.querySelectorAll("[data-nav-href]").forEach(link => {
      const href = link.dataset.navHref
      const active = href === "/admin" ? path === "/admin" : path.startsWith(href)
      link.classList.toggle("opacity-50", !active)
      link.classList.toggle("underline", active)
      link.classList.toggle("underline-offset-4", active)
      link.classList.toggle("decoration-2", active)
    })
  }
}

export default AdminNav
