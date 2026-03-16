#include "flutter_window.h"

#include <windows.h>
#include <shellapi.h>
#include <algorithm>
#include <cstdint>
#include <cmath>
#include <string>
#include <optional>
#include <cwchar>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {
constexpr wchar_t kIslandWindowClass[] = L"NOTES_BRIDGE_ISLAND_OVERLAY";
constexpr int kIslandExpandedWidth = 680;
constexpr int kIslandExpandedHeight = 180;
constexpr int kIslandCollapsedWidth = 240;
constexpr int kIslandCollapsedHeight = 64;
constexpr int kIslandHoverWidth = 420;
constexpr int kIslandTop = 12;
constexpr UINT_PTR kIslandTimerId = 1;
constexpr UINT kIslandFrameMs = 16;
constexpr int kExpandMs = 280;
constexpr int kCollapseMs = 240;
constexpr UINT kTrayCallbackMessage = WM_APP + 77;
constexpr UINT kTrayIconId = 1001;
constexpr UINT_PTR kTrayMenuOpenId = 40001;
constexpr UINT_PTR kTrayMenuExitId = 40002;
#ifndef NIN_SELECT
#define NIN_SELECT (WM_USER + 0)
#endif
#ifndef NIN_KEYSELECT
#define NIN_KEYSELECT (WM_USER + 1)
#endif

HWND g_island_hwnd = nullptr;
HWND g_main_hwnd = nullptr;
std::wstring g_island_title;
std::wstring g_island_body;
int g_hold_duration_ms = 2600;
int g_current_width = kIslandCollapsedWidth;
int g_current_height = kIslandCollapsedHeight;
BYTE g_current_alpha = 0;
int g_vertical_offset = -8;
double g_open_progress = 0.0;
bool g_island_visible = false;
bool g_hovered = false;
bool g_clock_mode_enabled = true;
bool g_force_exit = false;
std::wstring g_clock_text = L"00:00:00";
ULONGLONG g_last_clock_tick_ms = 0;
NOTIFYICONDATAW g_tray_icon = {};
bool g_tray_added = false;

HFONT g_title_font_large = nullptr;
HFONT g_title_font_small = nullptr;
HFONT g_body_font = nullptr;
HPEN g_border_pen = nullptr;
HPEN g_separator_pen = nullptr;
HBRUSH g_bg_brush = nullptr;
HBRUSH g_dot_brush = nullptr;
HBRUSH g_transparent_key_brush = nullptr;
constexpr COLORREF kTransparentKey = RGB(255, 0, 255);

enum class IslandPhase { kHidden, kExpanding, kHolding, kCollapsing };
IslandPhase g_phase = IslandPhase::kHidden;
ULONGLONG g_phase_start_ms = 0;

double Clamp01(double value) {
  return std::max(0.0, std::min(1.0, value));
}

double EaseOutCubic(double t) {
  const double x = 1.0 - Clamp01(t);
  return 1.0 - x * x * x;
}

double EaseInCubic(double t) {
  const double x = Clamp01(t);
  return x * x * x;
}

double EaseOutBack(double t) {
  const double x = Clamp01(t);
  const double c1 = 1.70158;
  const double c3 = c1 + 1.0;
  return 1 + c3 * std::pow(x - 1, 3) + c1 * std::pow(x - 1, 2);
}

COLORREF LerpColor(COLORREF from, COLORREF to, double t) {
  const double x = Clamp01(t);
  const int r = static_cast<int>(GetRValue(from) + (GetRValue(to) - GetRValue(from)) * x);
  const int g = static_cast<int>(GetGValue(from) + (GetGValue(to) - GetGValue(from)) * x);
  const int b = static_cast<int>(GetBValue(from) + (GetBValue(to) - GetBValue(from)) * x);
  return RGB(r, g, b);
}

