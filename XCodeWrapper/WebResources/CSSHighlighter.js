//
//  CSSHighlighter.swift
//  
//



import { debugLog } from "./DebugConfig.js";

/**
 * CSSHighlighter - Highlights text ranges using CSS custom highlights
 * instead of wrapping content in <span> elements (like SpanHighlighter).
 *
 * This is necessary for text fragment ranges because SpanHighlighter's
 * DOM mutations invalidate the cached Range objects held by
 * TextFragmentResolver.
 */
export class CSSHighlighter {
  #highlights = new Map();

  add(id, range, color) {
      this.remove(id);

      if (!range) {
        console.warn("[CSSHighlighter] add() called with null range");
        return;
      }

      try {
        const doc = range.startContainer.ownerDocument;
        const win = doc.defaultView;

        if (!win?.CSS?.highlights || !win?.Highlight) {
          console.warn("[CSSHighlighter] CSS Highlight API not available in this context");
          return;
        }



        const highlight = new win.Highlight(range);
        this.#highlights.set(id, { highlight, doc, win });
        win.CSS.highlights.set(id, highlight);

        this.#ensureStyle(doc, id, color);
      } catch (error) {
        console.error("[CSSHighlighter] Error adding highlight:", error);
      }
    }

  remove(id) {
     const entry = this.#highlights.get(id);
     if (!entry) return;

     entry.win?.CSS?.highlights?.delete(id);
     this.#highlights.delete(id);
   }


  removeAll() {
    for (const id of this.#highlights.keys()) {
      this.remove(id);
    }
  }

  updateColor(id, color) {
    const entry = this.#highlights.get(id);
    if (!entry) return;

    entry.color = color;

    for (const doc of this.#getDocsForHighlight(entry.highlight)) {
      this.#updateStyleInDoc(doc, id, color);
    }
  }

  #ensureStyle(doc, id, color) {
    const styleId = `css-highlight-style-${id}`;
    let style = doc.getElementById(styleId);

    if (!style) {
      style = doc.createElement('style');
      style.id = styleId;
      (doc.head || doc.documentElement).appendChild(style);
    }

    style.textContent = `::highlight(${id}) { color: ${color} !important; }`;
  }

  #updateStyleInDoc(doc, id, color) {
    const styleId = `css-highlight-style-${id}`;
    const style = doc.getElementById(styleId);
    if (style) {
      style.textContent = `::highlight(${id}) { color: ${color} !important; }`;
    }
  }

  #getDocsForHighlight(highlight) {
    const docs = new Set();
    for (const range of highlight) {
      const doc = range.startContainer?.ownerDocument;
      if (doc) docs.add(doc);
    }
    return docs;
  }
}
