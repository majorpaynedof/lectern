// A second audio player for Lectern that uses Windows' own media engine
// (Windows.Media.Playback.MediaPlayer). Windows 11 can decode formats the
// main player can't, such as Audible's xHE-AAC, so Lectern switches a book
// to this player when the main one fails to decode it.
//
// Talks to Dart over the "lectern/windows_player" method channel.
#ifndef RUNNER_WINDOWS_PLAYER_H_
#define RUNNER_WINDOWS_PLAYER_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

#include <memory>

class WindowsPlayer {
 public:
  explicit WindowsPlayer(flutter::BinaryMessenger* messenger);
  ~WindowsPlayer();

  WindowsPlayer(const WindowsPlayer&) = delete;
  WindowsPlayer& operator=(const WindowsPlayer&) = delete;

  struct Impl;

 private:
  std::unique_ptr<Impl> impl_;
};

#endif  // RUNNER_WINDOWS_PLAYER_H_