void EnsurePaintResources() {
  if (!g_title_font_large) {
    g_title_font_large = CreateFontW(34, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                                     OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                                     DEFAULT_PITCH | FF_SWISS, L"Segoe UI");
  }
  if (!g_title_font_small) {
    g_title_font_small = CreateFontW(41, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                                     OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                                     DEFAULT_PITCH | FF_SWISS, L"Segoe UI");
  }
  if (!g_body_font) {
    g_body_font = CreateFontW(22, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                              OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                              DEFAULT_PITCH | FF_SWISS, L"Segoe UI");
  }
  if (!g_border_pen) g_border_pen = CreatePen(PS_SOLID, 1, RGB(34, 34, 38));
  if (!g_separator_pen) g_separator_pen = CreatePen(PS_SOLID, 1, RGB(28, 28, 32));
  if (!g_bg_brush) g_bg_brush = CreateSolidBrush(RGB(9, 9, 11));
  if (!g_dot_brush) g_dot_brush = CreateSolidBrush(RGB(242, 242, 248));
  if (!g_transparent_key_brush) g_transparent_key_brush = CreateSolidBrush(kTransparentKey);
}

void RepositionIslandWindow(bool show) {
  if (!g_island_hwnd) return;
  const int screen_width = GetSystemMetrics(SM_CXSCREEN);
  const int left = (screen_width - kIslandExpandedWidth) / 2;

  if (show && !g_island_visible) {
    ShowWindow(g_island_hwnd, SW_SHOWNOACTIVATE);
    g_island_visible = true;
  }

  SetWindowPos(
      g_island_hwnd,
      HWND_TOPMOST,
      left,
      kIslandTop + g_vertical_offset,
      kIslandExpandedWidth,
      kIslandExpandedHeight,
      SWP_NOACTIVATE | SWP_NOZORDER);
  SetLayeredWindowAttributes(g_island_hwnd, kTransparentKey, g_current_alpha, LWA_COLORKEY | LWA_ALPHA);
}

void UpdateClockText() {
  SYSTEMTIME st;
  GetLocalTime(&st);
  wchar_t buf[16];
  std::swprintf(buf, 16, L"%02d:%02d:%02d", st.wHour, st.wMinute, st.wSecond);
  g_clock_text = buf;
}

void ShowMainWindow() {
  if (!g_main_hwnd) return;
  ShowWindow(g_main_hwnd, SW_SHOW);
  ShowWindow(g_main_hwnd, SW_RESTORE);
  SetForegroundWindow(g_main_hwnd);
}

void HideMainWindow() {
  if (!g_main_hwnd) return;
  ShowWindow(g_main_hwnd, SW_HIDE);
}

void RemoveTrayIcon() {
  if (!g_tray_added) return;
  Shell_NotifyIconW(NIM_DELETE, &g_tray_icon);
  g_tray_added = false;
}

void EnsureTrayIcon(HWND hwnd) {
  if (g_tray_added) return;
  g_tray_icon = {};
  g_tray_icon.cbSize = sizeof(NOTIFYICONDATAW);
  g_tray_icon.hWnd = hwnd;
  g_tray_icon.uID = kTrayIconId;
  g_tray_icon.uVersion = NOTIFYICON_VERSION_4;
  g_tray_icon.uCallbackMessage = kTrayCallbackMessage;
  g_tray_icon.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  g_tray_icon.hIcon = LoadIconW(GetModuleHandle(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON));
  wcscpy_s(g_tray_icon.szTip, L"Notes Bridge - Running in background");
  if (Shell_NotifyIconW(NIM_ADD, &g_tray_icon)) {
    Shell_NotifyIconW(NIM_SETVERSION, &g_tray_icon);
    g_tray_added = true;
  }
}

