#include "notification_native_popup.h"

#include <algorithm>
#include <cmath>
#include <string>

#include <gdiplus.h>
#include <windows.h>
#include <windowsx.h>

#pragma comment(lib, "Gdiplus.lib")

namespace {

constexpr wchar_t kWindowClassName[] = L"QuickNotificationNativeFloatV2";
constexpr UINT_PTR kAutoCloseTimerId = 1;
constexpr UINT kAutoCloseMs = 10000;
/// 96dpi 下内容区目标宽度（再乘 DPI 缩放）；原 360 偏窄，加长以容纳标题与三按钮。
constexpr float kPanelInnerWidthDp = 440.f;
constexpr float kPanelOuterExtraDp = 24.f;

HWND g_popup_hwnd = nullptr;
bool g_class_registered = false;

void EnsureGdiplusOnce() {
  static ULONG_PTR token = 0;
  static bool started = false;
  if (!started) {
    Gdiplus::GdiplusStartupInput gin;
    Gdiplus::GdiplusStartup(&token, &gin, nullptr);
    started = true;
  }
}

std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) {
    return L"";
  }
  int size = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, nullptr, 0);
  if (size <= 0) {
    return L"";
  }
  std::wstring out(static_cast<size_t>(size), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, out.data(), size);
  if (!out.empty() && out.back() == L'\0') {
    out.pop_back();
  }
  return out;
}

void CopyToClipboard(HWND owner, const std::wstring& text) {
  if (text.empty()) {
    return;
  }
  if (!OpenClipboard(owner)) {
    return;
  }
  EmptyClipboard();
  const size_t bytes = (text.size() + 1) * sizeof(wchar_t);
  HGLOBAL h_mem = GlobalAlloc(GMEM_MOVEABLE, bytes);
  if (!h_mem) {
    CloseClipboard();
    return;
  }
  void* locked = GlobalLock(h_mem);
  if (!locked) {
    GlobalFree(h_mem);
    CloseClipboard();
    return;
  }
  memcpy(locked, text.c_str(), bytes);
  GlobalUnlock(h_mem);
  if (!SetClipboardData(CF_UNICODETEXT, h_mem)) {
    GlobalFree(h_mem);
  }
  CloseClipboard();
}

int GetWindowDpi(HWND hwnd) {
  using GetDpiForWindowFn = UINT(WINAPI*)(HWND);
  static GetDpiForWindowFn fn = reinterpret_cast<GetDpiForWindowFn>(
      GetProcAddress(GetModuleHandleW(L"user32.dll"), "GetDpiForWindow"));
  if (fn && hwnd) {
    return static_cast<int>(fn(hwnd));
  }
  return 96;
}

void AddRoundRect(Gdiplus::GraphicsPath* path, float x, float y, float w, float h,
                  float r) {
  r = (std::min)(r, (std::min)(w, h) * 0.5f);
  const float d = 2.f * r;
  path->AddArc(x + w - d, y, d, d, 270, 90);
  path->AddArc(x + w - d, y + h - d, d, d, 0, 90);
  path->AddArc(x, y + h - d, d, d, 90, 90);
  path->AddArc(x, y, d, d, 180, 90);
  path->CloseFigure();
}

void FillRoundRect(Gdiplus::Graphics& g, Gdiplus::Brush& br, float x, float y,
                   float w, float h, float r) {
  Gdiplus::GraphicsPath path;
  AddRoundRect(&path, x, y, w, h, r);
  g.FillPath(&br, &path);
}

void DrawRoundRect(Gdiplus::Graphics& g, const Gdiplus::Pen& pen, float x, float y,
                   float w, float h, float r) {
  Gdiplus::GraphicsPath path;
  AddRoundRect(&path, x, y, w, h, r);
  g.DrawPath(&pen, &path);
}

void DrawBellIcon(Gdiplus::Graphics& g, float x, float y, float box, float r) {
  Gdiplus::SolidBrush blue(Gdiplus::Color(255, 0, 120, 215));
  FillRoundRect(g, blue, x, y, box, box, r);

  Gdiplus::SolidBrush white(Gdiplus::Color(255, 255, 255, 255));
  const float cx = x + box * 0.5f;
  const float bell_top = y + box * 0.26f;
  const float bell_w = box * 0.52f;
  const float bell_h = box * 0.42f;
  g.FillEllipse(&white, cx - bell_w * 0.5f, bell_top, bell_w, bell_h);
  const float stem_w = box * 0.14f;
  const float stem_h = box * 0.1f;
  g.FillRectangle(&white, cx - stem_w * 0.5f, y + box * 0.66f, stem_w, stem_h);
}

