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