void TickClockIsland() {
  const ULONGLONG now = GetTickCount64();
  if (g_last_clock_tick_ms == 0 || now - g_last_clock_tick_ms >= 1000) {
    g_last_clock_tick_ms = now;
    UpdateClockText();
  }

  const int target_width = g_hovered ? kIslandHoverWidth : kIslandCollapsedWidth;
  const int target_height = kIslandCollapsedHeight;
  const int target_alpha = 235;
  const int target_offset = 0;

  g_current_width += static_cast<int>((target_width - g_current_width) * 0.18);
  g_current_height += static_cast<int>((target_height - g_current_height) * 0.18);
  g_vertical_offset += static_cast<int>((target_offset - g_vertical_offset) * 0.18);
  const int alpha_delta = static_cast<int>((target_alpha - g_current_alpha) * 0.2);
  const int next_alpha = std::clamp(static_cast<int>(g_current_alpha) + alpha_delta, 0, 255);
  g_current_alpha = static_cast<BYTE>(next_alpha);
  g_open_progress = g_hovered ? 1.0 : 0.0;

  RepositionIslandWindow(true);
  InvalidateRect(g_island_hwnd, nullptr, TRUE);
}

void BeginPhase(IslandPhase phase) {
  g_phase = phase;
  g_phase_start_ms = GetTickCount64();
}

void TickIslandAnimation() {
  if (!g_island_hwnd) return;

  if (g_phase == IslandPhase::kHidden && g_clock_mode_enabled) {
    TickClockIsland();
    return;
  }

  const ULONGLONG now = GetTickCount64();
  if (g_last_clock_tick_ms == 0 || now - g_last_clock_tick_ms >= 1000) {
    g_last_clock_tick_ms = now;
    UpdateClockText();
  }

  if (g_phase == IslandPhase::kExpanding) {
    const double t = Clamp01(static_cast<double>(now - g_phase_start_ms) / kExpandMs);
    const double top_t = Clamp01(t / 0.42);
    const double panel_t = Clamp01((t - 0.22) / 0.78);
    const double top_eased = EaseOutBack(top_t);
    const double panel_eased = EaseOutCubic(panel_t);
    g_current_width = static_cast<int>(kIslandCollapsedWidth +
        (kIslandHoverWidth - kIslandCollapsedWidth) * top_eased);
    g_current_height = static_cast<int>(kIslandCollapsedHeight +
        (kIslandExpandedHeight - kIslandCollapsedHeight) * panel_eased);
    g_current_alpha = static_cast<BYTE>(160 + (255 - 160) * EaseOutCubic(t));
    g_vertical_offset = static_cast<int>(-8 + (0 - (-8)) * EaseOutCubic(t));
    g_open_progress = panel_t;
    RepositionIslandWindow(true);
    InvalidateRect(g_island_hwnd, nullptr, TRUE);
    if (t >= 1.0) {
      BeginPhase(IslandPhase::kHolding);
    }
    return;
  }

  if (g_phase == IslandPhase::kHolding) {
    g_current_width = kIslandHoverWidth;
    g_current_height = kIslandExpandedHeight;
    g_current_alpha = 255;
    g_vertical_offset = 0;
    g_open_progress = 1.0;
    RepositionIslandWindow(true);
    InvalidateRect(g_island_hwnd, nullptr, TRUE);
    if (static_cast<int>(now - g_phase_start_ms) >= g_hold_duration_ms) {
      BeginPhase(IslandPhase::kCollapsing);
    }
    return;
  }

  if (g_phase == IslandPhase::kCollapsing) {
    const double t = Clamp01(static_cast<double>(now - g_phase_start_ms) / kCollapseMs);
    const double panel_t = Clamp01(1.0 - (t / 0.72));
    const double top_t = Clamp01(1.0 - ((t - 0.30) / 0.70));
    const double panel_eased = EaseInCubic(panel_t);
    const double top_eased = EaseInCubic(top_t);
    g_current_width = static_cast<int>(kIslandCollapsedWidth +
        (kIslandHoverWidth - kIslandCollapsedWidth) * top_eased);
    g_current_height = static_cast<int>(kIslandCollapsedHeight +
        (kIslandExpandedHeight - kIslandCollapsedHeight) * panel_eased);
    g_current_alpha = static_cast<BYTE>(255 + (180 - 255) * EaseInCubic(t));
    g_vertical_offset = static_cast<int>(0 + (-8 - 0) * EaseInCubic(t));
    g_open_progress = panel_t;
    RepositionIslandWindow(true);
    InvalidateRect(g_island_hwnd, nullptr, TRUE);
    if (t >= 1.0) {
      g_phase = IslandPhase::kHidden;
      if (g_clock_mode_enabled) {
        g_current_width = g_hovered ? kIslandHoverWidth : kIslandCollapsedWidth;
        g_current_height = kIslandCollapsedHeight;
        g_current_alpha = 235;
        g_vertical_offset = 0;
        g_open_progress = g_hovered ? 1.0 : 0.0;
        RepositionIslandWindow(true);
        InvalidateRect(g_island_hwnd, nullptr, TRUE);
      } else {
        KillTimer(g_island_hwnd, kIslandTimerId);
        ShowWindow(g_island_hwnd, SW_HIDE);
        g_island_visible = false;
      }
    }
  }
}