void DrawCloseX(Gdiplus::Graphics& g, float x, float y, float sz,
                const Gdiplus::Pen& pen) {
  g.DrawLine(&pen, x, y, x + sz, y + sz);
  g.DrawLine(&pen, x + sz, y, x, y + sz);
}

struct PopupData {
  std::wstring header_title;
  std::wstring time_str;
  std::wstring code;
  std::wstring code_label;
  std::wstring subtitle;
  std::wstring from_label;
  std::wstring copy_payload;
  HWND owner_hwnd = nullptr;

  RECT rc_close{};   // screen coords not used; client coords
  RECT rc_time{};    // 时间条带：关闭按钮左侧，与 × 同一行
  RECT rc_copy{};
  RECT rc_open{};
  RECT rc_ignore{};
  int client_w = 0;
  int client_h = 0;
  int shadow_px = 0;
  int pad_px = 0;
};

PopupData* GetData(HWND hwnd) {
  return reinterpret_cast<PopupData*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));
}

void LayoutClientRects(PopupData* d, float s) {
  d->shadow_px = static_cast<int>(std::ceil(8.f * s));
  d->pad_px = static_cast<int>(std::ceil(16.f * s));
  const int sh = d->shadow_px;
  const int pad = d->pad_px;
  const int cw = d->client_w;
  const int ch = d->client_h;
  const int btn_h = static_cast<int>(std::ceil(40.f * s));
  const int btn_gap = static_cast<int>(std::ceil(8.f * s));
  const int btn_y = ch - sh - pad - btn_h;
  const int inner = cw - 2 * (sh + pad);
  const int btn_w = (inner - btn_gap * 2) / 3;

  SetRect(&d->rc_copy, sh + pad, btn_y, sh + pad + btn_w, btn_y + btn_h);
  SetRect(&d->rc_open, sh + pad + btn_w + btn_gap, btn_y,
          sh + pad + btn_w + btn_gap + btn_w, btn_y + btn_h);
  SetRect(&d->rc_ignore, sh + pad + (btn_w + btn_gap) * 2, btn_y, cw - sh - pad,
          btn_y + btn_h);

  const int close_sz = static_cast<int>(std::ceil(30.f * s));
  const int header_h = static_cast<int>(std::ceil(40.f * s));
  const int close_top = sh + pad + (header_h - close_sz) / 2;
  SetRect(&d->rc_close, cw - sh - pad - close_sz, close_top, cw - sh - pad,
          close_top + close_sz);

  const int time_w = static_cast<int>(std::ceil(64.f * s));
  const int time_gap = static_cast<int>(std::ceil(8.f * s));
  const int time_right = d->rc_close.left - time_gap;
  SetRect(&d->rc_time, time_right - time_w, close_top, time_right,
          close_top + close_sz);
}

