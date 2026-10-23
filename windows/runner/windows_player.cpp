#include "windows_player.h"

// <unknwn.h> must come before C++/WinRT.
#include <unknwn.h>
#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.Core.h>
#include <winrt/Windows.Media.Playback.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.Streams.h>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <atomic>
#include <chrono>
#include <cstdint>
#include <string>
#include <variant>

#pragma comment(lib, "windowsapp")

using flutter::EncodableMap;
using flutter::EncodableValue;
using winrt::Windows::Foundation::AsyncStatus;
using winrt::Windows::Foundation::IAsyncOperation;
using winrt::Windows::Foundation::TimeSpan;
using winrt::Windows::Foundation::Uri;
using winrt::Windows::Media::Core::MediaSource;
using winrt::Windows::Media::Playback::MediaPlaybackSession;
using winrt::Windows::Media::Playback::MediaPlaybackState;
using winrt::Windows::Media::Playback::MediaPlayer;
using winrt::Windows::Media::Playback::MediaPlayerAudioCategory;
using winrt::Windows::Media::Playback::MediaPlayerFailedEventArgs;
using winrt::Windows::Storage::FileAccessMode;
using winrt::Windows::Storage::Streams::FileRandomAccessStream;
using winrt::Windows::Storage::Streams::IRandomAccessStream;
using winrt::Windows::Storage::Streams::IRandomAccessStreamWithContentType;
using winrt::Windows::Storage::Streams::RandomAccessStreamReference;

namespace {

// Player events arrive on background threads; they are posted to this hidden
// window so they reach Dart on the main thread.
constexpr UINT kEventMessage = WM_APP + 0x4D;
constexpr wchar_t kSinkClass[] = L"LecternWindowsPlayerSink";

struct Event {
  uint64_t generation;
  std::string type;     // opened, ended, failed, state
  double value = 0;     // duration (opened)
  bool playing = false; // state
  std::string message;  // failed
};

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

TimeSpan ToTimeSpan(double seconds) {
  return std::chrono::duration_cast<TimeSpan>(
      std::chrono::milliseconds(static_cast<int64_t>(seconds < 0 ? 0 : seconds * 1000)));
}

double ToSeconds(TimeSpan t) {
  return std::chrono::duration_cast<std::chrono::milliseconds>(t).count() / 1000.0;
}

}  // namespace

struct WindowsPlayer::Impl {
  MediaPlayer player{nullptr};
  HWND sink = nullptr;
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel;

  // Bumped on every open/stop so events from an older file are ignored.
  std::atomic<uint64_t> generation{0};
  // For a web address, whether we already retried by reading it as a stream.
  std::atomic<bool> retried_as_stream{false};
  std::wstring source;
  std::wstring mime;
  bool is_file = false;

  winrt::event_token opened_token{};
  winrt::event_token ended_token{};
  winrt::event_token failed_token{};
  winrt::event_token state_token{};

  void Post(Event* e) {
    if (!sink || !PostMessage(sink, kEventMessage, 0, reinterpret_cast<LPARAM>(e))) delete e;
  }

  void PostFailed(uint64_t gen, const std::wstring& message) {
    auto* e = new Event{gen, "failed"};
    e->message = winrt::to_string(message);
    Post(e);
  }

