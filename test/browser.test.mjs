// Copyright (c) 2026 Paul Butcher. All rights reserved.
// Released under Apache 2.0 license as described in the file LICENSE.
// Browser tests: the built chart element in headless Chromium.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { chromium } from 'playwright';
import { preview } from 'vite';

let server, browser, base;

before(async () => {
  server = await preview({ root: 'web', build: { outDir: '../dist' }, preview: { port: 0, host: '127.0.0.1' } });
  base = server.resolvedUrls.local[0];
  browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
});

after(async () => {
  await browser?.close();
  await server?.close();
});

// Records every draw the chart announces, and every WebGL2 context the page asks for.
const instrument = () => {
  window.draws = [];
  window.errors = [];
  window.contexts = [];
  addEventListener('inkproof-draw', e => window.draws.push(e.detail));
  addEventListener('inkproof-error', e => window.errors.push(e.detail.message));
  window.measurements = 0;
  window.zeroTimeouts = 0;
  const set = window.setTimeout;
  window.setTimeout = function (fn, ms, ...rest) { if (ms === 0 && fn.name !== 'tick') window.zeroTimeouts++; return set.call(this, fn, ms, ...rest); };
  const measureText = CanvasRenderingContext2D.prototype.measureText;
  CanvasRenderingContext2D.prototype.measureText = function (...args) { window.measurements++; return measureText.apply(this, args); };
  window.uploads = 0;
  const bufferData = WebGL2RenderingContext.prototype.bufferData;
  WebGL2RenderingContext.prototype.bufferData = function (...args) { window.uploads++; return bufferData.apply(this, args); };
  const getContext = HTMLCanvasElement.prototype.getContext;
  HTMLCanvasElement.prototype.getContext = function (kind, ...rest) {
    const context = getContext.call(this, kind, ...rest);
    if (kind === 'webgl2') window.contexts.push(context);
    return context;
  };
};

const open = async (path, options = {}) => {
  const context = await browser.newContext(options);
  await context.addInitScript(instrument);
  const page = await context.newPage();
  const messages = [];
  page.on('console', m => messages.push({ type: m.type(), text: m.text() }));
  await page.goto(base + path);
  return { page, context, messages };
};

const drawn = (page, n) => page.waitForFunction(count => window.draws.length >= count, n);
const settle = page => page.evaluate(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(() => setTimeout(r, 100)))));
const pixel = page => page.evaluate(() => {
  const canvas = document.querySelector('inkproof-chart').shadowRoot.querySelector('canvas');
  const { width, height } = canvas;
  const d = canvas.getContext('2d').getImageData(width >> 1, height >> 1, 1, 1).data;
  return { width, height, rgba: [...d] };
});

test('a plain page with only the element draws the command list', async () => {
  const { page, context } = await open('/index.html');
  await drawn(page, 1);
  const { width, height, rgba } = await pixel(page);
  assert.deepEqual([width, height], [400, 200]);
  assert.deepEqual(rgba, [255, 128, 0, 255]);
  await context.close();
});

test('a triangle is drawn from the command list', async () => {
  const { page, context } = await open('/index.html');
  await drawn(page, 1);
  const { width, height } = await pixel(page);
  const at = await page.evaluate(([x, y]) => {
    const canvas = document.querySelector('inkproof-chart').shadowRoot.querySelector('canvas');
    return [...canvas.getContext('2d').getImageData(x, y, 1, 1).data];
  }, [width >> 3, height >> 1]);
  assert.deepEqual(at, [0, 0, 255, 255]);
  await context.close();
});

test('a scissor command clips the draw', async () => {
  const { page, context, messages } = await open('/index.html');
  await drawn(page, 1);
  const at = await page.evaluate(([x, y]) => {
    const canvas = document.querySelector('inkproof-chart').shadowRoot.querySelector('canvas');
    return [...canvas.getContext('2d').getImageData(x, y, 1, 1).data];
  }, [150, 190]);
  assert.deepEqual(at, [255, 128, 0, 255]);
  assert.deepEqual(await page.evaluate(() => window.errors), []);
  await context.close();
});

test('nothing is redrawn when nothing changed', async () => {
  const { page, context } = await open('/index.html');
  await drawn(page, 1);
  await settle(page);
  const before = await page.evaluate(() => window.draws.length);
  await settle(page);
  await settle(page);
  assert.equal(await page.evaluate(() => window.draws.length), before);
  await context.close();
});

test('a resize redraws at the new size', async () => {
  const { page, context } = await open('/index.html');
  await drawn(page, 1);
  await page.evaluate(() => { document.querySelector('inkproof-chart').style.width = '300px'; });
  await drawn(page, 2);
  const { width, rgba } = await pixel(page);
  assert.equal(width, 300);
  assert.deepEqual(rgba, [255, 128, 0, 255]);
  await context.close();
});

test('the backing store follows the device pixel ratio', async () => {
  const { page, context } = await open('/index.html', { deviceScaleFactor: 2 });
  await drawn(page, 1);
  const { width, height } = await pixel(page);
  assert.deepEqual([width, height], [800, 400]);
  const cdp = await context.newCDPSession(page);
  await cdp.send('Emulation.setDeviceMetricsOverride', { width: 800, height: 600, deviceScaleFactor: 3, mobile: false });
  await page.waitForFunction(() => document.querySelector('inkproof-chart').shadowRoot.querySelector('canvas').width === 1200);
  assert.deepEqual(await pixel(page).then(p => p.rgba), [255, 128, 0, 255]);
  await context.close();
});

test('many charts share one WebGL2 context', async () => {
  const { page, context } = await open('/many.html');
  await drawn(page, 3);
  assert.equal(await page.evaluate(() => window.contexts.length), 1);
  const colours = await page.evaluate(() => [...document.querySelectorAll('inkproof-chart')].map(el => {
    const c = el.shadowRoot.querySelector('canvas');
    return [...c.getContext('2d').getImageData(c.width >> 1, c.height >> 1, 1, 1).data];
  }));
  for (const rgba of colours) assert.deepEqual(rgba, [255, 128, 0, 255]);
  await context.close();
});

test('a lost context is recovered without a reload and is logged', async () => {
  const { page, context, messages } = await open('/index.html');
  await drawn(page, 1);
  await page.evaluate(() => { window.lose = window.contexts[0].getExtension('WEBGL_lose_context'); window.lose.loseContext(); });
  await page.waitForFunction(() => window.contexts[0].isContextLost());
  await page.evaluate(() => window.lose.restoreContext());
  await drawn(page, 2);
  assert.deepEqual(await pixel(page).then(p => p.rgba), [255, 128, 0, 255]);
  const warnings = messages.filter(m => m.type === 'warning').map(m => m.text);
  assert.ok(warnings.some(t => t.includes('context lost')), warnings.join('\n'));
  assert.ok(warnings.some(t => t.includes('context restored')), warnings.join('\n'));
  await context.close();
});

const at = (page, x, y) => page.evaluate(([x, y]) => {
  const c = document.querySelector('inkproof-chart').shadowRoot.querySelector('canvas');
  return [...c.getContext('2d').getImageData(x, y, 1, 1).data];
}, [x, y]);
const load = async (page, src) => {
  const n = await page.evaluate(() => window.draws.length);
  await page.evaluate(src => document.querySelector('inkproof-chart').setAttribute('src', src), src);
  await drawn(page, n + 1);
};

test('a list drawing buffers an earlier list uploaded draws them without a re-upload', async () => {
  const { page, context } = await open('/index.html');
  await drawn(page, 1);
  const first = [await at(page, 10, 190), await at(page, 300, 100)];
  await load(page, 'reuse.bin');
  assert.deepEqual([await at(page, 10, 190), await at(page, 300, 100)], first);
  assert.notDeepEqual(first[0], first[1]);
  assert.deepEqual(await page.evaluate(() => window.errors), []);
  await context.close();
});