void PaintPopup(HWND hwnd, PopupData* d) {
  PAINTSTRUCT ps{};
  HDC hdc = BeginPaint(hwnd, &ps);
  RECT rc{};
  GetClientRect(hwnd, &rc);

  Gdiplus::Graphics g(hdc);
  g.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
  g.SetTextRenderingHint(Gdiplus::TextRenderingHintClearTypeGridFit);
  g.SetPixelOffsetMode(Gdiplus::PixelOffsetModeHalf);

  const int dpi = GetWindowDpi(hwnd);
  const float s = static_cast<float>(dpi) / 96.f;

  const float shadow = 8.f * s;
  const float panel_r = 18.f * s;
  const float btn_r = 8.f * s;
  const float pad = 16.f * s;
  const float box = 40.f * s;
  const float icon_r = 8.f * s;

  Gdiplus::SolidBrush shadow_br(Gdiplus::Color(90, 0, 0, 0));
  FillRoundRect(g, shadow_br, shadow * 0.5f, shadow * 0.6f,
                static_cast<float>(rc.right) - shadow, static_cast<float>(rc.bottom) - shadow,
                panel_r + 4.f * s);

  Gdiplus::SolidBrush panel(Gdiplus::Color(255, 26, 26, 26));
  FillRoundRect(g, panel, shadow, shadow, static_cast<float>(rc.right) - 2.f * shadow,
                static_cast<float>(rc.bottom) - 2.f * shadow, panel_r);

  const float ox = shadow + pad;
  const float oy = shadow + pad;

  DrawBellIcon(g, ox, oy, box, icon_r);

  Gdiplus::FontFamily ff(L"Segoe UI");
  Gdiplus::StringFormat fmt;
  fmt.SetAlignment(Gdiplus::StringAlignmentNear);
  fmt.SetLineAlignment(Gdiplus::StringAlignmentCenter);
  fmt.SetTrimming(Gdiplus::StringTrimmingEllipsisCharacter);
  fmt.SetFormatFlags(Gdiplus::StringFormatFlagsNoWrap);

  Gdiplus::SolidBrush text_pri(Gdiplus::Color(255, 255, 255, 255));
  Gdiplus::SolidBrush text_sec(Gdiplus::Color(255, 160, 160, 160));
  Gdiplus::SolidBrush accent(Gdiplus::Color(255, 0, 120, 215));

  const float title_x = ox + box + 10.f * s;
  const float title_gap = 8.f * s;
  const float title_w = (std::max)(
      40.f, static_cast<float>(d->rc_time.left) - title_x - title_gap);
  Gdiplus::Font font_title(&ff, 14.f * s, Gdiplus::FontStyleRegular,
                            Gdiplus::UnitPixel);
  Gdiplus::RectF rf_title(title_x, oy, title_w, box);
  g.DrawString(d->header_title.c_str(), -1, &font_title, rf_title, &fmt,
               &text_pri);

  Gdiplus::Font font_time(&ff, 12.f * s, Gdiplus::FontStyleRegular,
                           Gdiplus::UnitPixel);
  Gdiplus::StringFormat fmt_r;
  fmt_r.SetAlignment(Gdiplus::StringAlignmentFar);
  fmt_r.SetLineAlignment(Gdiplus::StringAlignmentCenter);
  fmt_r.SetTrimming(Gdiplus::StringTrimmingEllipsisCharacter);
  fmt_r.SetFormatFlags(Gdiplus::StringFormatFlagsNoWrap);
  const float tw = static_cast<float>(d->rc_time.right - d->rc_time.left);
  const float th = static_cast<float>(d->rc_time.bottom - d->rc_time.top);
  Gdiplus::RectF rf_time(static_cast<float>(d->rc_time.left),
                         static_cast<float>(d->rc_time.top), tw, th);
  g.DrawString(d->time_str.c_str(), -1, &font_time, rf_time, &fmt_r, &text_sec);

  Gdiplus::Pen pen_x(Gdiplus::Color(255, 200, 200, 200), 1.35f * s);
  const float cx0 = static_cast<float>(d->rc_close.left);
  const float cy0 = static_cast<float>(d->rc_close.top);
  const float csz = static_cast<float>(d->rc_close.right - d->rc_close.left);
  DrawCloseX(g, cx0 + csz * 0.28f, cy0 + csz * 0.28f, csz * 0.44f, pen_x);

  const float body_y = oy + box + 14.f * s;
  Gdiplus::Font font_label(&ff, 14.f * s, Gdiplus::FontStyleRegular,
                           Gdiplus::UnitPixel);
  Gdiplus::StringFormat fmt_left;
  fmt_left.SetAlignment(Gdiplus::StringAlignmentNear);
  fmt_left.SetLineAlignment(Gdiplus::StringAlignmentNear);

  const bool has_code_label = !d->code_label.empty();
  const float code_x = has_code_label ? (ox + 58.f * s) : ox;
  if (has_code_label) {
    Gdiplus::RectF rf_lab(ox, body_y, 80.f * s, 40.f * s);
    g.DrawString(d->code_label.c_str(), -1, &font_label, rf_lab, &fmt_left,
                 &text_pri);
  }
  // 验证码保留醒目字号；普通正文场景降级字号，避免内容过大被裁切。
  const float code_font_px = has_code_label ? (30.f * s) : (20.f * s);
  const float code_block_h = has_code_label ? (48.f * s) : (58.f * s);
  Gdiplus::Font font_code(&ff, code_font_px, Gdiplus::FontStyleBold, Gdiplus::UnitPixel);
  Gdiplus::RectF rf_code(code_x, body_y - 2.f * s,
                         static_cast<float>(rc.right) - code_x - shadow - pad,
                         code_block_h);
  g.DrawString(d->code.c_str(), -1, &font_code, rf_code, &fmt_left, &accent);

  const float sub_y = body_y + (has_code_label ? (38.f * s) : (52.f * s));
  Gdiplus::Font font_sub(&ff, 12.f * s, Gdiplus::FontStyleRegular,
                         Gdiplus::UnitPixel);
  Gdiplus::RectF rf_sub(ox, sub_y, static_cast<float>(rc.right) - ox - shadow - pad,
                        40.f * s);
  g.DrawString(d->subtitle.c_str(), -1, &font_sub, rf_sub, &fmt_left, &text_sec);

  const float from_y = sub_y + 20.f * s;
  Gdiplus::RectF rf_from(ox, from_y, static_cast<float>(rc.right) - ox - shadow - pad,
                         40.f * s);
  if (!d->from_label.empty()) {
    g.DrawString(d->from_label.c_str(), -1, &font_sub, rf_from, &fmt_left,
                 &text_sec);
  }

  Gdiplus::SolidBrush btn_bg(Gdiplus::Color(255, 45, 45, 45));
  Gdiplus::Font font_btn(&ff, 13.f * s, Gdiplus::FontStyleRegular,
                         Gdiplus::UnitPixel);
  Gdiplus::StringFormat fmt_c;
  fmt_c.SetAlignment(Gdiplus::StringAlignmentCenter);
  fmt_c.SetLineAlignment(Gdiplus::StringAlignmentCenter);

  Gdiplus::Pen btn_border(Gdiplus::Color(255, 58, 58, 58), 1.f * s);
  auto draw_btn = [&](const RECT& r, const wchar_t* txt) {
    FillRoundRect(g, btn_bg, static_cast<float>(r.left), static_cast<float>(r.top),
                  static_cast<float>(r.right - r.left),
                  static_cast<float>(r.bottom - r.top), btn_r);
    DrawRoundRect(g, btn_border, static_cast<float>(r.left) + 0.5f,
                  static_cast<float>(r.top) + 0.5f,
                  static_cast<float>(r.right - r.left) - 1.f,
                  static_cast<float>(r.bottom - r.top) - 1.f, btn_r);
    Gdiplus::RectF rf(static_cast<float>(r.left), static_cast<float>(r.top),
                      static_cast<float>(r.right - r.left),
                      static_cast<float>(r.bottom - r.top));
    g.DrawString(txt, -1, &font_btn, rf, &fmt_c, &text_pri);
  };

  const wchar_t t_copy[] = L"复制";
  const wchar_t t_open[] = L"打开应用";
  const wchar_t t_ign[] = L"忽略";
  draw_btn(d->rc_copy, t_copy);
  draw_btn(d->rc_open, t_open);
  draw_btn(d->rc_ignore, t_ign);

  EndPaint(hwnd, &ps);
}

