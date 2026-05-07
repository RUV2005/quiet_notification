// Tauri 2.x 在静态文件模式下通过 window.__TAURI__ 访问 API
// 无需 npm / bundle，直接使用全局注入的对象

async function getAppWindow() {
  if (window.__TAURI__?.window) {
    const { getCurrentWindow } = window.__TAURI__.window;
    return getCurrentWindow();
  }
  return null;
}

async function clipboardWrite(text) {
  if (window.__TAURI__?.pluginClipboardManager) {
    await window.__TAURI__.pluginClipboardManager.writeText(text);
  } else {
    await navigator.clipboard?.writeText(text);
  }
}

// ── 窗口控制 ────────────────────────────────────────────
document.getElementById("btn-minimize")?.addEventListener("click", async () => {
  const win = await getAppWindow();
  win?.minimize();
});

document.getElementById("btn-close")?.addEventListener("click", async () => {
  const win = await getAppWindow();
  win?.hide();
});

let pinned = false;
document.getElementById("btn-pin")?.addEventListener("click", async (e) => {
  pinned = !pinned;
  const win = await getAppWindow();
  win?.setAlwaysOnTop(pinned);
  e.currentTarget.style.color = pinned ? "#3b82f6" : "";
});

// ── 标签切换 ────────────────────────────────────────────
const tabs = document.querySelectorAll(".tab[data-tab]");
const items = document.querySelectorAll(".notif-item[data-category]");

tabs.forEach((tab) => {
  tab.addEventListener("click", () => {
    tabs.forEach((t) => t.classList.remove("active"));
    tab.classList.add("active");

    const key = tab.dataset.tab;
    items.forEach((item) => {
      if (key === "all") {
        item.classList.remove("hidden");
      } else {
        const cats = item.dataset.category || "";
        item.classList.toggle("hidden", !cats.includes(key));
      }
    });
  });
});

// ── 复制验证码 ───────────────────────────────────────────
document.querySelectorAll(".copy-btn").forEach((btn) => {
  btn.addEventListener("click", async () => {
    const code = btn.dataset.code;
    await clipboardWrite(code);

    btn.classList.add("copied");
    btn.innerHTML = `<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg> 已复制`;
    setTimeout(() => {
      btn.classList.remove("copied");
      btn.innerHTML = `<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg> 复制 <span class="chevron">›</span>`;
    }, 2000);
  });
});
// 手动实现窗口拖动
const dragRegion = document.querySelector('[data-tauri-drag-region]');
if (dragRegion) {
  dragRegion.addEventListener('mousedown', async (e) => {
    if (e.button === 0) {
      const win = await getAppWindow();
      win?.startDragging();
    }
  });
}
