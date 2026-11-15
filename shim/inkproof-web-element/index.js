// Copyright (c) 2026 Paul Butcher. All rights reserved.
// Released under Apache 2.0 license as described in the file LICENSE.
export function define(name, attributes, connected, disconnected, changed) {
  customElements.define(name, class extends HTMLElement {
    static get observedAttributes() { return attributes; }
    connectedCallback() { connected(this); }
    disconnectedCallback() { disconnected(this); }
    attributeChangedCallback(attribute, old, value) { changed(this, attribute, old, value); }
  });
}
