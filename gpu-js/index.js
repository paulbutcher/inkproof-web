// Copyright (c) 2026 Paul Butcher. All rights reserved.
// Released under Apache 2.0 license as described in the file LICENSE.
// Generated from Inkproof.Gpu.specs. Do not edit.

class Reader {
  constructor(bytes) {
    this.v = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    this.p = 0;
  }
  u8() { return this.v.getUint8(this.p++); }
  u32() { const n = this.v.getUint32(this.p, true); this.p += 4; return n; }
  words() {
    const n = this.u32();
    const w = new Uint32Array(n);
    for (let i = 0; i < n; i++) w[i] = this.u32();
    return w;
  }
  done() { return this.p === this.v.byteLength; }
}

const VERTEX_SOURCE = "#version 300 es\n// Copyright (c) 2026 Paul Butcher. All rights reserved.\n// Released under Apache 2.0 license as described in the file LICENSE.\n// Generated from Inkproof.Gpu.Shader. Do not edit.\nprecision highp float;\nin vec2 a_position;\nuniform vec2 u_slope;\nuniform vec2 u_offset;\nvoid main() {\n  vec2 p = ((a_position * u_slope) + u_offset);\n  gl_Position = vec4(p.x, p.y, 0.0, 1.0);\n}\n";
const FRAGMENT_SOURCE = "#version 300 es\n// Copyright (c) 2026 Paul Butcher. All rights reserved.\n// Released under Apache 2.0 license as described in the file LICENSE.\n// Generated from Inkproof.Gpu.Shader. Do not edit.\nprecision highp float;\nuniform vec4 u_colour;\nout vec4 o_colour;\nvoid main() {\n  o_colour = u_colour;\n}\n";
const UNIFORM_NAMES = ["u_slope", "u_offset", "u_colour"];

function compile(gl, type, source) {
  const shader = gl.createShader(type);
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(shader));
  return shader;
}

function buildProgram(gl) {
  const program = gl.createProgram();
  const shaders = [compile(gl, gl.VERTEX_SHADER, VERTEX_SOURCE), compile(gl, gl.FRAGMENT_SHADER, FRAGMENT_SOURCE)];
  for (const shader of shaders) gl.attachShader(program, shader);
  gl.bindAttribLocation(program, 0, "a_position");
  gl.linkProgram(program);
  const linked = gl.getProgramParameter(program, gl.LINK_STATUS);
  for (const shader of shaders) gl.deleteShader(shader);
  if (!linked) {
    const log = gl.getProgramInfoLog(program);
    gl.deleteProgram(program);
    throw new Error(log);
  }
  return { program, uniforms: UNIFORM_NAMES.map(n => gl.getUniformLocation(program, n)) };
}

function decodeCommand(r) {
  switch (r.u8()) {
    case 0: return { op: 0, name: "createBuffer", args: [r.u32()] };
    case 1: return { op: 1, name: "bufferData", args: [r.u32(), r.words()] };
    case 2: return { op: 2, name: "deleteBuffer", args: [r.u32()] };
    case 3: return { op: 3, name: "useProgram", args: [r.u32()] };
    case 4: return { op: 4, name: "uniform", args: [r.u32(), r.words()] };
    case 5: return { op: 5, name: "draw", args: [r.u32(), r.u32()] };
    case 6: return { op: 6, name: "clear", args: [r.u32()] };
    case 7: return { op: 7, name: "createProgram", args: [r.u32()] };
    case 8: return { op: 8, name: "scissor", args: [r.words()] };
    default: throw new Error("unknown command");
  }
}

export function decode(bytes) {
  const r = new Reader(bytes);
  const n = r.u32();
  const cmds = [];
  for (let i = 0; i < n; i++) cmds.push(decodeCommand(r));
  if (!r.done()) throw new Error("trailing bytes");
  return cmds;
}

export function newState() {
  return { buffers: new Map(), programs: new Map(), current: null };
}

export function releaseState(gl, s) {
  if (s.current) gl.useProgram(null);
  for (const b of s.buffers.values()) gl.deleteBuffer(b);
  for (const p of s.programs.values()) gl.deleteProgram(p.program);
  s.buffers.clear();
  s.programs.clear();
  s.current = null;
}

export function run(gl, s, bytes) {
  for (const { op, args: a } of decode(bytes)) {
    switch (op) {
    case 0: {
      s.buffers.set(a[0], gl.createBuffer());
      break;
    }
    case 1: {
      gl.bindBuffer(gl.ARRAY_BUFFER, s.buffers.get(a[0]));
      gl.bufferData(gl.ARRAY_BUFFER, a[1], gl.STATIC_DRAW);
      break;
    }
    case 2: {
      gl.deleteBuffer(s.buffers.get(a[0]));
      s.buffers.delete(a[0]);
      break;
    }
    case 3: {
      s.current = s.programs.get(a[0]);
      gl.useProgram(s.current.program);
      break;
    }
    case 4: {
      const w = new Float32Array(a[1].buffer);
      gl["uniform" + w.length + "fv"](s.current.uniforms[a[0]], w);
      break;
    }
    case 5: {
      gl.bindBuffer(gl.ARRAY_BUFFER, s.buffers.get(a[0]));
      gl.enableVertexAttribArray(0);
      gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
      gl.drawArrays(gl.TRIANGLES, 0, a[1]);
      break;
    }
    case 6: {
      gl.clearColor((a[0] >>> 24) / 255, ((a[0] >>> 16) & 255) / 255,
        ((a[0] >>> 8) & 255) / 255, (a[0] & 255) / 255);
      gl.clear(gl.COLOR_BUFFER_BIT);
      break;
    }
    case 7: {
      s.programs.set(a[0], buildProgram(gl));
      break;
    }
    case 8: {
      const w = new Int32Array(a[0].buffer);
      if (w.length === 4) { gl.enable(gl.SCISSOR_TEST); gl.scissor(w[0], w[1], w[2], w[3]); }
      else { gl.disable(gl.SCISSOR_TEST); }
      break;
    }
    }
  }
}