test('after a lost context the earlier uploads are reported gone and a fresh list draws', async () => {
  const { page, context } = await open('/index.html');
  await drawn(page, 1);
  await page.evaluate(() => {
    window.restored = [];
    addEventListener('inkproof-contextrestored', e => window.restored.push(e.detail.generation));
    window.lose = window.contexts[0].getExtension('WEBGL_lose_context');
    window.lose.loseContext();
  });
  await page.waitForFunction(() => window.contexts[0].isContextLost());
  await page.evaluate(() => window.lose.restoreContext());
  await drawn(page, 2);
  assert.deepEqual(await page.evaluate(() => window.restored), [1]);
  await load(page, 'chart.bin');
  assert.deepEqual(await at(page, 10, 190), [0, 0, 255, 255]);
  assert.deepEqual(await at(page, 300, 100), [255, 128, 0, 255]);
  await context.close();
});

test('a chart added after the last one was removed draws from a fresh state', async () => {
  const { page, context } = await open('/index.html');
  await drawn(page, 1);
  await page.evaluate(() => document.querySelector('inkproof-chart').remove());
  const n = await page.evaluate(() => window.draws.length);
  await page.evaluate(() => {
    const el = document.createElement('inkproof-chart');
    el.setAttribute('src', 'chart.bin');
    document.body.append(el);
  });
  await drawn(page, n + 1);
  assert.deepEqual(await at(page, 10, 190), [0, 0, 255, 255]);
  assert.deepEqual(await at(page, 300, 100), [255, 128, 0, 255]);
  assert.deepEqual(await page.evaluate(() => window.errors), []);
  await context.close();
});

test('invalid attributes are reported, not defaulted', async () => {
  const { page, context, messages } = await open('/invalid.html');
  await page.waitForFunction(() => window.errors.length >= 2);
  const errors = await page.evaluate(() => window.errors);
  assert.ok(errors.some(e => e.includes('src is missing')), errors.join('\n'));
  assert.ok(errors.some(e => e.includes('log-level')), errors.join('\n'));
  assert.ok(messages.some(m => m.type === 'warning' && m.text.includes('src is missing')));
  await context.close();
});

test('the console stays quiet below warn and while idle', async () => {
  const { page, context, messages } = await open('/index.html');
  await drawn(page, 1);
  await settle(page);
  await settle(page);
  assert.deepEqual(messages.filter(m => m.text.includes('[inkproof')), []);
  await context.close();
});

test('labels from Axis are drawn over the data layer and measured once', async () => {
  const { page, context } = await open('/labelled.html');
  await drawn(page, 1);
  const canvasInk = () => page.evaluate(() => {
    const c = document.querySelector('inkproof-labelled-chart').shadowRoot.querySelector('canvas');
    const data = c.getContext('2d').getImageData(0, 0, c.width, c.height).data;
    let ink = 0;
    for (let i = 0; i < data.length; i += 4) if (data[i] !== 255 || data[i + 1] !== 128) ink++;
    return ink;
  });
  assert.ok(await canvasInk() > 0, 'no text over the data layer');
  const measured = () => page.evaluate(() => window.measurements);
  const first = await measured();
  assert.equal(first, 10);
  await page.evaluate(() => document.querySelector('inkproof-labelled-chart').setAttribute('src', 'chart.bin?again'));
  await drawn(page, 2);
  assert.equal(await measured(), first);
  await context.close();
});

test('labels are aligned on their anchor and turned about it', async () => {
  const { page, context } = await open('/turned.html');
  await drawn(page, 1);
  const boxes = await page.evaluate(() => {
    const c = document.querySelector('inkproof-turned-chart').shadowRoot.querySelector('canvas');
    const k = c.width / 400;
    const data = c.getContext('2d').getImageData(0, 0, c.width, c.height).data;
    const box = () => ({ x0: Infinity, x1: -Infinity, y0: Infinity, y1: -Infinity });
    const out = [box(), box()];
    for (let y = 0; y < c.height; y++) for (let x = 0; x < c.width; x++) {
      const i = (y * c.width + x) * 4;
      if (data[i] > 90 || data[i + 1] > 90 || data[i + 2] > 90) continue;
      const b = out[x < c.width / 2 ? 0 : 1];
      b.x0 = Math.min(b.x0, x / k); b.x1 = Math.max(b.x1, x / k);
      b.y0 = Math.min(b.y0, y / k); b.y1 = Math.max(b.y1, y / k);
    }
    return out;
  });
  const [flat, turned] = boxes;
  assert.ok(flat.x1 - flat.x0 > flat.y1 - flat.y0, 'horizontal text is not wider than tall');
  assert.ok(flat.x0 < 100 && 100 < flat.x1, 'centred text does not straddle its anchor');
  assert.ok(turned.y1 - turned.y0 > turned.x1 - turned.x0, 'turned text is not taller than wide');
  assert.ok(turned.y0 >= 99, 'text ending at its anchor extends past it');
  await context.close();
});

test('a tile query sums the tiles it touches and leaves the main thread free', async () => {
  const { page, context, messages } = await open('/tiles.html');
  const requests = [];
  page.on('request', r => requests.push(r.url()));
  await page.evaluate(() => { window.ticks = 0; const tick = () => { window.ticks++; setTimeout(tick, 0); }; tick(); });
  await page.waitForFunction(() => document.body.hasAttribute('done'));
  const attrs = await page.evaluate(() => ({ sum: document.body.getAttribute('sum'), missing: document.body.getAttribute('missing'), range: document.body.getAttribute('range'), columns: document.body.getAttribute('columns'), raw: document.body.getAttribute('raw'), cached: document.body.getAttribute('cached'), yields: document.body.getAttribute('yields'), shared: document.body.getAttribute('shared'), ms: Object.fromEntries(['tUncached', 'tCached', 'tMany', 'tPlain', 'tDraw'].map(n => [n, Number(document.body.getAttribute(n))])), ticks: window.ticks }));
  let expected = 0;
  for (let i = 2; i < 14; i++) expected += i * 3 + 1;
  assert.equal(attrs.sum, String(expected));
  assert.match(attrs.missing, /^error/);
  assert.equal(attrs.range, 'true');
  const columns = [];
  for (let c = 0; c < 4; c++) { let sum = 0; for (let i = 2 + 3 * c; i < 5 + 3 * c; i++) sum += i * 3 + 1; columns.push(sum); }
  assert.equal(attrs.columns, `#[${columns.join(', ')}]`);
  const leafSum = (a, b) => { let sum = 0; for (let i = a; i < Math.min(b, 16); i++) sum += i * 3 + 1; return sum; };
  assert.equal(attrs.raw, `#[${leafSum(10, 13)}, ${leafSum(13, 16)}, ${leafSum(16, 20)}]`);
  assert.ok(attrs.ms.tUncached < 50 && attrs.ms.tCached < 50, `a query over 4 tiles waits idle: ${JSON.stringify(attrs.ms)}`);
  assert.ok(attrs.ms.tMany < 400, `eight concurrent queries over 120 tiles wait idle: ${JSON.stringify(attrs.ms)}`);
  assert.ok(attrs.ms.tDraw < 1.5 * attrs.ms.tPlain, `eight charts of four stations over a shared cache take longer than plain fetches: ${JSON.stringify(attrs.ms)}`);
  assert.ok(attrs.ticks > 0);
  assert.ok(Number(attrs.yields) < 30, `a cached query over 120 tiles yielded ${attrs.yields} times, once per tile rather than per 8 ms of work`);
  const fetched = tag => requests.filter(u => u.endsWith('?' + tag)).map(u => u.split('/').pop());
  const total = (a, b) => { let sum = 0; for (let i = a; i < b; i++) sum += i * 3 + 1; return sum; };
  assert.equal(attrs.cached, `${total(2, 14)} #[${columns.join(', ')}] ${total(2, 14)}`);
  const once = fetched('cached');
  assert.deepEqual([...once].sort(), ['0.bin?cached', '1.bin?cached', '2.bin?cached', '3.bin?cached'], 'one fetch per tile across three queries');
  assert.equal(attrs.shared, `#[${Array(6).fill(total(2, 14)).join(', ')}]`);
  assert.deepEqual([...fetched('shared')].sort(), ['0.bin?shared', '1.bin?shared', '2.bin?shared', '3.bin?shared'], 'six concurrent queries fetch each tile once');
  assert.equal(fetched('small').length, 4, 'a one-tile cache evicts: tiles 1 and 2 are fetched again by the second query');
  assert.equal(fetched('bad').length, 2, 'a failed tile is not cached');
  assert.ok(messages.filter(m => m.text.includes('tiles/4.bin?bad')).length >= 2, 'a failed tile is logged each time');
  assert.ok(messages.some(m => m.type === 'warning' && m.text.includes('fetching a tile failed') && m.text.includes('tiles/4.bin')), JSON.stringify(messages));
  await context.close();
});

