# Changelog

## 1.0.0 (2026-08-16)

First public release.

### Features
- Session authentication and persistence via DSM WebAPI
- Photo timeline: browse personal and shared photos chronologically,
  folders and favorites
- Albums: normal and shared albums, create albums, add / remove photos,
  delete albums
- Fullscreen photo viewer with pinch-to-zoom, pan and swipe navigation
- Video streaming with mobile-optimized transcoded H.264 playback
- Metadata inspector: resolution, file size, capture date, orientation
- Search: full-text search across photos and albums
- Sharing: share links with passphrase, expiration and permission control
- Backup & Upload: back up device photos and videos to the NAS Personal
  Space, live upload progress, local file management
- Session handling: re-login prompt on expired sessions, human-readable
  Synology error messages
- Settings: clear cache, full app reset to fresh-install state
- About page: author, website, contact, disclaimer and privacy statement
- Security: passwords are never stored, session tokens are not logged,
  cached file names are sanitized against path traversal, dialog content
  is HTML-escaped
