#include "media_controls.h"

// <unknwn.h> must come before C++/WinRT so it can work with classic COM
// interfaces like ISystemMediaTransportControlsInterop.
#include <unknwn.h>
#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.h>
#include <winrt/Windows.Storage.Streams.h>
#include <systemmediatransportcontrolsinterop.h>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <chrono>
#include <string>
#include <variant>

#pragma comment(lib, "windowsapp")

using flutter::EncodableMap;
using flutter::EncodableValue;
using winrt::Windows::Foundation::TimeSpan;
using winrt::Windows::Foundation::Uri;
using winrt::Windows::Media::MediaPlaybackStatus;
using winrt::Windows::Media::MediaPlaybackType;
using winrt::Windows::Media::SystemMediaTransportControls;
using winrt::Windows::Media::SystemMediaTransportControlsButton;
using winrt::Windows::Media::SystemMediaTransportControlsButtonPressedEventArgs;
using winrt::Windows::Media::SystemMediaTransportControlsTimelineProperties;
using winrt::Windows::Storage::Streams::RandomAccessStreamReference;

namespace {

// Button presses arrive on a background thread; they are posted to this
// hidden window so they're handed to Dart on the main thread.
constexpr UINT kButtonMessage = WM_APP + 0x4C;
constexpr wchar_t kSinkClass[] = L"LecternMediaControlsSink";

const char* ButtonName(SystemMediaTransportControlsButton button) {
  switch (button) {
    case SystemMediaTransportControlsButton::Play:
      return "play";
    case SystemMediaTransportControlsButton::Pause:
      return "pause";
    case SystemMediaTransportControlsButton::Stop:
      return "stop";
    case SystemMediaTransportControlsButton::Next:
      return "next";
    case SystemMediaTransportControlsButton::Previous:
      return "previous";
    case SystemMediaTransportControlsButton::FastForward:
      return "fastForward";
    case SystemMediaTransportControlsButton::Rewind:
      return "rewind";
    default:
      return "";
  }
}

std::wstring Widen(const std::string& s) {
  if (s.empty()) return std::wstring();
  const int size = MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), nullptr, 0);
  std::wstring out(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), out.data(), size);
  return out;
}

const EncodableValue* Find(const EncodableMap& map, const char* key) {
  auto it = map.find(EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}

std::string Str(const EncodableMap& map, const char* key) {
  if (const auto* v = Find(map, key)) {
    if (const auto* s = std::get_if<std::string>(v)) return *s;
  }
  return std::string();
}

double Num(const EncodableMap& map, const char* key) {
  if (const auto* v = Find(map, key)) {
    if (const auto* d = std::get_if<double>(v)) return *d;
    if (const auto* i = std::get_if<int32_t>(v)) return static_cast<double>(*i);
    if (const auto* l = std::get_if<int64_t>(v)) return static_cast<double>(*l);
  }
  return 0;
}

bool Flag(const EncodableMap& map, const char* key) {
  if (const auto* v = Find(map, key)) {
    if (const auto* b = std::get_if<bool>(v)) return *b;
  }
  return false;
}

TimeSpan Seconds(double seconds) {
  return std::chrono::duration_cast<TimeSpan>(
      std::chrono::milliseconds(static_cast<int64_t>(seconds < 0 ? 0 : seconds * 1000)));
}

}  // namespace

struct MediaControls::Impl {
  SystemMediaTransportControls smtc{nullptr};
  winrt::event_token button_token{};
  HWND sink = nullptr;
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel;

