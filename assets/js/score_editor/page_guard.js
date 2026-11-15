// The unsaved-changes guard: while there are unsaved changes, leaving the
// editor (the Back button, an in-app link such as New or Compositions) asks
// first, in the editor's own dialog (#unsaved-dialog, from
// EditorComponents.unsaved_dialog), which says the changes will be lost.
// Closing or reloading the tab gets the browser's own question, the only
// one a browser allows there.

export class PageGuard {
  // `dirty()`: whether there are unsaved changes now.
  constructor(dirty) {
    this.dirty = dirty
    this.guarded = false
    // Set once the user has chosen to leave, so nothing asks again.
    this.leaving = false

    this.onBeforeUnload = (e) => {
      if (this.leaving || !this.dirty()) return
      e.preventDefault()
      e.returnValue = ""
    }
    // The Back button: while there are unsaved changes, a guard entry for
    // this same page sits on top of the history. Going back lands on the
    // page's own entry (same address, so LiveView does nothing) and asks.
    this.onPopState = () => {
      if (!this.guarded) return
      this.guarded = false
      this.ask(
        () => history.back(),
        () => this.sync(),
      )
    }
    // A link out is held back while the dialog asks; leaving follows it.
    this.onLinkClick = (e) => {
      const link = e.target.closest && e.target.closest("a[href]")
      if (this.leaving || !link || !this.dirty() || link.hasAttribute("download")) return
      // A patch stays in the editor (e.g. closing the Preferences panel).
      if (link.dataset.phxLink === "patch") return
      e.preventDefault()
      e.stopImmediatePropagation()
      this.ask(
        () => link.click(),
        () => {},
      )
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

  // Opens the dialog; `leave` or `stay` runs on the answer. Stay is the
  // default: its button has the focus, and Esc means it too.
  ask(leave, stay) {
    const dialog = document.getElementById("unsaved-dialog")
    if (!dialog) return confirm("Leave without saving? Your changes will be lost.") ? this.leave(leave) : stay()

    const answer = (choice) => {
      dialog.removeEventListener("cancel", onCancel)
      dialog.querySelector("#unsaved-leave").removeEventListener("click", onLeave)
      dialog.querySelector("#unsaved-stay").removeEventListener("click", onStay)
      dialog.close()
      choice()
    }
    const onLeave = () => {
      answer(() => this.leave(leave))
    }
    const onStay = () => {
      answer(stay)
    }
    const onCancel = (e) => {
      e.preventDefault()
      answer(stay)
    }

    dialog.addEventListener("cancel", onCancel)
    dialog.querySelector("#unsaved-leave").addEventListener("click", onLeave)
    dialog.querySelector("#unsaved-stay").addEventListener("click", onStay)
    dialog.showModal()
  }

  leave(go) {
    this.leaving = true
    go()
  }
}
