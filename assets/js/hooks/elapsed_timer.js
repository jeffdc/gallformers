const ElapsedTimer = {
  mounted() {
    this.startedAt = new Date(this.el.dataset.startedAt)
    this.timerEl = this.el.querySelector("[data-timer-display]")
    this.tick()
    this.interval = setInterval(() => this.tick(), 1000)

    this.handleEvent("stop_timer", () => {
      clearInterval(this.interval)
    })
  },

  destroyed() {
    clearInterval(this.interval)
  },

  tick() {
    const elapsed = Math.floor((Date.now() - this.startedAt) / 1000)
    const hours = Math.floor(elapsed / 3600)
    const minutes = Math.floor((elapsed % 3600) / 60)
    const seconds = elapsed % 60

    let display
    if (hours > 0) {
      display = `${hours}h ${String(minutes).padStart(2, "0")}m ${String(seconds).padStart(2, "0")}s`
    } else if (minutes > 0) {
      display = `${minutes}m ${String(seconds).padStart(2, "0")}s`
    } else {
      display = `${seconds}s`
    }

    this.timerEl.textContent = display
  }
}

export default ElapsedTimer