  static LRESULT CALLBACK SinkProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
    if (message == kButtonMessage) {
      auto* self = reinterpret_cast<Impl*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));
      if (self && self->channel) {
        const char* name = ButtonName(static_cast<SystemMediaTransportControlsButton>(wparam));
        if (*name) self->channel->InvokeMethod("button", std::make_unique<EncodableValue>(std::string(name)));
      }
      return 0;
    }
    return DefWindowProc(hwnd, message, wparam, lparam);
  }

  void Handle(const std::string& method, const EncodableMap& args) {
    if (!smtc) return;
    if (method == "metadata") {
      smtc.IsEnabled(true);
      auto updater = smtc.DisplayUpdater();
      updater.ClearAll();
      updater.Type(MediaPlaybackType::Music);
      auto music = updater.MusicProperties();
      music.Title(winrt::hstring(Widen(Str(args, "title"))));
      music.Artist(winrt::hstring(Widen(Str(args, "artist"))));
      music.AlbumTitle(winrt::hstring(Widen(Str(args, "title"))));
      music.AlbumArtist(winrt::hstring(Widen(Str(args, "artist"))));
      const std::string thumbnail = Str(args, "thumbnail");
      if (!thumbnail.empty()) {
        try {
          updater.Thumbnail(RandomAccessStreamReference::CreateFromUri(Uri(winrt::hstring(Widen(thumbnail)))));
        } catch (...) {
          // A bad cover address shouldn't stop the rest from showing.
        }
      }
      updater.Update();
    } else if (method == "status") {
      smtc.PlaybackStatus(Flag(args, "playing") ? MediaPlaybackStatus::Playing : MediaPlaybackStatus::Paused);
    } else if (method == "timeline") {
      SystemMediaTransportControlsTimelineProperties timeline;
      const TimeSpan end = Seconds(Num(args, "duration"));
      timeline.StartTime(Seconds(0));
      timeline.MinSeekTime(Seconds(0));
      timeline.EndTime(end);
      timeline.MaxSeekTime(end);
      timeline.Position(Seconds(Num(args, "position")));
      smtc.UpdateTimelineProperties(timeline);
    } else if (method == "disable") {
      smtc.PlaybackStatus(MediaPlaybackStatus::Stopped);
      smtc.DisplayUpdater().ClearAll();
      smtc.DisplayUpdater().Update();
      smtc.IsEnabled(false);
    }
  }
};

MediaControls::MediaControls(HWND window, flutter::BinaryMessenger* messenger)
    : impl_(std::make_unique<Impl>()) {
  Impl* impl = impl_.get();
  impl->channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "lectern/media_controls", &flutter::StandardMethodCodec::GetInstance());

  HINSTANCE instance = GetModuleHandle(nullptr);
  WNDCLASSW wc{};
  wc.lpfnWndProc = Impl::SinkProc;
  wc.hInstance = instance;
  wc.lpszClassName = kSinkClass;
  RegisterClassW(&wc);  // fails harmlessly if already registered
  impl->sink = CreateWindowExW(0, kSinkClass, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr, instance, nullptr);
  if (impl->sink) SetWindowLongPtr(impl->sink, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(impl));

  try {
    auto interop = winrt::get_activation_factory<SystemMediaTransportControls, ISystemMediaTransportControlsInterop>();
    winrt::check_hresult(interop->GetForWindow(window, winrt::guid_of<SystemMediaTransportControls>(),
                                               winrt::put_abi(impl->smtc)));
    impl->smtc.IsPlayEnabled(true);
    impl->smtc.IsPauseEnabled(true);
    impl->smtc.IsStopEnabled(true);
    impl->smtc.IsNextEnabled(true);      // next chapter
    impl->smtc.IsPreviousEnabled(true);  // previous chapter
    impl->smtc.IsFastForwardEnabled(true);
    impl->smtc.IsRewindEnabled(true);
    impl->smtc.IsEnabled(false);  // hidden until something plays

    HWND sink = impl->sink;
    impl->button_token = impl->smtc.ButtonPressed(
        [sink](SystemMediaTransportControls const&, SystemMediaTransportControlsButtonPressedEventArgs const& e) {
          if (sink) PostMessage(sink, kButtonMessage, static_cast<WPARAM>(e.Button()), 0);
        });
  } catch (...) {
    impl->smtc = nullptr;  // media controls unavailable; the app still works
  }

  impl->channel->SetMethodCallHandler(
      [impl](const flutter::MethodCall<EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        try {
          const auto* map = std::get_if<EncodableMap>(call.arguments());
          impl->Handle(call.method_name(), map ? *map : EncodableMap{});
        } catch (...) {
          // Never let a media-controls hiccup crash the app.
        }
        result->Success();
      });
}

MediaControls::~MediaControls() {
  if (!impl_) return;
  if (impl_->smtc) {
    try {
      impl_->smtc.ButtonPressed(impl_->button_token);
      impl_->smtc.IsEnabled(false);
    } catch (...) {
    }
  }
  if (impl_->sink) {
    DestroyWindow(impl_->sink);
    impl_->sink = nullptr;
  }
  if (impl_->channel) impl_->channel->SetMethodCallHandler(nullptr);
  impl_->channel = nullptr;
}
