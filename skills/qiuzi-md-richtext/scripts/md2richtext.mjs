#!/usr/bin/env node

/**
 * Markdown → 富文本 HTML 转换脚本
 *
 * 使用方式：
 *   node md2richtext.mjs <输入MD文件路径> [输出HTML文件路径]
 *
 * 示例：
 *   node md2richtext.mjs docs/design.md
 *   node md2richtext.mjs docs/design.md docs/design-richtext.html
 *
 * 依赖（在本脚本所在目录执行一次）：
 *   npm install
 */

import { readFileSync, writeFileSync, unlinkSync, existsSync, mkdirSync } from 'fs';
import { resolve, dirname, basename, extname, join } from 'path';
import { createServer } from 'http';
import { marked } from 'marked';

const inputPath = process.argv[2];
if (!inputPath) {
  console.error('用法: node md2richtext.mjs <MD文件路径> [输出HTML路径]');
  process.exit(1);
}

const absInput = resolve(inputPath);
if (!existsSync(absInput)) {
  console.error(`文件不存在: ${absInput}`);
  process.exit(1);
}

const outputPath = process.argv[3]
  || join(dirname(absInput), basename(absInput, extname(absInput)) + '-richtext.html');
const absOutput = resolve(outputPath);
mkdirSync(dirname(absOutput), { recursive: true });

console.log(`输入: ${absInput}`);
console.log(`输出: ${absOutput}`);

const md = readFileSync(absInput, 'utf-8');

// 拦截代码块渲染：mermaid 块转为占位 div，其余代码块做 HTML 转义
const escapeHtml = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const mermaidBlocks = [];
const renderer = new marked.Renderer();
renderer.code = function ({ text, lang }) {
  if (lang === 'mermaid') {
    const idx = mermaidBlocks.length;
    mermaidBlocks.push(text);
    return `<div class="mermaid" data-idx="${idx}">${escapeHtml(text)}</div>`;
  }
  return `<pre><code>${escapeHtml(text)}</code></pre>`;
};

marked.setOptions({ renderer, gfm: true, breaks: false });
const htmlBody = marked.parse(md);

const STYLE = `
  body { background: #fff; color: #333; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Microsoft YaHei", sans-serif; line-height: 1.8; max-width: 960px; margin: 0 auto; padding: 40px 60px; }
  h1, h2, h3 { color: #1a1a1a; }
  h1 { font-size: 1.8em; border-bottom: 2px solid #e0e0e0; padding-bottom: 10px; margin: 30px 0 20px; }
  h2 { font-size: 1.4em; border-bottom: 1px solid #e0e0e0; padding-bottom: 8px; margin: 30px 0 16px; }
  h3 { font-size: 1.15em; margin: 20px 0 12px; }
  p { margin: 10px 0; }
  strong { color: #1a1a1a; }
  hr { border: none; border-top: 1px solid #e0e0e0; margin: 24px 0; }
  ul, ol { padding-left: 24px; margin: 10px 0; }
  li { margin: 4px 0; }
  code { background: #f5f5f5; color: #c7254e; padding: 2px 6px; border-radius: 3px; font-family: "Cascadia Code", "Fira Code", Consolas, monospace; font-size: 0.9em; border: 1px solid #e1e1e8; }
  pre { background: #f5f5f5; padding: 16px; border-radius: 6px; overflow-x: auto; margin: 12px 0; border: 1px solid #e0e0e0; }
  pre code { background: none; color: #333; border: none; padding: 0; }
  table { width: 100%; border-collapse: collapse; margin: 12px 0; font-size: 0.95em; }
  th { background: #f0f0f0; color: #1a1a1a; padding: 10px 12px; text-align: left; border: 1px solid #e0e0e0; font-weight: 600; }
  td { padding: 8px 12px; border: 1px solid #e0e0e0; }
  tr:nth-child(even) { background: #fafafa; }
  a { color: #0366d6; text-decoration: none; }
  .mermaid { background: #fff; text-align: center; margin: 16px 0; padding: 20px; }
`;

const fullHtml = `<!DOCTYPE html>
<html lang="zh-CN">
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Document</title>
<style>${STYLE}</style>
${mermaidBlocks.length > 0 ? '<script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>' : ''}
</head>
<body>${htmlBody}
${mermaidBlocks.length > 0 ? '<script>mermaid.initialize({ startOnLoad: true, theme: "default", securityLevel: "loose" });</script>' : ''}
</body></html>`;

if (mermaidBlocks.length === 0) {
  writeFileSync(absOutput, fullHtml, 'utf-8');
  console.log(`无 Mermaid 图表，直接输出完成: ${absOutput}`);
  process.exit(0);
}