  static LRESULT CALLBACK SinkProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
    if (message == kEventMessage) {
      std::unique_ptr<Event> e(reinterpret_cast<Event*>(lparam));
      auto* self = reinterpret_cast<Impl*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));
      if (self && self->channel && e && e->generation == self->generation.load()) {
        EncodableMap args{{EncodableValue("type"), EncodableValue(e->type)}};
        if (e->type == "opened") args[EncodableValue("duration")] = EncodableValue(e->value);
        if (e->type == "state") args[EncodableValue("playing")] = EncodableValue(e->playing);
        if (e->type == "failed") args[EncodableValue("message")] = EncodableValue(e->message);
        self->channel->InvokeMethod("event", std::make_unique<EncodableValue>(args));
      }
      return 0;
    }
    return DefWindowProc(hwnd, message, wparam, lparam);
  }

  bool EnsurePlayer() {
    if (player) return true;
    try {
      player = MediaPlayer();
      player.AutoPlay(false);
      player.AudioCategory(MediaPlayerAudioCategory::Media);
      // Lectern runs the Windows media controls itself (media_controls.cpp).
      player.CommandManager().IsEnabled(false);

      opened_token = player.MediaOpened([this](MediaPlayer const& p, auto&&) {
        auto* e = new Event{generation.load(), "opened"};
        try {
          e->value = ToSeconds(p.PlaybackSession().NaturalDuration());
        } catch (...) {
        }
        Post(e);
      });
      ended_token = player.MediaEnded([this](MediaPlayer const&, auto&&) {
        Post(new Event{generation.load(), "ended"});
      });
      failed_token = player.MediaFailed([this](MediaPlayer const&, MediaPlayerFailedEventArgs const& args) {
        const uint64_t gen = generation.load();
        // Windows picks a decoder from the server's file type; if it couldn't,
        // read the address as a stream and tell it the type ourselves.
        if (!is_file && !retried_as_stream.exchange(true)) {
          OpenWebAsStream(gen);
          return;
        }
        std::wstring message = std::wstring(args.ErrorMessage());
        if (message.empty()) {
          wchar_t code[32];
          swprintf_s(code, L"error 0x%08X", static_cast<unsigned int>(args.ExtendedErrorCode()));
          message = code;
        }
        PostFailed(gen, message);
      });
      state_token = player.PlaybackSession().PlaybackStateChanged([this](MediaPlaybackSession const& s, auto&&) {
        auto* e = new Event{generation.load(), "state"};
        const auto state = s.PlaybackState();
        e->playing = state == MediaPlaybackState::Playing || state == MediaPlaybackState::Buffering;
        Post(e);
      });
      return true;
    } catch (...) {
      player = nullptr;
      return false;
    }
  }

  void SetSource(uint64_t gen, MediaSource const& src) {
    if (gen != generation.load()) return;
    try {
      player.Source(src);
    } catch (winrt::hresult_error const& e) {
      PostFailed(gen, std::wstring(e.message()));
    }
  }

  void OpenFile(uint64_t gen) {
    // A file is opened as a stream with its type given, so Windows doesn't
    // depend on the file extension (it doesn't always know .m4b).
    auto op = FileRandomAccessStream::OpenAsync(source, FileAccessMode::Read);
    op.Completed([this, gen](IAsyncOperation<IRandomAccessStream> const& done, AsyncStatus status) {
      if (status != AsyncStatus::Completed) {
        PostFailed(gen, L"Could not open the downloaded file.");
        return;
      }
      try {
        SetSource(gen, MediaSource::CreateFromStream(done.GetResults(), mime));
      } catch (winrt::hresult_error const& e) {
        PostFailed(gen, std::wstring(e.message()));
      }
    });
  }

  void OpenWebAsStream(uint64_t gen) {
    try {
      auto op = RandomAccessStreamReference::CreateFromUri(Uri(source)).OpenReadAsync();
      op.Completed([this, gen](IAsyncOperation<IRandomAccessStreamWithContentType> const& done,
                               AsyncStatus status) {
        if (status != AsyncStatus::Completed) {
          PostFailed(gen, L"Windows could not open this audio from the server.");
          return;
        }
        try {
          SetSource(gen, MediaSource::CreateFromStream(done.GetResults(), mime));
        } catch (winrt::hresult_error const& e) {
          PostFailed(gen, std::wstring(e.message()));
        }
      });
    } catch (winrt::hresult_error const& e) {
      PostFailed(gen, std::wstring(e.message()));
    }
  }

  void Open(const EncodableMap& args) {
    if (!EnsurePlayer()) {
      PostFailed(generation.load(), L"Windows media playback is not available.");
      return;
    }
    const uint64_t gen = ++generation;
    retried_as_stream = false;
    source = Widen(Str(args, "source"));
    mime = Widen(Str(args, "mime"));
    if (mime.empty()) mime = L"audio/mp4";
    is_file = Flag(args, "isFile");
    try {
      player.Pause();
      player.Source(nullptr);
      if (is_file) {
        OpenFile(gen);
      } else {
        SetSource(gen, MediaSource::CreateFromUri(Uri(source)));
      }
    } catch (winrt::hresult_error const& e) {
      PostFailed(gen, std::wstring(e.message()));
    }
  }

  std::unique_ptr<EncodableValue> Handle(const std::string& method, const EncodableMap& args) {
    if (method == "open") {
      Open(args);
      return nullptr;
    }
    if (!player) {
      if (method == "state") {
        return std::make_unique<EncodableValue>(EncodableMap{
            {EncodableValue("position"), EncodableValue(0.0)},
            {EncodableValue("duration"), EncodableValue(0.0)},
            {EncodableValue("playing"), EncodableValue(false)}});
      }
      return nullptr;
    }
    auto session = player.PlaybackSession();
    if (method == "play") {
      player.Play();
    } else if (method == "pause") {
      player.Pause();
    } else if (method == "seek") {
      session.Position(ToTimeSpan(Num(args, "position")));
    } else if (method == "rate") {
      const double rate = Num(args, "rate");
      session.PlaybackRate(rate > 0 ? rate : 1.0);
    } else if (method == "stop") {
      ++generation;
      player.Pause();
      player.Source(nullptr);
    } else if (method == "state") {
      const auto state = session.PlaybackState();
      return std::make_unique<EncodableValue>(EncodableMap{
          {EncodableValue("position"), EncodableValue(ToSeconds(session.Position()))},
          {EncodableValue("duration"), EncodableValue(ToSeconds(session.NaturalDuration()))},
          {EncodableValue("playing"), EncodableValue(state == MediaPlaybackState::Playing ||
                                                     state == MediaPlaybackState::Buffering)}});
    }
    return nullptr;
  }
};

