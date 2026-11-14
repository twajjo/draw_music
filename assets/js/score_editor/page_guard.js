// The unsaved-changes guard: while there are unsaved changes, leaving the
// editor (closing or reloading the tab, the Back button, an in-app link)
// asks first.

const QUESTION = "Leave without saving your changes?"

export class PageGuard {
  // `dirty()`: whether there are unsaved changes now.
  constructor(dirty) {
    this.dirty = dirty
    this.guarded = false

    this.onBeforeUnload = (e) => {
      if (!this.dirty()) return
      e.preventDefault()
      e.returnValue = ""
    }
    // The Back button: while there are unsaved changes, a guard entry for
    // this same page sits on top of the history. Going back lands on the
    // page's own entry (same address, so LiveView does nothing) and asks.
    this.onPopState = () => {
      if (!this.guarded) return
      this.guarded = false
      if (confirm(QUESTION)) history.back()
      else this.sync()
    }
    this.onLinkClick = (e) => {
      const link = e.target.closest && e.target.closest("a[href]")
      if (!link || !this.dirty() || link.hasAttribute("download")) return
      if (!confirm(QUESTION)) {
        e.preventDefault()
        e.stopImmediatePropagation()
      }
    }
  }

  attach() {
    window.addEventListener("popstate", this.onPopState)
    window.addEventListener("beforeunload", this.onBeforeUnload)
    document.addEventListener("click", this.onLinkClick, true)
    this.sync()
  }

  detach() {
    window.removeEventListener("popstate", this.onPopState)
    window.removeEventListener("beforeunload", this.onBeforeUnload)
    document.removeEventListener("click", this.onLinkClick, true)
  }

  // Adds the history guard when changes become unsaved; removes it after a save.
  sync() {
    if (this.dirty() && !this.guarded) {
      history.pushState({drawMusicGuard: true}, "", location.href)
      this.guarded = true
    } else if (!this.dirty() && this.guarded) {
      this.guarded = false
      history.back()
    }
  }
}
