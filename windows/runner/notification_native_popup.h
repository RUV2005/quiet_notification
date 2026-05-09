#ifndef RUNNER_NOTIFICATION_NATIVE_POPUP_H_
#define RUNNER_NOTIFICATION_NATIVE_POPUP_H_

#include <string>
#include <windows.h>

void NotificationNativePopupClose();

/// 显示与参考图一致的 Win32 置顶浮窗（UTF-8）。
/// [header_title] 如「验证码 · 支付宝」；[code] 为大号蓝色数字；[subtitle] 如「5 分钟内有效…」；
/// [from_label] 如「来自：小米 14」；[copy_payload_utf8] 为「复制」按钮写入剪贴板的文本（一般为验证码）。
void NotificationNativePopupShow(HWND owner_root_hwnd,
                                   const std::string& header_title_utf8,
                                   const std::string& time_utf8,
                                   const std::string& code_utf8,
                                   const std::string& code_label_utf8,
                                   const std::string& subtitle_utf8,
                                   const std::string& from_label_utf8,
                                   const std::string& copy_payload_utf8);

#endif  // RUNNER_NOTIFICATION_NATIVE_POPUP_H_