const keyed = async (page, ...keys) => {
  await page.evaluate(() => {
    window.views = []; window.cursors = [];
    const el = document.querySelector('inkproof-accessible-chart, inkproof-replacing-chart, inkproof-inset-chart');
    el.addEventListener('inkproof-view', e => window.views.push(e.detail));
    el.addEventListener('inkproof-cursor', e => window.cursors.push(e.detail));
  });
  await page.locator('inkproof-accessible-chart, inkproof-replacing-chart, inkproof-inset-chart').focus();
  for (const key of keys) await page.keyboard.press(key);
};
const announced = page => page.evaluate(() => document.querySelector('inkproof-accessible-chart').shadowRoot.querySelector('[aria-live]').textContent);

test('the chart can be focused and zoomed and panned from the keyboard alone', async () => {
  const { page, context } = await open('/accessible.html');
  await drawn(page, 1);
  await page.keyboard.press('Tab');
  assert.equal(await page.evaluate(() => document.activeElement.localName), 'inkproof-accessible-chart');
  await keyed(page, '+');
  let [view] = await page.evaluate(() => window.views);
  assert.ok(view.xEnd - view.xStart < 100, 'zoom in narrows the range');
  await keyed(page, 'ArrowRight');
  const views = await page.evaluate(() => window.views);
  assert.ok(views.at(-1).xStart > 0, 'pan right moves the range');
  await keyed(page, '-', 'Escape');
  assert.deepEqual((await page.evaluate(() => window.views)).at(-1), { xStart: 0, xEnd: 100, yStart: 0, yEnd: 100 });
  await context.close();
});

test('the cursor moves within the points and the series is selectable from the keyboard', async () => {
  const { page, context } = await open('/accessible.html');
  await drawn(page, 1);
  await keyed(page, 'Shift+ArrowRight', 'Shift+ArrowRight', 'End', 'Shift+ArrowRight');
  let cursors = await page.evaluate(() => window.cursors);
  assert.deepEqual(cursors.map(c => c.point), [1, 2, 4]);
  await keyed(page, 'Home', 'Shift+ArrowLeft', 'PageDown');
  cursors = await page.evaluate(() => window.cursors);
  assert.deepEqual(cursors.at(-1), { series: 1, point: 0 });
  assert.match(await announced(page), /South/);
  await keyed(page, 'PageDown');
  assert.equal((await page.evaluate(() => window.cursors)).at(-1).series, 0);
  await context.close();
});

test('keys the chart does not use are left to the browser', async () => {
  const { page, context } = await open('/accessible.html');
  await drawn(page, 1);
  await keyed(page);
  const prevented = await page.evaluate(() => new Promise(resolve => {
    const el = document.querySelector('inkproof-accessible-chart');
    const event = new KeyboardEvent('keydown', { key: 'Tab', cancelable: true });
    el.dispatchEvent(event);
    resolve(event.defaultPrevented);
  }));
  assert.equal(prevented, false);
  await context.close();
});

test('the chart has an accessible name and a summary naming its series and range', async () => {
  const { page, context } = await open('/accessible.html');
  await drawn(page, 1);
  await page.waitForFunction(() => document.querySelector('inkproof-accessible-chart').hasAttribute('aria-description'));
  const cdp = await context.newCDPSession(page);
  const { nodes } = await cdp.send('Accessibility.getFullAXTree');
  const chart = nodes.find(n => n.name?.value === 'Sales');
  assert.ok(chart, 'no accessible node named Sales');
  assert.match(chart.description?.value ?? '', /North.*South.*0 to 100/);
  await keyed(page, '+');
  assert.match(await page.evaluate(() => document.querySelector('inkproof-accessible-chart').getAttribute('aria-description')), /showing 25 to 75/);
  await context.close();
});

test('the data is available as a table that can be shown', async () => {
  const { page, context } = await open('/accessible.html');
  await drawn(page, 1);
  const cells = () => page.evaluate(() => [...document.querySelector('inkproof-accessible-chart').shadowRoot.querySelectorAll('table td')].map(c => c.textContent));
  assert.deepEqual(await cells(), ['Jan', '1', '2', 'Feb', '3', '4']);
  const shown = () => page.evaluate(() => { const t = document.querySelector('inkproof-accessible-chart').shadowRoot.querySelector('table').parentElement; return t.getBoundingClientRect().height > 2; });
  assert.equal(await shown(), false);
  await page.evaluate(() => document.querySelector('inkproof-accessible-chart').setAttribute('show-table', ''));
  assert.equal(await shown(), true);
  await context.close();
});

const gesture = async (page, steps) => {
  await page.evaluate(() => {
    window.views = []; window.pointers = [];
    const el = document.querySelector('inkproof-accessible-chart, inkproof-replacing-chart, inkproof-inset-chart');
    el.addEventListener('inkproof-view', e => window.views.push(e.detail));
    el.addEventListener('inkproof-pointer', e => window.pointers.push(e.detail));
  });
  await page.evaluate(steps => {
    const el = document.querySelector('inkproof-accessible-chart, inkproof-replacing-chart, inkproof-inset-chart');
    const rect = el.getBoundingClientRect();
    for (const [type, init] of steps) {
      const { x, y, ...rest } = init;
      const options = { bubbles: true, cancelable: true, clientX: rect.left + x, clientY: rect.top + y, pointerType: 'touch', isPrimary: true, ...rest };
      el.dispatchEvent(type === 'wheel' ? new WheelEvent(type, options) : new PointerEvent(type, options));
    }
  }, steps);
};
const lastView = page => page.evaluate(() => window.views.at(-1));

test('the wheel zooms about the pointer and keeps the data under it', async () => {
  const { page, context } = await open('/accessible.html');
  await drawn(page, 1);
  await gesture(page, [['wheel', { x: 100, y: 100, deltaY: -200 }]]);
  const view = await lastView(page);
  assert.ok(view.xEnd - view.xStart < 100, 'wheel up zooms in');
  const under = view.xStart + (view.xEnd - view.xStart) * 100 / 400;
  assert.ok(Math.abs(under - 25) < 1e-6, 'the data under the pointer stays under it');
  await gesture(page, [['wheel', { x: 100, y: 100, deltaY: 100000 }]]);
  assert.deepEqual(await lastView(page), { xStart: 0, xEnd: 100, yStart: 0, yEnd: 100 }, 'zoom out stops at the limit');
  await context.close();
});

test('positions are taken from the plot, which is inset in the element', async () => {
  const { page, context } = await open('/inset.html');
  await drawn(page, 1);
  await gesture(page, [['wheel', { x: 60 + 200, y: 20 + 100, deltaY: -200 }]]);
  const view = await lastView(page);
  assert.ok(Math.abs((view.xStart + view.xEnd) / 2 - 50) < 1e-6, 'a wheel at the plot centre zooms about the centre of the range');
  assert.ok(Math.abs((view.yStart + view.yEnd) / 2 - 50) < 1e-6);
  await gesture(page, [['pointermove', { x: 60, y: 20, pointerId: 1 }]]);
  const top = await page.evaluate(() => window.pointers.at(-1));
  assert.ok(top, 'the plot top left reports a position');
  await gesture(page, [['pointermove', { x: 30, y: 100, pointerId: 1 }]]);
  assert.equal(await page.evaluate(() => window.pointers.length), 0, 'over the axis labels nothing is reported');
  await gesture(page, [['wheel', { x: 30, y: 100, deltaY: -200 }], ['pointerdown', { x: 30, y: 100, pointerId: 2 }], ['pointermove', { x: 90, y: 100, pointerId: 2 }]]);
  assert.equal((await page.evaluate(() => window.views)).length, 0, 'outside the plot no gesture starts');
  await context.close();
});

