---
name: qiuzi-md-richtext
description: >-
  将 Markdown 文件转为可复制粘贴到富文本编辑器的自包含 HTML 文件，Mermaid 图表渲染为内嵌 PNG 图片。
  当用户提到"MD 转富文本"、"Markdown 转 HTML"、"文档导出"、"复制到飞书/腾讯文档/企业微信/邮件"时使用。
---

# Markdown → 富文本 HTML 转换

将含 Mermaid 图表的 Markdown 文件转为自包含的富文本 HTML，可直接在浏览器中全选复制后粘贴到任何富文本编辑器。

## 输出约定

- 输入：`xxx.md`
- 输出：`xxx-richtext.html`（默认与输入文件同目录，可显式指定输出路径）
- 必须使用浅色/白底主题，图片使用 2x 缩放保证高清
- 最终 HTML 不含任何 `<script>`，Mermaid 图表全部替换为 `<img src="data:image/png;base64,...">`

## 方案一：脚本转换（优先）

脚本位于 `scripts/md2richtext.mjs`，依赖 `marked` 与 `puppeteer`。

首次使用先在脚本目录安装依赖：

```powershell
$skillRoot = Join-Path $HOME '.agents\skills\qiuzi-md-richtext'
npm install --prefix (Join-Path $skillRoot 'scripts')
```

执行转换：

```powershell
$skillRoot = Join-Path $HOME '.agents\skills\qiuzi-md-richtext'
node (Join-Path $skillRoot 'scripts\md2richtext.mjs') <MD文件路径> [输出HTML路径]
```

以上路径对应仓库安装脚本的默认目标目录；若使用自定义 `-TargetRoot`，将 `$skillRoot` 替换为实际安装目录。

`npm install` 时 Puppeteer 会下载一份 Chrome（约 170 MB）。网络较慢或本机已有 Chrome 时，可跳过下载并指定可执行文件：

```powershell
$env:PUPPETEER_SKIP_DOWNLOAD = '1'
npm install --prefix (Join-Path $skillRoot 'scripts')
$env:PUPPETEER_EXECUTABLE_PATH = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
```

脚本行为：

1. 用 `marked` 解析 Markdown，Mermaid 代码块转为 `<div class="mermaid">`
2. 无 Mermaid 时直接写出 HTML 并退出
3. 有 Mermaid 时启动本地 HTTP 服务（端口 19876），用 Puppeteer 无头浏览器加载页面
4. 等待 Mermaid SVG 渲染完成，将 SVG 转为 2x PNG 并替换原元素
5. 移除脚本标签，写出最终 HTML，清理临时文件与服务

完成后向用户报告输出路径，并提示"浏览器打开 → Ctrl+A → Ctrl+C → 粘贴到目标编辑器"。

## 方案二：Playwright MCP 手动流程（脚本不可用时）

当本机无法安装 Puppeteer，但有 Playwright MCP 时，按以下步骤手动执行。

### Step 1：生成带 Mermaid JS 的中间 HTML

在 MD 同目录创建临时文件（后缀 `-temp.html`）：

- 引入 CDN：`https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js`
- Mermaid 代码块转为 `<div class="mermaid">...</div>`
- 其他 Markdown 转为对应 HTML 标签
- 样式内联到 `<style>`，采用与脚本一致的浅色配色：

```css
body { background: #fff; color: #333; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Microsoft YaHei", sans-serif; line-height: 1.8; max-width: 960px; margin: 0 auto; padding: 40px 60px; }
h1, h2, h3 { color: #1a1a1a; }
h1 { border-bottom: 2px solid #e0e0e0; }
h2 { border-bottom: 1px solid #e0e0e0; }
code { background: #f5f5f5; color: #c7254e; padding: 2px 6px; border-radius: 3px; border: 1px solid #e1e1e8; }
pre { background: #f5f5f5; border: 1px solid #e0e0e0; border-radius: 6px; padding: 16px; }
pre code { background: none; color: #333; border: none; }
table { width: 100%; border-collapse: collapse; }
th { background: #f0f0f0; font-weight: 600; }
th, td { padding: 8px 12px; border: 1px solid #e0e0e0; }
tr:nth-child(even) { background: #fafafa; }
.mermaid { background: #fff; text-align: center; margin: 16px 0; }
```

### Step 2：启动 HTTP 服务并渲染

1. 用 `npx http-server` 在临时端口（如 18923）服务该目录
2. 用 `browser_navigate` 打开页面
3. 用 `browser_run_code` 等待渲染完成：

```javascript
await page.waitForFunction(() => {
  return document.querySelectorAll('.mermaid svg').length >= EXPECTED_COUNT;
}, { timeout: 15000 });
await page.waitForTimeout(1500);
```

### Step 3：SVG 转内嵌 PNG

在 `page.evaluate` 中执行：

```javascript
const mermaidEls = Array.from(document.querySelectorAll('.mermaid'));
const pngs = [];
for (const el of mermaidEls) {
  const svg = el.querySelector('svg');
  const vb = svg.getAttribute('viewBox').split(' ').map(Number);
  const targetW = Math.max(vb[2], 1200);
  const targetH = vb[3] * (targetW / vb[2]);
  const svgClone = svg.cloneNode(true);
  svgClone.setAttribute('width', String(targetW));
  svgClone.setAttribute('height', String(targetH));
  svgClone.style.maxWidth = 'none';
  const svgData = new XMLSerializer().serializeToString(svgClone);
  const svgBase64 = btoa(unescape(encodeURIComponent(svgData)));
  const img = new Image();
  img.crossOrigin = 'anonymous';
  await new Promise((r, j) => { img.onload = r; img.onerror = j; img.src = 'data:image/svg+xml;base64,' + svgBase64; });
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
  const div = document.createElement('div');
  div.style.cssText = 'text-align:center;margin:16px 0;';
  div.innerHTML = '<img src="' + pngs[i] + '" style="max-width:100%;border:1px solid #ddd;border-radius:4px;">';
  mermaidEls[i].parentNode.replaceChild(div, mermaidEls[i]);
}
document.querySelectorAll('script').forEach(s => s.remove());
```

### Step 4：下载并落盘

```javascript
const html = document.documentElement.outerHTML;
const blob = new Blob(['<!DOCTYPE html>' + html], { type: 'text/html;charset=utf-8' });
const a = document.createElement('a');
a.href = URL.createObjectURL(blob);
a.download = 'TARGET_FILENAME.html';
document.body.appendChild(a);
a.click();
```

文件会下载到 `.playwright-mcp/` 目录，用 `cmd /c copy` 复制到目标位置。

### Step 5：清理

- 停止 HTTP 服务（`taskkill /PID xxx /F`）
- 删除临时 HTML 文件，保留最终富文本 HTML

## 注意事项

- MD 中没有 Mermaid 图表时，跳过浏览器渲染，直接生成纯 HTML
- 浅色主题是必须的，富文本编辑器通常为白底
- Windows 上含中文路径的文件操作使用 `cmd /c`，避免 PowerShell 编码问题
- 脚本使用本地端口 19876 提供临时页面，监听失败时会报错退出并清理临时文件
