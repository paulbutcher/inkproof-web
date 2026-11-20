// Copyright (c) 2026 Paul Butcher. All rights reserved.
// Released under Apache 2.0 license as described in the file LICENSE.
import lasm from '@lasm/cli/vite';
export default { root: 'web', plugins: [lasm()], build: { rollupOptions: { input: ['index.html', 'many.html', 'invalid.html', 'labelled.html', 'turned.html', 'tiles.html', 'accessible.html', 'replacing.html', 'inset.html', 'boxzoom.html', 'dragbox.html', 'grouped.html', 'cursor.html', 'select.html', 'buttons.html', 'cached.html', 'probe.html'].map(f => new URL('./web/' + f, import.meta.url).pathname) }, outDir: '../dist', emptyOutDir: true }, server: { fs: { allow: ['..'] } } };