test('dragging pans the view with the content', async () => {
  const { page, context } = await open('/accessible.html');
  await drawn(page, 1);
  await keyed(page, '+');
  const before = await lastView(page);
  await gesture(page, [['pointerdown', { x: 200, y: 100, pointerId: 1 }], ['pointermove', { x: 240, y: 100, pointerId: 1 }], ['pointerup', { x: 240, y: 100, pointerId: 1 }]]);
  const after = await lastView(page);
  assert.ok(after.xStart < before.xStart, 'dragging right moves the content right, so the range moves left');
  assert.equal(after.xEnd - after.xStart, before.xEnd - before.xStart);
  assert.equal(after.yStart, before.yStart);
  await context.close();
});

test('shift-dragging zooms to the box, and a tiny one does nothing', async () => {
  const { page, context } = await open('/accessible.html');
  await drawn(page, 1);
  await gesture(page, [['pointerdown', { x: 100, y: 50, pointerId: 1, shiftKey: true }], ['pointermove', { x: 200, y: 100, pointerId: 1 }], ['pointerup', { x: 200, y: 100, pointerId: 1 }]]);
  const view = await lastView(page);
  assert.ok(Math.abs(view.xStart - 25) < 1e-6 && Math.abs(view.xEnd - 50) < 1e-6);
  assert.ok(Math.abs(view.yStart - 50) < 1e-6 && Math.abs(view.yEnd - 75) < 1e-6, 'screen y grows downward, data y upward');
  await gesture(page, [['pointerdown', { x: 100, y: 50, pointerId: 1, shiftKey: true }], ['pointerup', { x: 101, y: 51, pointerId: 1 }]]);
  assert.equal(await lastView(page), undefined);
  await context.close();
});

test('a box zoom set to x changes only x, and a drag shorter than box-min changes nothing', async () => {
  const { page, context } = await open('/boxzoom.html');
  await drawn(page, 1);
  await gesture(page, [['pointerdown', { x: 100, y: 50, pointerId: 1, shiftKey: true }], ['pointerup', { x: 105, y: 150, pointerId: 1 }]]);
  assert.equal(await lastView(page), undefined, 'a drag under 10 px along x does nothing');
  await gesture(page, [['pointerdown', { x: 100, y: 50, pointerId: 1, shiftKey: true }], ['pointerup', { x: 200, y: 60, pointerId: 1 }]]);
  const view = await lastView(page);
  assert.ok(Math.abs(view.xStart - 25) < 1e-6 && Math.abs(view.xEnd - 50) < 1e-6);
  assert.ok(Math.abs(view.yStart) < 1e-6 && Math.abs(view.yEnd - 100) < 1e-6, 'y keeps its range');
  await context.close();
});

test('with drag=box a plain drag zooms to the box and shift-drag pans', async () => {
  const { page, context } = await open('/dragbox.html');
  await drawn(page, 1);
  await gesture(page, [['pointerdown', { x: 100, y: 50, pointerId: 1 }], ['pointermove', { x: 200, y: 100, pointerId: 1 }], ['pointerup', { x: 200, y: 100, pointerId: 1 }]]);
  const view = await lastView(page);
  assert.ok(Math.abs(view.xStart - 25) < 1e-6 && Math.abs(view.xEnd - 50) < 1e-6);
  await gesture(page, [['pointerdown', { x: 200, y: 100, pointerId: 1, shiftKey: true }], ['pointermove', { x: 240, y: 100, pointerId: 1 }], ['pointerup', { x: 240, y: 100, pointerId: 1 }]]);
  const panned = await lastView(page);
  assert.ok(panned.xStart < view.xStart, 'shift-drag pans');
  assert.equal(panned.xEnd - panned.xStart, view.xEnd - view.xStart);
  await context.close();
});

test('two fingers pinch to zoom and pan', async () => {
  const { page, context } = await open('/accessible.html');
  await drawn(page, 1);
  await gesture(page, [
    ['pointerdown', { x: 150, y: 100, pointerId: 1 }], ['pointerdown', { x: 250, y: 100, pointerId: 2 }],
    ['pointermove', { x: 100, y: 100, pointerId: 1 }], ['pointermove', { x: 300, y: 100, pointerId: 2 }]]);
  const zoomed = await lastView(page);
  assert.ok(zoomed.xEnd - zoomed.xStart < 100, 'fingers moving apart zoom in');
  assert.ok(zoomed.xStart > 0 && zoomed.xEnd < 100);
  await gesture(page, [['pointermove', { x: 140, y: 100, pointerId: 1 }], ['pointermove', { x: 340, y: 100, pointerId: 2 }]]);
  const panned = await lastView(page);
  assert.ok(panned.xStart < zoomed.xStart, 'both fingers moving right drags the content right');
  await context.close();
});

test('the data position under the pointer is reported, and nothing is while it is outside', async () => {
  const { page, context } = await open('/accessible.html');
  await drawn(page, 1);
  await gesture(page, [['pointermove', { x: 100, y: 50, pointerId: 1, pointerType: 'mouse' }], ['pointermove', { x: 500, y: 50, pointerId: 1, pointerType: 'mouse' }]]);
  const pointers = await page.evaluate(() => window.pointers);
  assert.equal(pointers.length, 1);
  assert.ok(Math.abs(pointers[0].x - 25) < 1e-6 && Math.abs(pointers[0].y - 75) < 1e-6);
  await context.close();
});

test('replacing the scene keeps the view, and a reset returns to home', async () => {
  const { page, context, messages } = await open('/replacing.html');
  await drawn(page, 1);
  const n = await page.evaluate(() => window.draws.length);
  await gesture(page, [['wheel', { x: 100, y: 100, deltaY: -200 }]]);
  const first = await lastView(page);
  await drawn(page, n + 1);
  await gesture(page, [['wheel', { x: 100, y: 100, deltaY: -200 }]]);
  const second = await lastView(page);
  assert.ok(second.xEnd - second.xStart < first.xEnd - first.xStart, 'the next wheel step continues from the zoomed view');
  await page.evaluate(() => document.querySelector('inkproof-replacing-chart').dispatchEvent(new Event('test-reset')));
  assert.deepEqual(await lastView(page), { xStart: 0, xEnd: 100, yStart: 0, yEnd: 100 });
  assert.deepEqual(await page.evaluate(() => window.errors), []);
  assert.deepEqual(messages.filter(m => m.type === 'error' || m.type === 'warning'), []);
  await context.close();
});

test('charts in one group follow each other in x, and one that leaves stops following', async () => {
  const { page, context } = await open('/grouped.html');
  await drawn(page, 2);
  const wheel = id => page.evaluate(id => {
    const el = document.getElementById(id);
    const rect = el.getBoundingClientRect();
    el.dispatchEvent(new WheelEvent('wheel', { bubbles: true, cancelable: true, clientX: rect.left + 100, clientY: rect.top + 100, deltaY: -200 }));
  }, id);
  const watch = () => page.evaluate(() => {
    window.seen = { a: [], b: [] };
    for (const id of ['a', 'b']) document.getElementById(id).addEventListener('inkproof-view', e => window.seen[id].push(e.detail));
  });
  await watch();
  await wheel('a');
  const [a, b] = await page.evaluate(() => [window.seen.a.at(-1), window.seen.b.at(-1)]);
  assert.ok(a.xEnd - a.xStart < 100, 'the wheel zoomed a');
  assert.equal(b.xStart, a.xStart);
  assert.equal(b.xEnd, a.xEnd);
  assert.equal(b.yEnd - b.yStart, 100, 'y stays with the chart');
  await page.evaluate(() => document.getElementById('b').removeAttribute('group'));
  await watch();
  await wheel('a');
  assert.equal(await page.evaluate(() => window.seen.b.length), 0, 'an unlinked chart does not follow');
  await page.evaluate(() => document.getElementById('b').setAttribute('group', 'g'));
  const joined = await page.evaluate(() => window.seen.b.at(-1));
  const now = await page.evaluate(() => window.seen.a.at(-1));
  assert.equal(joined.xStart, now.xStart, 'relinking takes the group x range');
  await context.close();
});