LRESULT CALLBACK IslandWndProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  switch (message) {
    case WM_ERASEBKGND:
      return 1;
    case WM_MOUSEMOVE: {
      if (!g_hovered) {
        g_hovered = true;
        TRACKMOUSEEVENT tme = {};
        tme.cbSize = sizeof(TRACKMOUSEEVENT);
        tme.dwFlags = TME_LEAVE;
        tme.hwndTrack = hwnd;
        TrackMouseEvent(&tme);
      }
      return 0;
    }
    case WM_MOUSELEAVE:
      g_hovered = false;
      return 0;
    case WM_TIMER:
      TickIslandAnimation();
      return 0;
    case WM_PAINT: {
      PAINTSTRUCT ps;
      HDC hdc = BeginPaint(hwnd, &ps);
      EnsurePaintResources();
      RECT rect;
      GetClientRect(hwnd, &rect);

      const int width = rect.right - rect.left;
      const int height = rect.bottom - rect.top;
      HDC mem_dc = CreateCompatibleDC(hdc);
      HBITMAP mem_bmp = CreateCompatibleBitmap(hdc, width, height);
      HGDIOBJ old_mem_bmp = SelectObject(mem_dc, mem_bmp);

      FillRect(mem_dc, &rect, g_transparent_key_brush);

      const int center_x = width / 2;
      const int top_width = std::clamp(g_current_width, kIslandCollapsedWidth, kIslandHoverWidth);
      const int top_height = kIslandCollapsedHeight;
      const int top_left = center_x - top_width / 2;
      const int top_top = 0;
      const int top_right = top_left + top_width;
      const int top_bottom = top_top + top_height;
      const int top_radius = top_height;

      HGDIOBJ old_pen = SelectObject(mem_dc, g_border_pen);
      HGDIOBJ old_brush = SelectObject(mem_dc, g_bg_brush);
      RoundRect(mem_dc, top_left, top_top, top_right, top_bottom, top_radius, top_radius);
      SelectObject(mem_dc, old_pen);
      SelectObject(mem_dc, old_brush);

      SetBkMode(mem_dc, TRANSPARENT);
      SetTextAlign(mem_dc, TA_CENTER);
      HGDIOBJ old_font = SelectObject(mem_dc, g_title_font_small);
      SetTextColor(mem_dc, RGB(245, 245, 250));
      SIZE clock_size = {};
      GetTextExtentPoint32W(mem_dc, g_clock_text.c_str(), static_cast<int>(g_clock_text.size()), &clock_size);
      const int clock_x = center_x - clock_size.cx / 2;
      const int clock_y = top_top + (top_height - clock_size.cy) / 2;
      const UINT old_align = SetTextAlign(mem_dc, TA_LEFT | TA_TOP);
      TextOutW(mem_dc, clock_x, clock_y, g_clock_text.c_str(), static_cast<int>(g_clock_text.size()));
      SetTextAlign(mem_dc, old_align);
      SelectObject(mem_dc, old_font);

      if (!(g_phase == IslandPhase::kHidden && g_clock_mode_enabled)) {
        const double panel_t = EaseOutCubic(Clamp01(g_open_progress));
        const int panel_gap = 8;
        const int panel_max_h = kIslandExpandedHeight - kIslandCollapsedHeight - panel_gap;
        const int panel_h = std::max(0, static_cast<int>(panel_max_h * panel_t));
        if (panel_h > 2) {
          const int panel_w = top_width;
          const int panel_left = center_x - panel_w / 2;
          const int panel_top = top_bottom + panel_gap;
          const int panel_right = panel_left + panel_w;
          const int panel_bottom = panel_top + panel_h;
          const int panel_radius = std::min(46, std::max(16, panel_h));

          old_pen = SelectObject(mem_dc, g_border_pen);
          old_brush = SelectObject(mem_dc, g_bg_brush);
          RoundRect(mem_dc, panel_left, panel_top, panel_right, panel_bottom, panel_radius, panel_radius);
          SelectObject(mem_dc, old_pen);
          SelectObject(mem_dc, old_brush);

          const double content_alpha_t = EaseOutCubic(Clamp01((g_open_progress - 0.20) / 0.80));
          if (g_open_progress > 0.35) {
            RECT title_rect = {
                panel_left + 20,
                panel_top + 12,
                panel_right - 20,
                panel_top + static_cast<int>(panel_h * 0.46),
            };
            RECT body_rect = {
                panel_left + 20,
                panel_top + static_cast<int>(panel_h * 0.50),
                panel_right - 20,
                panel_bottom - 12,
            };

            HGDIOBJ title_font = SelectObject(mem_dc, g_title_font_large);
            SetTextColor(mem_dc, LerpColor(RGB(120, 120, 128), RGB(252, 252, 255), content_alpha_t));
            DrawTextW(mem_dc, g_island_title.c_str(), -1, &title_rect,
                      DT_CENTER | DT_SINGLELINE | DT_END_ELLIPSIS | DT_VCENTER);
            SelectObject(mem_dc, title_font);

            if (!g_island_body.empty()) {
              HGDIOBJ body_font = SelectObject(mem_dc, g_body_font);
              SetTextColor(mem_dc, LerpColor(RGB(80, 80, 88), RGB(168, 168, 176), content_alpha_t));
              DrawTextW(mem_dc, g_island_body.c_str(), -1, &body_rect,
                        DT_CENTER | DT_SINGLELINE | DT_END_ELLIPSIS | DT_VCENTER);
              SelectObject(mem_dc, body_font);
            }
          }
        }
      }

      BitBlt(hdc, 0, 0, width, height, mem_dc, 0, 0, SRCCOPY);
      SelectObject(mem_dc, old_mem_bmp);
      DeleteObject(mem_bmp);
      DeleteDC(mem_dc);
      EndPaint(hwnd, &ps);
      return 0;
    }
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

void EnsureIslandWindow() {
  if (g_island_hwnd) return;

  WNDCLASSW wc = {};
  wc.lpfnWndProc = IslandWndProc;
  wc.hInstance = GetModuleHandle(nullptr);
  wc.lpszClassName = kIslandWindowClass;
  wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
  RegisterClassW(&wc);

  g_island_hwnd = CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_LAYERED,
      kIslandWindowClass,
      L"",
      WS_POPUP,
      0,
      0,
      kIslandExpandedWidth,
      kIslandExpandedHeight,
      nullptr,
      nullptr,
      GetModuleHandle(nullptr),
      nullptr);
  g_current_width = kIslandCollapsedWidth;
  g_current_height = kIslandCollapsedHeight;
  g_current_alpha = 235;
  g_vertical_offset = 0;
  g_open_progress = 0.0;
  UpdateClockText();
  RepositionIslandWindow(true);
  SetTimer(g_island_hwnd, kIslandTimerId, kIslandFrameMs, nullptr);
}