WindowsPlayer::WindowsPlayer(flutter::BinaryMessenger* messenger) : impl_(std::make_unique<Impl>()) {
  Impl* impl = impl_.get();
  impl->channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "lectern/windows_player", &flutter::StandardMethodCodec::GetInstance());

  HINSTANCE instance = GetModuleHandle(nullptr);
  WNDCLASSW wc{};
  wc.lpfnWndProc = Impl::SinkProc;
  wc.hInstance = instance;
  wc.lpszClassName = kSinkClass;
  RegisterClassW(&wc);  // fails harmlessly if already registered
  impl->sink = CreateWindowExW(0, kSinkClass, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr, instance, nullptr);
  if (impl->sink) SetWindowLongPtr(impl->sink, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(impl));

  impl->channel->SetMethodCallHandler(
      [impl](const flutter::MethodCall<EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        try {
          const auto* map = std::get_if<EncodableMap>(call.arguments());
          auto reply = impl->Handle(call.method_name(), map ? *map : EncodableMap{});
          if (reply) {
            result->Success(*reply);
          } else {
            result->Success();
          }
        } catch (winrt::hresult_error const& e) {
          result->Error("windows_player", winrt::to_string(e.message()));
        } catch (...) {
          result->Error("windows_player", "Unexpected error");
        }
      });
}

WindowsPlayer::~WindowsPlayer() {
  if (!impl_) return;
  ++impl_->generation;
  if (impl_->sink) {
    SetWindowLongPtr(impl_->sink, GWLP_USERDATA, 0);
    DestroyWindow(impl_->sink);
    impl_->sink = nullptr;
  }
  if (impl_->player) {
    try {
      impl_->player.MediaOpened(impl_->opened_token);
      impl_->player.MediaEnded(impl_->ended_token);
      impl_->player.MediaFailed(impl_->failed_token);
      impl_->player.PlaybackSession().PlaybackStateChanged(impl_->state_token);
      impl_->player.Close();
    } catch (...) {
    }
    impl_->player = nullptr;
  }
  if (impl_->channel) impl_->channel->SetMethodCallHandler(nullptr);
  impl_->channel = nullptr;
}