test('a cursor follows the pointer and shows on the other charts of its group', async () => {
  const { page, context } = await open('/cursor.html');
  await drawn(page, 2);
  const read = id => page.evaluate(id => {
    const canvas = document.getElementById(id).shadowRoot.querySelector('canvas');
    return [...canvas.getContext('2d').getImageData(100, 5, 1, 1).data];
  }, id);
  const point = (id, type) => page.evaluate(([id, type]) => {
    const el = document.getElementById(id);
    const rect = el.getBoundingClientRect();
    el.dispatchEvent(new PointerEvent(type, { pointerId: 1, clientX: rect.left + 100, clientY: rect.top + 100 }));
  }, [id, type]);
  const before = { a: await read('a'), b: await read('b') };
  await point('a', 'pointermove');
  await settle(page);
  assert.notDeepEqual(await read('a'), before.a, 'the chart under the pointer draws the cursor');
  assert.notDeepEqual(await read('b'), before.b, 'the other chart in the group draws it too');
  const legendB = () => page.evaluate(() =>
    [...document.getElementById('b').shadowRoot.querySelectorAll('.legend .readout, .legend button')].map(e => e.textContent));
  assert.match((await legendB())[0], /^x: /, 'the legend of the other chart reads the cursor');
  await point('a', 'pointerleave');
  await settle(page);
  assert.deepEqual(await read('b'), before.b, 'leaving takes the cursor away');
  assert.deepEqual(await page.evaluate(() => window.errors), []);
  await context.close();
});

test('markers sit on each series at the cursor, only a nearest one on a nearest chart, and none with the cursor away', async () => {
  const { page, context } = await open('/markers.html');
  await drawn(page, 2);
  const read = (id, x, y) => page.evaluate(([id, x, y]) => {
    const canvas = document.getElementById(id).shadowRoot.querySelector('canvas');
    return [...canvas.getContext('2d').getImageData(x, y, 1, 1).data];
  }, [id, x, y]);
  const move = (id, type, y) => page.evaluate(([id, type, y]) => {
    const el = document.getElementById(id);
    const rect = el.getBoundingClientRect();
    el.dispatchEvent(new PointerEvent(type, { pointerId: 1, clientX: rect.left + 100, clientY: rect.top + y }));
  }, [id, type, y]);
  const spots = { a: [[100, 140], [100, 60], [100, 100]], b: [[100, 140], [100, 60]] };
  const snap = async id => Promise.all(spots[id].map(([x, y]) => read(id, x, y)));
  const away = { a: await snap('a'), b: await snap('b') };
  await move('a', 'pointermove', 100);
  await settle(page);
  const near = await snap('a');
  assert.notDeepEqual(near[0], away.a[0], 'the first series has a marker at its value at the cursor x');
  assert.deepEqual(near[0].slice(0, 3), [0xdd, 0x33, 0x33], 'in its colour');
  assert.notDeepEqual(near[1], away.a[1], 'so has the second');
  assert.deepEqual(near[2], away.a[2], 'nothing is drawn between them');
  await move('a', 'pointerleave', 100);
  await settle(page);
  assert.deepEqual(await snap('a'), away.a, 'leaving takes the markers away');
  await move('b', 'pointermove', 130);
  await settle(page);
  const only = await snap('b');
  assert.notDeepEqual(only[0], away.b[0], 'the series nearest the pointer has a marker');
  assert.deepEqual(only[1], away.b[1], 'the other has none');
  assert.deepEqual(await page.evaluate(() => window.errors), []);
  await context.close();
});

test('a drag on a selecting chart draws a band that the others in its group show, and its own range stays', async () => {
  const { page, context } = await open('/select.html');
  await drawn(page, 2);
  await page.evaluate(() => {
    window.selected = []; window.followed = []; window.own = [];
    document.getElementById('a').addEventListener('inkproof-select', e => window.selected.push(e.detail));
    document.getElementById('a').addEventListener('inkproof-view', e => window.own.push(e.detail));
    document.getElementById('b').addEventListener('inkproof-view', e => window.followed.push(e.detail));
  });
  const point = (type, x) => page.evaluate(([type, x]) => {
    const el = document.getElementById('a');
    const rect = el.getBoundingClientRect();
    el.dispatchEvent(new PointerEvent(type, { pointerId: 1, clientX: rect.left + x, clientY: rect.top + 100 }));
  }, [type, x]);
  await point('pointerdown', 150);
  await point('pointermove', 250);
  await point('pointerup', 250);
  await settle(page);
  const [band] = (await page.evaluate(() => window.selected)).slice(-1);
  assert.ok(band.xStart < band.xEnd, 'the drag reports an ordered range');
  const [view] = (await page.evaluate(() => window.followed)).slice(-1);
  assert.deepEqual([view.xStart, view.xEnd], [band.xStart, band.xEnd], 'the other chart takes the selected range');
  assert.deepEqual(await page.evaluate(() => window.own), [], 'the selecting chart keeps its range');
  await point('pointerdown', 200);
  await point('pointermove', 240);
  await point('pointerup', 240);
  const moved = (await page.evaluate(() => window.selected)).at(-1);
  assert.ok(Math.abs(moved.xStart - band.xStart - 10) < 1e-6 && Math.abs(moved.xEnd - band.xEnd - 10) < 1e-6, 'a drag inside the band moves it');
  await page.locator('#b').focus();
  await page.keyboard.press('+');
  await settle(page);
  const zoomed = (await page.evaluate(() => window.selected)).at(-1);
  const shown = (await page.evaluate(() => window.followed)).at(-1);
  assert.deepEqual([zoomed.xStart, zoomed.xEnd], [shown.xStart, shown.xEnd], 'zooming the other chart moves the band');
  assert.deepEqual(await page.evaluate(() => window.own), [], 'the selecting chart still keeps its range');
  assert.deepEqual(await page.evaluate(() => window.errors), []);
  await context.close();
});

test('buttons reset and unlink charts with no page script, and the page decodes the events', async () => {
  const { page, context } = await open('/buttons.html');
  await drawn(page, 2);
  const seen = () => page.evaluate(() => {
    window.last = {};
    for (const id of ['a', 'b']) document.getElementById(id).addEventListener('inkproof-view', e => { window.last[id] = e.detail; window.latest = e.detail; });
  });
  const wheel = () => page.evaluate(() => {
    const el = document.getElementById('a');
    const rect = el.getBoundingClientRect();
    el.dispatchEvent(new WheelEvent('wheel', { bubbles: true, cancelable: true, clientX: rect.left + 100, clientY: rect.top + 100, deltaY: -200 }));
  });
  await seen();
  await wheel();
  const zoomed = await page.evaluate(() => window.last.a);
  assert.ok(zoomed.xEnd - zoomed.xStart < 100);
  const decoded = (await page.locator('#view').textContent()).split(' ').map(Number);
  const latest = await page.evaluate(() => window.latest);
  const expected = [latest.xStart, latest.xEnd - latest.xStart, latest.yStart, latest.yEnd - latest.yStart];
  decoded.forEach((n, i) => assert.ok(Math.abs(n - expected[i]) < 1e-5, `${decoded} vs ${expected}`));
  await page.click('#reset');
  const home = await page.evaluate(() => window.last.a);
  assert.deepEqual([home.xStart, home.xEnd], [0, 100]);
  await page.click('#unlink');
  assert.equal(await page.evaluate(() => document.getElementById('b').hasAttribute('group')), false);
  await seen();
  await wheel();
  assert.equal(await page.evaluate(() => window.last.b), undefined, 'an unlinked chart does not follow');
  await page.click('#unlink');
  assert.equal(await page.evaluate(() => document.getElementById('b').getAttribute('group')), 'g');
  await page.evaluate(() => {
    const el = document.getElementById('a');
    const rect = el.getBoundingClientRect();
    el.dispatchEvent(new PointerEvent('pointermove', { pointerId: 1, clientX: rect.left + 100, clientY: rect.top + 100 }));
  });
  const [x, y] = (await page.locator('#reading').textContent()).split(' ').map(Number);
  assert.ok(Number.isFinite(x) && Number.isFinite(y));
  assert.deepEqual(await page.evaluate(() => window.errors), []);
  await context.close();
});

