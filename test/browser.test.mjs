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

test('a tile query sums the tiles it touches and leaves the main thread free', async () => {
  const { page, context, messages } = await open('/tiles.html');
  await page.evaluate(() => { window.ticks = 0; const tick = () => { window.ticks++; setTimeout(tick, 0); }; tick(); });
  await page.waitForFunction(() => document.body.hasAttribute('done'));
  const attrs = await page.evaluate(() => ({ sum: document.body.getAttribute('sum'), missing: document.body.getAttribute('missing'), ticks: window.ticks }));
  let expected = 0;
  for (let i = 2; i < 14; i++) expected += i * 3 + 1;
  assert.equal(attrs.sum, String(expected));
  assert.match(attrs.missing, /^error/);
  assert.ok(attrs.ticks > 0);
  assert.ok(messages.some(m => m.type === 'warning' && m.text.includes('fetching a tile failed') && m.text.includes('tiles/4.bin')), JSON.stringify(messages));
  await context.close();
});

const keyed = async (page, ...keys) => {
  await page.evaluate(() => {
    window.views = []; window.cursors = [];
    const el = document.querySelector('inkproof-accessible-chart');
    el.addEventListener('inkproof-view', e => window.views.push(e.detail));
    el.addEventListener('inkproof-cursor', e => window.cursors.push(e.detail));
  });
  await page.locator('inkproof-accessible-chart').focus();
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
