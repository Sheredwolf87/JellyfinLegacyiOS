# Jellyfin for iOS 6  (v1.1)

Objective-C, ARC, no storyboards / Auto Layout / NSURLSession, so it runs on iOS 6.0 and on
32-bit ARM only. Tuned for **iPhone 4S, iPhone 5/5c, iPad 2, iPad mini (1st gen)**.

## What it does
- **Browse** movies, shows, seasons, episodes, collections, playlists (paged, pull-to-refresh).
- **Continue Watching** row on the home screen, **Resume / Play from Start** on the detail screen.
  Progress is reported to the server (start / every 10 s / stop), so watched state and resume
  points sync with your other Jellyfin clients.
- **Direct Play** (original H.264/AAC file in MP4/M4V/MOV when the device can decode it),
  **Direct Stream** (remux), or **Transcode** (HLS H.264/AAC). The server decides from this
  device's profile (`JFDevice`), and if Direct Play fails the player retries as a transcode.
- **Music**: Artists / Albums / Songs, queue playback, Now Playing screen, background audio,
  headset and multitasking-bar controls, lock-screen info. mp3/m4a/aac/wav/aiff play directly;
  FLAC/OGG/etc. are converted to MP3 by the server.
- **Live TV**: On Now, Channels, Favorite Channels, Recordings (needs Live TV set up on the server).
- **Settings**: Direct Play on/off, max streaming quality, detected device and what it decodes.

## Device profiles (JFDevice.m)
| Device | Decodes | Auto bitrate |
|---|---|---|
| iPhone 4S | 1080p H.264 High 4.1 | 12 Mbps |
| iPhone 5 / 5c | 1080p H.264 High 4.1 | 20 Mbps |
| iPad 2 | 720p H.264 Main 3.1 | 12 Mbps |
| iPad mini 1 | 1080p H.264 High 4.1 | 20 Mbps |

Anything above those limits (1080p on an iPad 2, HEVC, AC3/DTS audio, 60 fps, 10-bit) is
transcoded or remuxed by the server. Unknown devices get the conservative iPad 2 profile.

## Build
1. Xcode 4.6.3 or 5.x is the safest choice (iOS 6 SDK / 6.0 deployment target).
2. New project -> iOS "Empty Application", Objective-C, ARC on, Devices: Universal.
3. Delete the generated AppDelegate/main files and drag in everything from this folder
   (including the five `Default*.png` launch images; without `Default-568h@2x.png` the
   iPhone 5 letterboxes the app).
4. Target settings: Deployment Target 6.0, Architectures `armv7 armv7s`.
5. Either point "Info.plist File" at `Jellyfin-Info.plist`, or copy its keys into yours
   (the important one is `UIBackgroundModes` = `audio`).
6. Link: MediaPlayer, AVFoundation, QuartzCore, CoreMedia (the last three are usually automatic).

## Server notes
- Enter the server as `192.168.1.10:8096`; `http://` is added for you.
- iOS 6 can't validate modern HTTPS certificates (no Let's Encrypt ISRG Root X1, old TLS ciphers).
  Use plain HTTP on the LAN or a reverse proxy with a compatible certificate.
- Streams and images authenticate with the `api_key` query parameter.
- Subtitles aren't supported; the app asks the server for no subtitle track.
- Seeking in a *transcoded* song is disabled (the MP3 stream isn't seekable); direct-played songs seek normally.