int CalcClientHeight(float s) {
  const float pad = 16.f * s;
  const float box = 40.f * s;
  const float gap1 = 14.f * s;
  // 留出更宽松正文区，避免非验证码长文本时显示不全。
  const float code_block = 60.f * s;
  const float sub = 20.f * s;
  const float from = 20.f * s;
  const float gap2 = 12.f * s;
  const float btn = 40.f * s;
  const float shadow = 8.f * s;
  const float h = pad + box + gap1 + code_block + sub + from + gap2 + btn + pad;
  return static_cast<int>(std::ceil(h + 2.f * shadow));
}

LRESULT CALLBACK PopupWndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
  switch (msg) {
    case WM_CREATE: {
      auto* cs = reinterpret_cast<CREATESTRUCT*>(lp);
      auto* data = reinterpret_cast<PopupData*>(cs->lpCreateParams);
      SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(data));
      SetTimer(hwnd, kAutoCloseTimerId, kAutoCloseMs, nullptr);
      return 0;
    }
    case WM_TIMER:
      if (wp == kAutoCloseTimerId) {
        KillTimer(hwnd, kAutoCloseTimerId);
        DestroyWindow(hwnd);
      }
      return 0;
    case WM_DESTROY: {
      KillTimer(hwnd, kAutoCloseTimerId);
      PopupData* d = GetData(hwnd);
      if (d) {
        delete d;
        SetWindowLongPtr(hwnd, GWLP_USERDATA, 0);
      }
      if (g_popup_hwnd == hwnd) {
        g_popup_hwnd = nullptr;
      }
      return 0;
    }
    case WM_ERASEBKGND:
      return 1;
    case WM_LBUTTONDOWN: {
      PopupData* d = GetData(hwnd);
      if (!d) {
        return 0;
      }
      const int x = GET_X_LPARAM(lp);
      const int y = GET_Y_LPARAM(lp);
      POINT pt{x, y};

      auto hit = [&](const RECT& r) {
        return PtInRect(&r, pt) != 0;
      };

      if (hit(d->rc_close)) {
        DestroyWindow(hwnd);
        return 0;
      }
      if (hit(d->rc_copy)) {
        const std::wstring clip =
            d->copy_payload.empty() ? d->code : d->copy_payload;
        CopyToClipboard(hwnd, clip);
        return 0;
      }
      if (hit(d->rc_open)) {
        if (d->owner_hwnd && IsWindow(d->owner_hwnd)) {
          ShowWindow(d->owner_hwnd, SW_RESTORE);
          SetForegroundWindow(d->owner_hwnd);
        }
        DestroyWindow(hwnd);
        return 0;
      }
      if (hit(d->rc_ignore)) {
        DestroyWindow(hwnd);
        return 0;
      }
      return 0;
    }
    case WM_PAINT: {
      PopupData* d = GetData(hwnd);
      if (d) {
        PaintPopup(hwnd, d);
      } else {
        PAINTSTRUCT ps{};
        BeginPaint(hwnd, &ps);
        EndPaint(hwnd, &ps);
      }
      return 0;
    }
    default:
      return DefWindowProc(hwnd, msg, wp, lp);
  }
}