console.log(`检测到 ${mermaidBlocks.length} 个 Mermaid 图表，启动浏览器渲染...`);

const tempHtmlPath = join(dirname(absOutput), '_temp_mermaid_render.html');
writeFileSync(tempHtmlPath, fullHtml, 'utf-8');

const server = createServer((req, res) => {
  try {
    const content = readFileSync(tempHtmlPath, 'utf-8');
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(content);
  } catch {
    res.writeHead(404);
    res.end('Not found');
  }
});

// 统一清理临时文件与服务，避免异常路径遗留
const cleanup = () => {
  server.close();
  if (existsSync(tempHtmlPath)) {
    unlinkSync(tempHtmlPath);
  }
};

server.on('error', (err) => {
  console.error(`临时服务器启动失败: ${err.message}`);
  cleanup();
  process.exit(1);
});

const PORT = 19876;
server.listen(PORT, async () => {
  console.log(`临时服务器启动: http://localhost:${PORT}`);

  let puppeteer;
  try {
    puppeteer = await import('puppeteer');
  } catch {
    console.error('请先在脚本目录执行 npm install 安装 puppeteer');
    cleanup();
    process.exit(1);
  }

  let browser;
  try {
    browser = await puppeteer.default.launch({ headless: true });
    const page = await browser.newPage();
    await page.setViewport({ width: 1200, height: 800 });
    await page.goto(`http://localhost:${PORT}`, { waitUntil: 'networkidle0', timeout: 30000 });

    try {
      await page.waitForFunction(
        (count) => document.querySelectorAll('.mermaid svg').length >= count,
        { timeout: 15000 },
        mermaidBlocks.length
      );
    } catch {
      console.warn('部分 Mermaid 图表渲染超时，继续处理已渲染的图表...');
    }
    await new Promise(r => setTimeout(r, 2000));

    // 在页面内把每个 Mermaid SVG 栅格化为 2x PNG，并替换原元素
    const resultHtml = await page.evaluate(async () => {
      const mermaidEls = Array.from(document.querySelectorAll('.mermaid'));
      const pngs = [];

      for (const el of mermaidEls) {
        const svg = el.querySelector('svg');
        if (!svg) { pngs.push(null); continue; }

        const vbAttr = svg.getAttribute('viewBox');
        if (!vbAttr) { pngs.push(null); continue; }

        const vb = vbAttr.split(' ').map(Number);
        const vbW = vb[2];
        const vbH = vb[3];
        const targetW = Math.max(vbW, 1200);
        const targetH = vbH * (targetW / vbW);

        const svgClone = svg.cloneNode(true);
        svgClone.setAttribute('width', String(targetW));
        svgClone.setAttribute('height', String(targetH));
        svgClone.style.maxWidth = 'none';

        const svgData = new XMLSerializer().serializeToString(svgClone);
        const svgBase64 = btoa(unescape(encodeURIComponent(svgData)));
        const dataUrl = 'data:image/svg+xml;base64,' + svgBase64;

        const img = new Image();
        img.crossOrigin = 'anonymous';
        await new Promise((r, j) => { img.onload = r; img.onerror = j; img.src = dataUrl; });

        const scale = 2;
        const canvas = document.createElement('canvas');
        canvas.width = targetW * scale;
        canvas.height = targetH * scale;
        const ctx = canvas.getContext('2d');
        ctx.fillStyle = '#ffffff';
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        ctx.scale(scale, scale);
        ctx.drawImage(img, 0, 0, targetW, targetH);
        pngs.push(canvas.toDataURL('image/png'));
      }

      for (let i = mermaidEls.length - 1; i >= 0; i--) {
        if (pngs[i]) {
          const div = document.createElement('div');
          div.style.cssText = 'text-align:center;margin:16px 0;';
          div.innerHTML = '<img src="' + pngs[i] + '" style="max-width:100%;border:1px solid #ddd;border-radius:4px;">';
          mermaidEls[i].parentNode.replaceChild(div, mermaidEls[i]);
        }
      }

      document.querySelectorAll('script').forEach(s => s.remove());
      return '<!DOCTYPE html>' + document.documentElement.outerHTML;
    });

    writeFileSync(absOutput, resultHtml, 'utf-8');
    console.log(`富文本 HTML 生成完成: ${absOutput}`);
  } catch (err) {
    console.error(`渲染失败: ${err.message}`);
    process.exitCode = 1;
  } finally {
    if (browser) {
      await browser.close();
    }
    cleanup();
    console.log('清理完成');
  }
});
