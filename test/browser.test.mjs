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
  await gesture(page, [['wheel', { x: 100, y: 100, deltaY: -200 }]]);
  const first = await lastView(page);
  const n = await page.evaluate(() => window.draws.length);
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
  await point('a', 'pointerleave');
  await settle(page);
  assert.deepEqual(await read('b'), before.b, 'leaving takes the cursor away');
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