test('a chart that builds from its scene cache uploads once, again after the data changes or a context is lost', async () => {
  const { page, context } = await open('/cached.html');
  await drawn(page, 1);
  assert.equal(await page.evaluate(() => window.uploads), 1);
  const redraw = async (event, n) => {
    await page.evaluate(event => document.querySelector('inkproof-cached-chart').dispatchEvent(new Event(event)), event);
    await drawn(page, n);
  };
  await redraw('test-redraw', 2);
  assert.equal(await page.evaluate(() => window.uploads), 1, 'a second draw reuses the buffer');
  await page.evaluate(() => { window.lose = window.contexts[0].getExtension('WEBGL_lose_context'); window.lose.loseContext(); });
  await page.waitForFunction(() => window.contexts[0].isContextLost());
  await page.evaluate(() => window.lose.restoreContext());
  await redraw('test-redraw', 3);
  assert.equal(await page.evaluate(() => window.uploads), 2, 'a draw after a lost context uploads again');
  await page.evaluate(() => document.querySelector('inkproof-cached-chart').dispatchEvent(new Event('test-invalidate')));
  await redraw('test-redraw', 4);
  assert.equal(await page.evaluate(() => window.uploads), 3, 'an invalidated cache uploads again');
  assert.deepEqual(await page.evaluate(() => window.errors), []);
  await context.close();
});

test('the tooltip names the nearest visible point and the legend gives each series value at the cursor', async () => {
  const { page, context } = await open('/probe.html');
  await drawn(page, 1);
  await page.evaluate(() => {
    window.toggled = [];
    document.getElementById('a').addEventListener('inkproof-series', e => window.toggled.push(e.detail));
  });
  const move = y => page.evaluate(y => {
    const el = document.getElementById('a');
    const rect = el.getBoundingClientRect();
    el.dispatchEvent(new PointerEvent('pointermove', { pointerId: 1, clientX: rect.left + 100, clientY: rect.top + y }));
  }, y);
  const text = sel => page.evaluate(sel => document.getElementById('a').shadowRoot.querySelector(sel).textContent, sel);
  const legend = () => page.evaluate(() =>
    [...document.getElementById('a').shadowRoot.querySelectorAll('.legend button')].map(b => b.textContent));
  const away = await legend();
  assert.equal(away.length, 2);
  assert.ok(away.every(t => /^\w+: \S+ \(last\)$/.test(t)), `with no cursor each row gives its last value, got ${away}`);
  const readout = () => page.evaluate(() => document.getElementById('a').shadowRoot.querySelector('.legend .readout')?.textContent ?? null);
  assert.equal(await readout(), null, 'with no cursor there is no readout');
  await move(130);
  assert.deepEqual(await legend(), ['North: 30', 'South: 70'], 'each value is the series at the cursor x');
  assert.match(await readout(), /^x: 25, y: /, 'the readout gives the position under the cursor');
  assert.equal(await text('.tip'), 'North: 25, 30');
  await move(40);
  assert.equal(await text('.tip'), 'South: 25, 70', 'the nearest point changes with the pointer');
  await page.locator('#a .legend button').first().click();
  assert.deepEqual(await page.evaluate(() => window.toggled), [{ series: 0, hidden: true }]);
  await move(130);
  assert.equal(await text('.tip'), 'South: 25, 70', 'a hidden series has no nearest point');
  assert.equal(await page.evaluate(() =>
    document.getElementById('a').shadowRoot.querySelector('.legend button').getAttribute('aria-pressed')), 'false');
  assert.deepEqual(await page.evaluate(() => window.errors), []);
  await context.close();
});

test('the legend shows a group of values at the nearest x, or its last, and toggles only a hideable group', async () => {
  const { page, context } = await open('/values.html');
  await drawn(page, 1);
  await page.evaluate(() => {
    window.toggled = [];
    document.getElementById('a').addEventListener('inkproof-group', e => window.toggled.push(e.detail));
  });
  const legend = () => page.evaluate(() =>
    [...document.getElementById('a').shadowRoot.querySelectorAll('.legend button, .legend .entry')].map(b => b.textContent));
  assert.deepEqual(await legend(), ['Open: 5 (last)', 'Close: 6 (last)', 'State: - (last)'], 'with no cursor the last group, a missing value as a dash');
  await page.evaluate(() => {
    const el = document.getElementById('a');
    const rect = el.getBoundingClientRect();
    el.dispatchEvent(new PointerEvent('pointermove', { pointerId: 1, clientX: rect.left + 80, clientY: rect.top + 100 }));
  });
  assert.deepEqual(await legend(), ['Open: 3', 'Close: 4', 'State: 8'], 'the group nearest the cursor x');
  const kinds = () => page.evaluate(() =>
    [...document.getElementById('a').shadowRoot.querySelectorAll('.legend button, .legend .entry')].map(e => e.tagName));
  assert.deepEqual(await kinds(), ['BUTTON', 'BUTTON', 'DIV'], 'only the hideable group toggles');
  await page.locator('#a .legend button').first().click();
  assert.deepEqual(await page.evaluate(() => window.toggled), [{ group: 0, hidden: true }]);
  assert.deepEqual(await page.evaluate(() =>
    [...document.getElementById('a').shadowRoot.querySelectorAll('.legend button')].map(b => b.getAttribute('aria-pressed'))), ['false', 'false']);
  assert.deepEqual(await page.evaluate(() => window.errors), []);
  await context.close();
});

test('a static legend lists each series without values or readout, and still toggles', async () => {
  const { page, context } = await open('/probe.html');
  await drawn(page, 1);
  await page.evaluate(() => {
    window.toggled = [];
    const el = document.getElementById('a');
    el.addEventListener('inkproof-series', e => window.toggled.push(e.detail));
    el.setAttribute('legend', 'static');
  });
  await page.evaluate(() => {
    const el = document.getElementById('a');
    const rect = el.getBoundingClientRect();
    el.dispatchEvent(new PointerEvent('pointermove', { pointerId: 1, clientX: rect.left + 100, clientY: rect.top + 130 }));
  });
  const state = () => page.evaluate(() => {
    const root = document.getElementById('a').shadowRoot;
    return { names: [...root.querySelectorAll('.legend button')].map(b => b.textContent), readout: root.querySelector('.legend .readout') };
  });
  assert.deepEqual(await state(), { names: ['North', 'South'], readout: null });
  await page.locator('#a .legend button').first().click();
  assert.deepEqual(await page.evaluate(() => window.toggled), [{ series: 0, hidden: true }]);
  assert.deepEqual(await page.evaluate(() => window.errors), []);
  await context.close();
});

