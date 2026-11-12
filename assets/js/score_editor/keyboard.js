// Keyboard helpers shared by the editor's hooks (the score's and the
// palette's), so they agree on when a key is theirs and what it is called.

// Typing in a form field: the editor's keys leave it alone.
export function typing(e) {
  return Boolean(e.target.closest && e.target.closest("input, textarea, select, [contenteditable]"))
}

// A dialog or the cheat-sheet is open: its own keys (Esc) handle it, so the
// editor's keys are off. Help is always on the page, shown and hidden in
// the browser.
export function dialogOpen() {
  if (document.querySelector("#settings-form, #save-as-form, #transpose-dialog, #tempo-dialog")) {
    return true
  }
  const help = document.getElementById("help")
  return Boolean(help && help.style.display !== "none")
}

// A key press as keys.json names it: "Ctrl+Z", "Shift+ArrowUp", "Space", "R".
// Modifiers only count where they change what the key does.
export function keyId(e) {
  const ctrl = e.ctrlKey || e.metaKey
  const name = e.key === " " ? "Space" : e.key.length === 1 ? e.key.toUpperCase() : e.key
  if (name === "ArrowUp" || name === "ArrowDown") return ctrl ? `Ctrl+${name}` : e.shiftKey ? `Shift+${name}` : name
  if (ctrl) return e.shiftKey ? `Ctrl+Shift+${name}` : `Ctrl+${name}`
  return name
}
