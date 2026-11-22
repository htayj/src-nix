// Handle gg in the page so a single g never becomes a prefix in a text field.
(() => {
  let pending = false;
  const reset = () => { pending = false; };
  document.addEventListener("keydown", (event) => {
    const editing = event.composedPath().some((element) =>
      element.isContentEditable ||
      ["INPUT", "TEXTAREA", "SELECT"].includes(element.tagName));
    if (editing || event.ctrlKey || event.altKey || event.metaKey ||
        event.shiftKey || event.isComposing || event.key !== "g") {
      reset();
      return;
    }
    if (event.repeat) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    if (pending) window.scrollTo({top: 0, behavior: "instant"});
    pending = !pending;
  }, true);
  document.addEventListener("pointerdown", reset, true);
  document.addEventListener("focusin", reset, true);
  document.addEventListener("nyxt-page-key-reset", reset);
  window.addEventListener("blur", reset);
})();