test('a legend lies where its placement says, lists entries in a row or a column, and shows the readouts it is asked for', async () => {
  const { page, context } = await open('/probe.html');
  await drawn(page, 1);
  const boxes = legend => page.evaluate(async legend => {
    const el = document.getElementById('a');
    el.setAttribute('legend', legend);
    await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(() => setTimeout(r, 50))));
    const root = el.shadowRoot;
    const box = e => { const r = e.getBoundingClientRect(); return { left: r.left, right: r.right, top: r.top, bottom: r.bottom }; };
    return { host: box(el), canvas: box(root.querySelector('canvas')), legend: box(root.querySelector('.legend')),
      entries: [...root.querySelectorAll('.legend button')].map(box) };
  }, legend);
  const near = (a, b, what) => assert.ok(Math.abs(a - b) <= 1, `${what}: ${a} is not ${b}`);
  const corners = { 'top-left': [true, true], 'top-right': [true, false], 'bottom-left': [false, true], 'bottom-right': [false, false] };
  for (const [place, [top, left]] of Object.entries(corners)) {
    for (const layout of ['vertical', 'horizontal']) {
      const b = await boxes(`${place} ${layout}`);
      near(top ? b.legend.top : b.legend.bottom, top ? b.canvas.top : b.canvas.bottom, `${place} ${layout} vertical edge`);
      near(left ? b.legend.left : b.legend.right, left ? b.canvas.left : b.canvas.right, `${place} ${layout} horizontal edge`);
    }
  }
  for (const [place, at] of [['below-left', 0], ['below-center', 0.5], ['below-right', 1]]) {
    for (const layout of ['vertical', 'horizontal']) {
      const b = await boxes(`${place} ${layout}`);
      assert.ok(b.legend.top >= b.canvas.bottom - 0.5, `${place} ${layout}: the legend overlaps the plot`);
      assert.ok(b.legend.bottom <= b.host.bottom + 0.5, `${place} ${layout}: the legend leaves the element`);
      const used = b.entries.length ? [Math.min(...b.entries.map(e => e.left)), Math.max(...b.entries.map(e => e.right))] : [0, 0];
      const free = (b.host.right - b.host.left) - (used[1] - used[0]);
      if (layout === 'horizontal') near(used[0] - b.host.left, free * at, `${place} row alignment`);
      else {
        const e = b.entries[0];
        near(e.left - b.host.left, ((b.host.right - b.host.left) - (e.right - e.left)) * at, `${place} column alignment`);
      }
    }
  }
  const row = await boxes('below-center horizontal');
  near(row.entries[0].top, row.entries[1].top, 'a row puts entries at one vertical position');
  const column = await boxes('below-left vertical');
  near(column.entries[0].left, column.entries[1].left, 'a column puts entries at one horizontal position');
  assert.ok(column.entries[1].top > column.entries[0].top, 'a column stacks its entries');
  const readout = async legend => {
    await page.evaluate(legend => {
      const el = document.getElementById('a');
      el.setAttribute('legend', legend);
      const rect = el.getBoundingClientRect();
      el.dispatchEvent(new PointerEvent('pointermove', { pointerId: 1, clientX: rect.left + 100, clientY: rect.top + 100 }));
    }, legend);
    await settle(page);
    return page.evaluate(() => document.getElementById('a').shadowRoot.querySelector('.legend .readout')?.textContent ?? null);
  };
  assert.match(await readout('static x'), /^x: [^,]+$/, 'a static legend shows x when asked');
  assert.match(await readout('static y'), /^y: /, 'a static legend shows y when asked');
  assert.match(await readout('no-y'), /^x: [^,]+$/, 'a live legend leaves y out');
  assert.match(await readout('no-x'), /^y: /, 'a live legend leaves x out');
  assert.equal(await readout('no-x no-y'), null, 'no readout line when both are hidden');
  assert.match(await readout('below-center'), /^x: .*, y: /, 'both by default');
  assert.deepEqual(await page.evaluate(() => window.errors), []);
  await page.evaluate(() => document.getElementById('a').setAttribute('legend', 'sideways'));
  await page.waitForFunction(() => window.errors.length > 0);
  assert.match(await page.evaluate(() => window.errors[0]), /expected on, off, static, bottom/);
  await context.close();
});

test('a conflicting or unknown word in cursor or interaction is reported, not defaulted', async () => {
  const { page, context } = await open('/probe.html');
  await drawn(page, 1);
  const report = async (name, value) => {
    await page.evaluate(([n, v]) => { window.errors.length = 0; document.getElementById('a').setAttribute(n, v); }, [name, value]);
    await page.waitForFunction(() => window.errors.length > 0);
    return page.evaluate(() => window.errors[0]);
  };
  assert.match(await report('interaction', 'wheel-zoom no-wheel'), /two words for the wheel/);
  assert.match(await report('interaction', 'sideways'), /unknown word "sideways"/);
  assert.match(await report('cursor', 'x xy'), /two words for the lines/);
  assert.match(await report('cursor', 'dotty'), /unknown word "dotty"/);
  await context.close();
});

test('the cursor, tooltip and legend work over a trace of half a million points', async () => {
  const { page, context } = await open('/huge.html');
  await drawn(page, 1);
  await page.evaluate(() => {
    const el = document.getElementById('a');
    const rect = el.getBoundingClientRect();
    el.dispatchEvent(new PointerEvent('pointermove', { pointerId: 1, clientX: rect.left + 200, clientY: rect.top + 100 }));
  });
  const row = () => page.evaluate(() =>
    document.getElementById('a').shadowRoot.querySelector('.legend button').textContent);
  assert.match(await row(), /^Wave: \S+$/, 'the legend reads the value at the cursor, not the last one');
  assert.match(await page.evaluate(() => document.getElementById('a').shadowRoot.querySelector('.tip').textContent), /^Wave: 25\d{4}, /);

  assert.deepEqual(await page.evaluate(() => window.errors), []);
  await context.close();
});

test('a sized chart makes its scene again for its new size and keeps its legend outside the plot', async () => {
  const { page, context } = await open('/sized.html');
  await drawn(page, 1);
  const inkCentre = () => page.evaluate(() => {
    const c = document.querySelector('inkproof-sized-chart').shadowRoot.querySelector('canvas');
    const k = c.width / c.getBoundingClientRect().width;
    const data = c.getContext('2d').getImageData(0, 0, c.width, c.height).data;
    let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity;
    for (let y = 0; y < c.height; y++) for (let x = 0; x < c.width; x++) {
      const i = (y * c.width + x) * 4;
      if (data[i] > 90 || data[i + 1] > 90 || data[i + 2] > 90) continue;
      x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); y1 = Math.max(y1, y);
    }
    const r = c.getBoundingClientRect();
    return { x: (x0 + x1) / 2 / k - r.width, y: (y0 + y1) / 2 / k - r.height / 2 };
  });
  const near = async what => {
    await page.waitForFunction(() => window.draws.length > 0);
    const { x, y } = await inkCentre();
    assert.ok(Math.abs(x + 30) <= 3 && Math.abs(y) <= 3, `${what}: label off its anchor by ${x + 30}, ${y}`);
  };
  await near('first size');
  await page.setViewportSize({ width: 900, height: 600 });
  await page.evaluate(() => { document.querySelector('inkproof-sized-chart').style.width = '700px'; document.querySelector('inkproof-sized-chart').style.height = '320px'; });
  await page.waitForFunction(() => document.querySelector('inkproof-sized-chart').shadowRoot.querySelector('canvas').getBoundingClientRect().width === 700);
  await settle(page);
  await settle(page);
  await near('after resizing');
  const layout = await page.evaluate(() => {
    const root = document.querySelector('inkproof-sized-chart').shadowRoot;
    const host = document.querySelector('inkproof-sized-chart').getBoundingClientRect();
    const canvas = root.querySelector('canvas').getBoundingClientRect();
    const legend = root.querySelector('.legend').getBoundingClientRect();
    return { host, canvas, legend };
  });
  assert.ok(layout.canvas.bottom <= layout.legend.top + 0.5, 'the legend overlaps the plot');
  assert.ok(Math.abs(layout.legend.right - layout.host.right) <= 1, 'the legend is not at the right');
  assert.ok(layout.legend.bottom <= layout.host.bottom + 0.5, 'the legend leaves the element');
  await context.close();
});

test('a clipped draw covers the whole plot at any device pixel ratio', async () => {
  for (const factor of [1, 2, 3]) {
    const { page, context } = await open('/pixels.html', { deviceScaleFactor: factor });
    await drawn(page, 1);
    const corners = await page.evaluate(() => {
      const c = document.querySelector('inkproof-pixel-chart').shadowRoot.querySelector('canvas');
      const px = (x, y) => [...c.getContext('2d').getImageData(x, y, 1, 1).data];
      return { width: c.width, pixels: [px(2, 2), px(c.width - 3, 2), px(2, c.height - 3), px(c.width - 3, c.height - 3)] };
    });
    assert.equal(corners.width, 400 * factor);
    for (const rgba of corners.pixels) assert.deepEqual(rgba, corners.pixels[0], `ratio ${factor}: the corners differ`);
    assert.notDeepEqual(corners.pixels[0], [255, 255, 255, 255], `ratio ${factor}: nothing drawn`);
    await context.close();
  }
});

// Dispatches a wheel event over the plot and reports whether the chart took it (default-prevented).
const wheelTaken = (page, init = {}) => page.evaluate(init => {
  const el = document.querySelector('inkproof-accessible-chart');
  const rect = el.getBoundingClientRect();
  return !el.dispatchEvent(new WheelEvent('wheel', { bubbles: true, cancelable: true, clientX: rect.left + 100, clientY: rect.top + 100, deltaY: -200, ...init }));
}, init);
const touchAction = page => page.evaluate(() => getComputedStyle(document.querySelector('inkproof-accessible-chart')).touchAction);
const zoomed = async page => { const v = await lastView(page); return v !== undefined && v.xEnd - v.xStart < 100; };

