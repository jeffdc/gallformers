// SourceReader hook: the review pages' reader panel (review_reader, matter d213).
// On opening it brings the question's first quoted block into view; when the
// question or the find changes, the first match (or, with no find, the first
// quoted block). The server marks the blocks and the matches.
const SourceReader = {
  mounted() {
    this.find = this.el.dataset.find || ""
    this.cited = this.el.dataset.cited || ""
    this.reveal()
  },
  updated() {
    const find = this.el.dataset.find || ""
    const cited = this.el.dataset.cited || ""
    if (find === this.find && cited === this.cited) return
    this.find = find
    this.cited = cited
    this.reveal()
  },
  reveal() {
    const target = (this.find && this.el.querySelector("mark")) || this.el.querySelector("[data-cited]")
    if (target) target.scrollIntoView({block: "center"})
  }
}

export default SourceReader