void ShowIslandOverlay(const std::wstring& title, const std::wstring& body, int duration_ms) {
  EnsureIslandWindow();
  g_island_title = title;
  g_island_body = body;
  g_hold_duration_ms = duration_ms > 0 ? duration_ms : 2600;
  g_current_width = kIslandCollapsedWidth;
  g_current_height = kIslandCollapsedHeight;
  g_current_alpha = 0;
  g_vertical_offset = -8;
  g_open_progress = 0.0;
  RepositionIslandWindow(true);
  BeginPhase(IslandPhase::kExpanding);
  SetTimer(g_island_hwnd, kIslandTimerId, kIslandFrameMs, nullptr);
  InvalidateRect(g_island_hwnd, nullptr, TRUE);
}
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  g_main_hwnd = GetHandle();
  EnsureIslandWindow();
  EnsureTrayIcon(g_main_hwnd);

  island_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "notes_bridge/island",
          &flutter::StandardMethodCodec::GetInstance());
  island_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() != "show") {
          result->NotImplemented();
          return;
        }

        std::string title = "Reminder";
        std::string body = "";
        int duration_ms = 2600;

        const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
        if (args) {
          auto title_it = args->find(flutter::EncodableValue("title"));
          if (title_it != args->end()) {
            if (const auto* v = std::get_if<std::string>(&title_it->second)) {
              title = *v;
            }
          }

          auto body_it = args->find(flutter::EncodableValue("body"));
          if (body_it != args->end()) {
            if (const auto* v = std::get_if<std::string>(&body_it->second)) {
              body = *v;
            }
          }

          auto duration_it = args->find(flutter::EncodableValue("durationMs"));
          if (duration_it != args->end()) {
            if (const auto* v = std::get_if<int32_t>(&duration_it->second)) {
              duration_ms = *v;
            } else if (const auto* v64 = std::get_if<int64_t>(&duration_it->second)) {
              duration_ms = static_cast<int>(*v64);
            }
          }
        }

        ShowIslandOverlay(
            std::wstring(title.begin(), title.end()),
            std::wstring(body.begin(), body.end()),
            duration_ms);
        result->Success();
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();

  if (g_island_hwnd) {
    KillTimer(g_island_hwnd, kIslandTimerId);
    DestroyWindow(g_island_hwnd);
    g_island_hwnd = nullptr;
    g_island_visible = false;
  }

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_CLOSE:
      if (!g_force_exit) {
        HideMainWindow();
        return 0;
      }
      break;
    case kTrayCallbackMessage: {
      const UINT tray_event = LOWORD(lparam);
      if (tray_event == WM_LBUTTONUP || tray_event == WM_LBUTTONDBLCLK ||
          tray_event == NIN_SELECT || tray_event == NIN_KEYSELECT) {
        ShowMainWindow();
        return 0;
      }
      if (tray_event == WM_RBUTTONUP || tray_event == WM_CONTEXTMENU) {
        POINT pt;
        GetCursorPos(&pt);
        HMENU menu = CreatePopupMenu();
        AppendMenuW(menu, MF_STRING, kTrayMenuOpenId, L"Open Notes Bridge");
        AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
        AppendMenuW(menu, MF_STRING, kTrayMenuExitId, L"Exit");
        SetForegroundWindow(hwnd);
        const UINT cmd = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_NONOTIFY, pt.x, pt.y, 0, hwnd, nullptr);
        DestroyMenu(menu);
        if (cmd == kTrayMenuOpenId) {
          ShowMainWindow();
        } else if (cmd == kTrayMenuExitId) {
          g_force_exit = true;
          RemoveTrayIcon();
          DestroyWindow(hwnd);
        }
        return 0;
      }
      break;
    }
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

