'use strict';

/* Animated background: drifting colour fields, synthwave grid and star dust. */
(function () {
  const canvas = document.getElementById('bg');
  const ctx = canvas.getContext('2d');
  let width = 0;
  let height = 0;
  let dpr = 1;

  const fract = (v) => v - Math.floor(v);
  const particles = Array.from({ length: 110 }, (_, i) => {
    const seed = i * 12.9898;
    return {
      x: fract(Math.sin(seed) * 43758.5453),
      y: fract(Math.sin(seed * 1.7) * 24634.6345),
      speed: 0.004 + fract(Math.sin(seed * 2.3) * 9631.1) * 0.012,
      r: 0.5 + fract(Math.sin(seed * 3.1) * 1234.5) * 1.5,
      seed,
      color: i % 5 === 0 ? '64,220,255' : i % 7 === 0 ? '237,84,242' : '255,255,255',
    };
  });

  const blobs = [
    { color: '110,97,255', x: 0.25, y: 0.2, r: 0.55, fx: 0.11, fy: 0.07 },
    { color: '237,84,242', x: 0.78, y: 0.3, r: 0.45, fx: 0.08, fy: 0.12 },
    { color: '64,220,255', x: 0.45, y: 0.75, r: 0.5, fx: 0.06, fy: 0.09 },
    { color: '77,35,170', x: 0.9, y: 0.85, r: 0.4, fx: 0.1, fy: 0.05 },
  ];

  function resize() {
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    width = window.innerWidth;
    height = window.innerHeight;
    canvas.width = width * dpr;
    canvas.height = height * dpr;
    canvas.style.width = `${width}px`;
    canvas.style.height = `${height}px`;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }

  function draw(now) {
    const t = now / 1000;
    ctx.globalCompositeOperation = 'source-over';
    ctx.fillStyle = '#05060e';
    ctx.fillRect(0, 0, width, height);

    // Colour fields
    ctx.globalCompositeOperation = 'lighter';
    const base = Math.max(width, height);
    for (const b of blobs) {
      const x = (b.x + Math.sin(t * b.fx * 2) * 0.12) * width;
      const y = (b.y + Math.cos(t * b.fy * 2) * 0.1) * height;
      const r = b.r * base;
      const g = ctx.createRadialGradient(x, y, 0, x, y, r);
      g.addColorStop(0, `rgba(${b.color},0.30)`);
      g.addColorStop(0.5, `rgba(${b.color},0.10)`);
      g.addColorStop(1, `rgba(${b.color},0)`);
      ctx.fillStyle = g;
      ctx.fillRect(0, 0, width, height);
    }
    ctx.globalCompositeOperation = 'source-over';

    // Grid floor
    const horizon = height * 0.62;
    ctx.save();
    ctx.beginPath();
    ctx.rect(0, horizon, width, height - horizon);
    ctx.clip();
    const grad = ctx.createLinearGradient(0, horizon, 0, height);
    grad.addColorStop(0, 'rgba(64,220,255,0)');
    grad.addColorStop(0.45, 'rgba(110,97,255,0.35)');
    grad.addColorStop(1, 'rgba(237,84,242,0.5)');
    ctx.strokeStyle = grad;
    ctx.lineWidth = 1;
    ctx.beginPath();
    const vx = width / 2;
    const rays = 36;
    for (let i = 0; i <= rays; i++) {
      const x = (i / rays) * width * 4 - width * 1.5;
      ctx.moveTo(vx, horizon);
      ctx.lineTo(x, height);
    }
    const phase = fract(t / 1.8);
    const lines = 16;
    for (let i = 0; i < lines; i++) {
      const p = (i + phase) / lines;
      const y = horizon + (height - horizon) * p * p;
      ctx.moveTo(0, y);
      ctx.lineTo(width, y);
    }
    ctx.stroke();
    ctx.restore();

    const glow = ctx.createLinearGradient(0, horizon - 70, 0, horizon + 70);
    glow.addColorStop(0, 'rgba(237,84,242,0)');
    glow.addColorStop(0.5, 'rgba(237,84,242,0.16)');
    glow.addColorStop(1, 'rgba(237,84,242,0)');
    ctx.fillStyle = glow;
    ctx.fillRect(0, horizon - 70, width, 140);

    // Star dust
    for (const p of particles) {
      const y = fract(p.y - t * p.speed) * height;
      const x = (p.x + Math.sin(t * 0.3 + p.seed) * 0.008) * width;
      const twinkle = 0.5 + 0.5 * Math.sin(t * (1 + p.x * 2) + p.seed);
      ctx.fillStyle = `rgba(${p.color},${0.12 + twinkle * 0.45})`;
      ctx.beginPath();
      ctx.arc(x, y, p.r, 0, Math.PI * 2);
      ctx.fill();
    }

    requestAnimationFrame(draw);
  }

  window.addEventListener('resize', resize);
  resize();
  requestAnimationFrame(draw);
})();