void EnsureWindowClass() {
  if (g_class_registered) {
    return;
  }
  WNDCLASSEXW wc{};
  wc.cbSize = sizeof(wc);
  wc.lpfnWndProc = PopupWndProc;
  wc.hInstance = GetModuleHandle(nullptr);
  wc.lpszClassName = kWindowClassName;
  wc.hbrBackground = reinterpret_cast<HBRUSH>(GetStockObject(BLACK_BRUSH));
  wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
  RegisterClassExW(&wc);
  g_class_registered = true;
}

}  // namespace

void NotificationNativePopupClose() {
  if (g_popup_hwnd && IsWindow(g_popup_hwnd)) {
    DestroyWindow(g_popup_hwnd);
  }
  g_popup_hwnd = nullptr;
}

void NotificationNativePopupShow(HWND owner_root_hwnd,
                                   const std::string& header_title_utf8,
                                   const std::string& time_utf8,
                                   const std::string& code_utf8,
                                   const std::string& code_label_utf8,
                                   const std::string& subtitle_utf8,
                                   const std::string& from_label_utf8,
                                   const std::string& copy_payload_utf8) {
  NotificationNativePopupClose();
  EnsureWindowClass();
  EnsureGdiplusOnce();

  HWND dpi_ref = owner_root_hwnd ? owner_root_hwnd : GetDesktopWindow();
  const int dpi = GetWindowDpi(dpi_ref);
  const float s = static_cast<float>(dpi) / 96.f;

  const int client_w = static_cast<int>(
      std::ceil(kPanelInnerWidthDp * s + kPanelOuterExtraDp * s));
  const int client_h = CalcClientHeight(s);

  std::wstring copy_w = Utf8ToWide(copy_payload_utf8);
  if (copy_w.empty()) {
    copy_w = Utf8ToWide(code_utf8);
  }

  auto* data = new PopupData{
      Utf8ToWide(header_title_utf8),
      Utf8ToWide(time_utf8),
      Utf8ToWide(code_utf8),
      Utf8ToWide(code_label_utf8),
      Utf8ToWide(subtitle_utf8),
      Utf8ToWide(from_label_utf8),
      copy_w,
      owner_root_hwnd,
      {},
      {},
      {},
      {},
      {},
      client_w,
      client_h,
      0,
      0,
  };
  LayoutClientRects(data, s);

  HMONITOR mon = MonitorFromWindow(dpi_ref, MONITOR_DEFAULTTONEAREST);
  MONITORINFO mi{};
  mi.cbSize = sizeof(mi);
  RECT work{0, 0, 1920, 1080};
  if (mon && GetMonitorInfoW(mon, &mi)) {
    work = mi.rcWork;
  }

  const int left = work.right - client_w - 12;
  const int top = work.bottom - client_h - 12;

  HWND hwnd = CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW, kWindowClassName, L"",
      WS_POPUP, left, top, client_w, client_h, nullptr, nullptr,
      GetModuleHandle(nullptr), data);

  if (!hwnd) {
    delete data;
    return;
  }

  g_popup_hwnd = hwnd;
  ShowWindow(hwnd, SW_SHOWNA);
  UpdateWindow(hwnd);
}
