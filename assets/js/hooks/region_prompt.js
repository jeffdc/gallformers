// RegionPrompt hook for the contextual first-visit modal on scoped pages
const RegionPrompt = {
  mounted() {
    const hasContinent = localStorage.getItem("gf_continent")
    const dismissed = localStorage.getItem("gf_continent_dismissed")

    if (!hasContinent && !dismissed) {
      this.el.classList.remove("hidden")
    }

    // Selection from the prompt saves to localStorage and dismisses
    this.el.querySelectorAll("[data-prompt-code]").forEach(btn => {
      btn.addEventListener("click", () => {
        const code = btn.dataset.promptCode
        if (code === "") {
          localStorage.setItem("gf_continent_dismissed", "true")
        } else {
          localStorage.setItem("gf_continent", code)
          localStorage.setItem("gf_continent_dismissed", "true")
        }
        this.el.classList.add("hidden")
      })
    })
  }
}

export default RegionPrompt
