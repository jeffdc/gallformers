// AdminNav hook - marks the admin sidebar link for the current page with
// aria-current="page"; the design system styles it (.gf-sidenav in
// assets/css/system/components.css).
const AdminNav = {
  mounted() { this.mark() },
  updated() { this.mark() },
  mark() {
    const path = window.location.pathname
    this.el.querySelectorAll("[data-nav-href]").forEach(link => {
      const href = link.dataset.navHref
      const current = href === "/admin" ? path === "/admin" : path.startsWith(href)
      if (current) link.setAttribute("aria-current", "page")
      else link.removeAttribute("aria-current")
    })
  }
}

export default AdminNav