test('a chart with wheel="off" leaves the wheel to the page', async () => {
  const { page, context } = await open('/wheeloff.html');
  await drawn(page, 1);
  assert.equal(await wheelTaken(page), false);
  await gesture(page, [['wheel', { x: 100, y: 100, deltaY: -200 }]]);
  assert.equal(await zoomed(page), false, 'the view did not change');
  await context.close();
});

test('a chart with no wheel attribute takes the wheel and zooms', async () => {
  const { page, context } = await open('/accessible.html');
  await drawn(page, 1);
  assert.equal(await wheelTaken(page), true);
  await gesture(page, [['wheel', { x: 100, y: 100, deltaY: -200 }]]);
  assert.equal(await zoomed(page), true);
  await context.close();
});

test('with wheel="ctrl" only the wheel with Ctrl or Meta held zooms', async () => {
  const { page, context } = await open('/wheelctrl.html');
  await drawn(page, 1);
  assert.equal(await wheelTaken(page), false);
  await gesture(page, [['wheel', { x: 100, y: 100, deltaY: -200 }]]);
  assert.equal(await zoomed(page), false);
  assert.equal(await wheelTaken(page, { ctrlKey: true }), true);
  assert.equal(await wheelTaken(page, { metaKey: true }), true);
  await gesture(page, [['wheel', { x: 100, y: 100, deltaY: -200, ctrlKey: true }]]);
  assert.equal(await zoomed(page), true);
  await context.close();
});

test('touch-action follows what the chart does with touch', async () => {
  const check = async (path, expected) => {
    const { page, context } = await open(path);
    await drawn(page, 1);
    assert.equal(await touchAction(page), expected, path);
    await context.close();
  };
  await check('/accessible.html', 'none');
  await check('/touchoff.html', 'auto');
  await check('/dragoff.html', 'pan-x pan-y');
  await check('/select.html', 'pan-y');
});

test('with touch="off" a finger does not pan or pinch', async () => {
  const { page, context } = await open('/touchoff.html');
  await drawn(page, 1);
  await gesture(page, [['pointerdown', { x: 100, y: 100, pointerId: 1 }], ['pointermove', { x: 200, y: 100, pointerId: 1 }], ['pointerup', { x: 200, y: 100, pointerId: 1 }]]);
  const views = await page.evaluate(() => window.views);
  assert.equal(views.length, 0, 'no view change');
  await context.close();
});

test('with drag="off" a mouse drag does not pan but a pinch still zooms', async () => {
  const { page, context } = await open('/dragoff.html');
  await drawn(page, 1);
  await gesture(page, [['pointerdown', { x: 100, y: 100, pointerId: 1, pointerType: 'mouse' }], ['pointermove', { x: 200, y: 100, pointerId: 1, pointerType: 'mouse' }], ['pointerup', { x: 200, y: 100, pointerId: 1, pointerType: 'mouse' }]]);
  assert.equal((await page.evaluate(() => window.views)).length, 0, 'the drag did not pan');
  await gesture(page, [['pointerdown', { x: 100, y: 100, pointerId: 1 }], ['pointerdown', { x: 200, y: 100, pointerId: 2 }], ['pointermove', { x: 50, y: 100, pointerId: 1 }], ['pointermove', { x: 250, y: 100, pointerId: 2 }]]);
  assert.equal(await zoomed(page), true, 'the pinch zoomed');
  await context.close();
});

test('the tooltip stays inside the chart, moves by its offset and takes its look from custom properties', async () => {
  const { page, context } = await open('/tooltip.html');
  await drawn(page, 1);
  const move = (x, y) => page.evaluate(([x, y]) => {
    const el = document.getElementById('a');
    const rect = el.getBoundingClientRect();
    el.dispatchEvent(new PointerEvent('pointermove', { pointerId: 1, clientX: rect.left + x, clientY: rect.top + y }));
  }, [x, y]);
  const set = tooltip => page.evaluate(t => document.getElementById('a').setAttribute('tooltip', t), tooltip);
  // The tooltip and the chart, in pixels from the chart's top left.
  const boxes = () => page.evaluate(() => {
    const el = document.getElementById('a');
    const host = el.getBoundingClientRect();
    const r = el.shadowRoot.querySelector('.tip').getBoundingClientRect();
    return { left: r.left - host.left, top: r.top - host.top, right: r.right - host.left, bottom: r.bottom - host.top, width: host.width, height: host.height };
  });
  for (const words of ['xy top-right 150', 'xy top-left 150', 'xy bottom-right 150', 'xy bottom-left 150', 'xy pointer bottom-right 40']) {
    for (const [x, y] of [[395, 195], [5, 5], [395, 5], [200, 100]]) {
      await set(words);
      await move(x, y);
      const b = await boxes();
      assert.ok(b.left >= 0 && b.top >= 0 && b.right <= b.width && b.bottom <= b.height, `"${words}" at ${x},${y} lies outside the chart: ${JSON.stringify(b)}`);
    }
  }
  await set('xy pointer 8');
  await move(150, 100);
  const near = await boxes();
  await set('xy pointer 28');
  await move(150, 100);
  const far = await boxes();
  assert.ok(Math.abs(far.left - near.left - 20) < 1 && Math.abs(near.top - far.top - 20) < 1, `an offset of 28 rather than 8 moves it 20 pixels, got ${JSON.stringify([near, far])}`);
  await set('xy pointer bottom-left 8');
  await move(150, 100);
  const flipped = await boxes();
  assert.ok(Math.abs(flipped.right - 142) < 1 && Math.abs(flipped.bottom - 108) < 1, `opening bottom-left puts the corner 8 pixels from the pointer, got ${JSON.stringify(flipped)}`);
  await set('shared no-x-value');
  await move(100, 100);
  const shared = await page.evaluate(() => document.getElementById('a').shadowRoot.querySelector('.tip').textContent);
  assert.equal(shared, 'North: 30\nSouth: 70', 'a shared tooltip lists every series at the cursor x');
  await set('shared');
  assert.equal(await page.evaluate(() => document.getElementById('a').shadowRoot.querySelector('.tip').textContent), 'x: 25\nNorth: 30\nSouth: 70');
  await page.evaluate(() => {
    const el = document.getElementById('a');
    el.style.setProperty('--inkproof-tooltip-color', 'rgb(1, 2, 3)');
    el.style.setProperty('--inkproof-tooltip-background', 'rgb(4, 5, 6)');
    el.style.setProperty('--inkproof-tooltip-border-color', 'rgb(7, 8, 9)');
    el.style.setProperty('--inkproof-tooltip-border-width', '3px');
    el.style.setProperty('--inkproof-tooltip-border-radius', '5px');
    el.style.setProperty('--inkproof-tooltip-font-size', '19px');
    el.style.setProperty('--inkproof-tooltip-font-family', 'monospace');
    el.style.setProperty('--inkproof-tooltip-padding', '9px');
    el.style.setProperty('--inkproof-tooltip-shadow', 'rgb(10, 11, 12) 1px 1px 2px');
  });
  const look = await page.evaluate(() => {
    const s = getComputedStyle(document.getElementById('a').shadowRoot.querySelector('.tip'));
    return [s.color, s.backgroundColor, s.borderTopColor, s.borderTopWidth, s.borderTopLeftRadius, s.fontSize, s.fontFamily, s.paddingTop, s.boxShadow];
  });
  assert.deepEqual(look, ['rgb(1, 2, 3)', 'rgb(4, 5, 6)', 'rgb(7, 8, 9)', '3px', '5px', '19px', 'monospace', '9px', 'rgb(10, 11, 12) 1px 1px 2px 0px']);
  assert.deepEqual(await page.evaluate(() => window.errors), []);
  await context.close();
});

test('a tooltip with words that contradict each other is refused', async () => {
  const { page, context } = await open('/tooltip.html');
  await drawn(page, 1);
  await page.evaluate(() => document.getElementById('a').setAttribute('tooltip', 'shared xy'));
  assert.equal((await page.evaluate(() => window.errors)).length, 1);
  await context.close();
});
