#include "BackupEngine.h"

#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>
#include <QUrl>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QJsonDocument>
#include <QJsonObject>
#include <QThreadPool>
#include <QRunnable>
#include <QMetaObject>
#include <QTimer>
#include <QDebug>
#include <QBuffer>
#include <QTcpServer>
#include <QTcpSocket>
#include <QHostAddress>
#include <QSet>
#include <QtEndian>
#include <QRegularExpression>
#include <cstring>

namespace {

// Masks session credentials in a URL so they never appear in logs.
QString maskedUrlForLog(const QString &url)
{
    static const QRegularExpression re(
        QStringLiteral("((?:[?&])(?:_sid|SynoToken|passphrase)=)[^&]*"));
    QString masked = url;
    masked.replace(re, QStringLiteral("\\1***"));
    return masked;
}

// Local HTTP proxy that streams a remote video to Media Hub. The Android
// media stack on Ubuntu Touch cannot fetch https URLs itself, but it can
// play plain http, so we expose the remote stream on 127.0.0.1 and forward
// it (including Range requests for seeking).
class MediaProxyServer : public QObject
{
public:
    explicit MediaProxyServer(QObject *parent = nullptr)
        : QObject(parent)
        , m_server(new QTcpServer(this))
        , m_nam(new QNetworkAccessManager(this))
        , m_nextToken(1)
    {
        connect(m_server, &QTcpServer::newConnection, this, &MediaProxyServer::onNewConnection);
        m_server->listen(QHostAddress::LocalHost, 0);
        qDebug() << "MediaProxyServer listening on 127.0.0.1:" << m_server->serverPort();
    }

    QString registerUrl(const QString &url)
    {
        if (!m_server->isListening()) {
            m_server->listen(QHostAddress::LocalHost, 0);
        }
        if (!m_server->isListening() || url.isEmpty()) return QString();
        const QString token = QString::number(m_nextToken++);
        if (m_urls.size() > 50) {
            // Trim oldest entries to avoid unbounded growth
            m_urls.clear();
        }
        m_urls.insert(token, url);
        qDebug() << "MediaProxyServer: registered token" << token << "for URL:" << maskedUrlForLog(url);
        // ".mp4" suffix helps the media stack sniff the stream type
        return QStringLiteral("http://127.0.0.1:%1/%2/video.mp4").arg(m_server->serverPort()).arg(token);
    }

    void stopAllStreams()
    {
        qDebug() << "MediaProxyServer: aborting all active streams (" << m_conns.size() << "connections )";
        const QList<ProxyConn *> conns = m_conns.values();
        for (ProxyConn *c : conns) {
            if (!m_conns.contains(c)) continue;
            if (c->reply) {
                c->reply->disconnect(this);
                c->reply->abort();
                c->reply->deleteLater();
                c->reply = nullptr;
            }
            if (c->client) {
                c->client->disconnect(this);
                c->client->abort();
                c->client->deleteLater();
                c->client = nullptr;
            }
            m_conns.remove(c);
            delete c;
        }
        m_urls.clear();
    }

    void shutdown()
    {
        qDebug() << "MediaProxyServer: shutting down proxy";
        stopAllStreams();
        m_server->close();
    }

private:
    struct ProxyConn
    {
        QTcpSocket *client = nullptr;
        QNetworkReply *reply = nullptr;
        QByteArray buf;
        bool requestParsed = false;
        bool headersSent = false;
        QString token;
        qint64 bytesSent = 0;
    };

private:
    void onNewConnection()
    {
        while (m_server->hasPendingConnections()) {
            QTcpSocket *sock = m_server->nextPendingConnection();
            ProxyConn *c = new ProxyConn;
            c->client = sock;
            m_conns.insert(c);
            qDebug() << "MediaProxyServer: new connection from" << sock->peerAddress().toString();
            connect(sock, &QTcpSocket::readyRead, this, [this, c]() {
                if (!m_conns.contains(c)) return;
                onClientReadyRead(c);
            });
            connect(sock, &QTcpSocket::disconnected, this, [this, c]() {
                if (!m_conns.contains(c)) return;
                qDebug() << "MediaProxyServer: client disconnected, token=" << c->token
                         << "total bytesSent=" << c->bytesSent;
                // Sever every handler that references this connection, then
                // abort the upstream reply: no lambda may touch `c` after it
                // is deleted below
                if (c->reply) {
                    c->reply->disconnect(this);
                    c->reply->abort();
                }
                // Do NOT remove token from m_urls here: seeking and multiple
                // range requests open new TCP connections to the same token!
                m_conns.remove(c);
                if (c->client) {
                    c->client->disconnect(this);
                    c->client->deleteLater();
                }
                delete c;
            });
            connect(sock, QOverload<QAbstractSocket::SocketError>::of(&QAbstractSocket::error),
                    this, [this, c](QAbstractSocket::SocketError e) {
                if (!m_conns.contains(c)) return;
                qDebug() << "MediaProxyServer: client socket error:" << e;
                if (c->reply) c->reply->abort();
            });
        }
    }

    void onClientReadyRead(ProxyConn *c)
    {
        if (!c->requestParsed) {
            c->buf += c->client->readAll();
            const int headerEnd = c->buf.indexOf("\r\n\r\n");
            if (headerEnd < 0) {
                if (c->buf.size() > 16 * 1024) c->client->disconnectFromHost();
                return;
            }
            const QByteArray header = c->buf.left(headerEnd);
            c->buf.remove(0, headerEnd + 4);
            c->requestParsed = true;
            qDebug() << "MediaProxyServer: request:" << QString::fromUtf8(header.left(200));

            const QList<QByteArray> lines = header.split('\r');
            if (lines.isEmpty() || !lines.first().startsWith("GET ")) {
                c->client->disconnectFromHost();
                return;
            }
            const QList<QByteArray> parts = lines.first().split(' ');
            if (parts.length() < 2) {
                c->client->disconnectFromHost();
                return;
            }
            const QString path = QString::fromLatin1(parts.at(1));
            const QStringList pathParts = path.split(QLatin1Char('/'), QString::SkipEmptyParts);
            const QString token = pathParts.isEmpty() ? QString() : pathParts.first();
            c->token = token;
            if (!m_urls.contains(token)) {
                qDebug() << "MediaProxyServer: unknown token" << token;
                respondSimple(c, "404 Not Found");
                return;
            }

            QString rangeHeader;
            for (const QByteArray &line : lines) {
                const QByteArray t = line.trimmed();
                if (t.toLower().startsWith("range:")) {
                    rangeHeader = QString::fromLatin1(t.mid(6)).trimmed();
                }
            }
            qDebug() << "MediaProxyServer: streaming" << maskedUrlForLog(m_urls.value(token))
                     << "range=" << rangeHeader;

            QNetworkRequest req{QUrl(m_urls.value(token))};
            req.setRawHeader("Accept", "*/*");
            if (!rangeHeader.isEmpty()) {
                req.setRawHeader("Range", rangeHeader.toUtf8());
            }
            c->reply = m_nam->get(req);
            connect(c->reply, QOverload<const QList<QSslError>&>::of(&QNetworkReply::sslErrors),
                    c->reply, QOverload<>::of(&QNetworkReply::ignoreSslErrors));
            connect(c->reply, &QNetworkReply::metaDataChanged, this, [this, c]() { onMetaDataChanged(c); });
            connect(c->reply, &QNetworkReply::readyRead, this, [this, c]() { onReplyReadyRead(c); });
            connect(c->reply, &QNetworkReply::finished, this, [this, c]() { onReplyFinished(c); });
            QNetworkReply *replyForLog = c->reply;
            connect(replyForLog, QOverload<QNetworkReply::NetworkError>::of(&QNetworkReply::error),
                    this, [replyForLog](QNetworkReply::NetworkError e) {
                qDebug() << "MediaProxyServer: reply error:" << e << replyForLog->errorString();
            });
        }
    }

    void respondSimple(ProxyConn *c, const QByteArray &status)
    {
        QByteArray resp = "HTTP/1.1 " + status + "\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
        c->client->write(resp);
        c->client->disconnectFromHost();
    }

    void onMetaDataChanged(ProxyConn *c)
    {
        if (!m_conns.contains(c) || !c->reply || c->headersSent) return;
        const int status = c->reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        qDebug() << "MediaProxyServer: upstream status" << status << c->reply->error();
        const QByteArray reason = (status == 206) ? "Partial Content" : "OK";
        QByteArray resp = "HTTP/1.1 " + QByteArray::number(status) + " " + reason + "\r\n";
        resp += "Accept-Ranges: bytes\r\n";
        resp += "Connection: close\r\n";
        const QByteArray contentType = c->reply->header(QNetworkRequest::ContentTypeHeader).toByteArray();
        if (!contentType.isEmpty()) resp += "Content-Type: " + contentType + "\r\n";
        const QByteArray rawContentRange = c->reply->rawHeader("Content-Range");
        if (!rawContentRange.isEmpty()) resp += "Content-Range: " + rawContentRange + "\r\n";
        const QVariant contentLength = c->reply->header(QNetworkRequest::ContentLengthHeader);
        if (contentLength.isValid()) resp += "Content-Length: " + contentLength.toByteArray() + "\r\n";
        resp += "\r\n";
        c->client->write(resp);
        c->headersSent = true;
    }

    void onReplyReadyRead(ProxyConn *c)
    {
        if (!m_conns.contains(c)) return;
        QNetworkReply *reply = c->reply;
        if (!reply || !c->headersSent || !c->client) return;
        const QByteArray data = reply->readAll();
        if (!data.isEmpty()) {
            if (c->bytesSent == 0) {
                qDebug() << "MediaProxyServer: first data chunk" << data.size() << "bytes";
            }
            c->bytesSent += data.size();
            c->client->write(data);
        }
    }

    void onReplyFinished(ProxyConn *c)
    {
        if (!m_conns.contains(c)) return;
        // Null the pointer first: QNAM may have already scheduled the reply
        // for deletion, and socket handlers must not touch it anymore
        QNetworkReply *reply = c->reply;
        if (!reply) return;
        c->reply = nullptr;
        qDebug() << "MediaProxyServer: upstream finished, sent" << c->bytesSent
                 << "bytes, headersSent=" << c->headersSent;
        if (!c->client) return;
        if (!c->headersSent) {
            respondSimple(c, "502 Bad Gateway");
            return;
        }
        c->client->flush();
        c->client->disconnectFromHost();
    }

private:
    QTcpServer *m_server;
    QNetworkAccessManager *m_nam;
    QSet<ProxyConn *> m_conns;
    QHash<QString, QString> m_urls;
    int m_nextToken;
};

} // namespace

namespace {

bool isMediaFile(const QString &fileName)
{
    static const QStringList exts = {
        QStringLiteral("jpg"), QStringLiteral("jpeg"), QStringLiteral("png"),
        QStringLiteral("heic"), QStringLiteral("heif"), QStringLiteral("gif"),
        QStringLiteral("webp"), QStringLiteral("bmp"), QStringLiteral("tiff"),
        QStringLiteral("mp4"), QStringLiteral("mov"), QStringLiteral("m4v"),
        QStringLiteral("mkv"), QStringLiteral("webm"), QStringLiteral("avi"),
        QStringLiteral("3gp"), QStringLiteral("mpeg"), QStringLiteral("mpg")
    };
    return exts.contains(QFileInfo(fileName).suffix().toLower());
}

QString mimeForFile(const QString &fileName)
{
    QString ext = QFileInfo(fileName).suffix().toLower();
    if (ext == QLatin1String("jpg") || ext == QLatin1String("jpeg")) return QStringLiteral("image/jpeg");
    if (ext == QLatin1String("png")) return QStringLiteral("image/png");
    if (ext == QLatin1String("heic")) return QStringLiteral("image/heic");
    if (ext == QLatin1String("heif")) return QStringLiteral("image/heif");
    if (ext == QLatin1String("gif")) return QStringLiteral("image/gif");
    if (ext == QLatin1String("webp")) return QStringLiteral("image/webp");
    if (ext == QLatin1String("bmp")) return QStringLiteral("image/bmp");
    if (ext == QLatin1String("tiff")) return QStringLiteral("image/tiff");
    if (ext == QLatin1String("mp4")) return QStringLiteral("video/mp4");
    if (ext == QLatin1String("mov")) return QStringLiteral("video/quicktime");
    if (ext == QLatin1String("m4v")) return QStringLiteral("video/x-m4v");
    if (ext == QLatin1String("mkv")) return QStringLiteral("video/x-matroska");
    if (ext == QLatin1String("webm")) return QStringLiteral("video/webm");
    if (ext == QLatin1String("avi")) return QStringLiteral("video/x-msvideo");
    if (ext == QLatin1String("3gp")) return QStringLiteral("video/3gpp");
    if (ext == QLatin1String("mpeg") || ext == QLatin1String("mpg")) return QStringLiteral("video/mpeg");
    return QStringLiteral("application/octet-stream");
}

class ScanTask : public QRunnable
{
public:
    ScanTask(const QStringList &roots, BackupEngine *engine)
        : m_roots(roots), m_engine(engine)
    {
        setAutoDelete(true);
    }

    void run() override
    {
        QVariantList folders;
        int totalFiles = 0;
        bool picsExists = false;
        bool picsReadable = false;
        bool vidsExists = false;
        bool vidsReadable = false;

        for (int rootIdx = 0; rootIdx < m_roots.size(); rootIdx++) {
            QString root = m_roots.at(rootIdx);
            QString rootLabel = (rootIdx == 0) ? QStringLiteral("Pictures") : QStringLiteral("Videos");

            QDir dir(root);
            const bool exists = dir.exists();
            const bool readable = QFileInfo(root).isReadable();
            if (rootIdx == 0) {
                picsExists = exists;
                picsReadable = readable;
            } else {
                vidsExists = exists;
                vidsReadable = readable;
            }
            qDebug() << "BackupEngine scanMedia root:" << root
                     << "exists:" << exists
                     << "readable:" << readable;
            if (!exists) continue;

            QHash<QString, QVariantList> folderFiles;
            QStringList order;
            int rootFiles = 0;

            QDirIterator it(root, QDir::Files | QDir::Readable, QDirIterator::Subdirectories);
            while (it.hasNext()) {
                it.next();
                QString path = it.filePath();
                if (!isMediaFile(path)) continue;
                rootFiles++;

                QFileInfo info(path);
                QString rel = dir.relativeFilePath(path);
                QString topFolder = rel.contains(QLatin1Char('/'))
                    ? rel.section(QLatin1Char('/'), 0, 0)
                    : rootLabel;

                // Prefix non-Pictures roots so folder names stay unique
                QString folderName = (rootIdx == 0) ? topFolder
                    : (topFolder == rootLabel ? rootLabel : rootLabel + QLatin1Char('/') + topFolder);

                if (!folderFiles.contains(folderName)) {
                    folderFiles.insert(folderName, QVariantList());
                    order.append(folderName);
                }

                QVariantMap file;
                file.insert(QStringLiteral("path"), path);
                file.insert(QStringLiteral("name"), info.fileName());
                file.insert(QStringLiteral("size"), (double)info.size());

                QDateTime dt = info.birthTime();
                if (!dt.isValid() || dt.isNull()) {
                    dt = info.lastModified();
                }
                file.insert(QStringLiteral("mtime"), (double)dt.toMSecsSinceEpoch() / 1000.0);

                file.insert(QStringLiteral("folder"), folderName);
                folderFiles[folderName].append(file);
            }

            for (const QString &name : order) {
                QVariantMap folder;
                folder.insert(QStringLiteral("name"), name);
                folder.insert(QStringLiteral("root"), rootLabel);
                folder.insert(QStringLiteral("path"), root);
                folder.insert(QStringLiteral("fileCount"), folderFiles.value(name).length());
                folder.insert(QStringLiteral("files"), folderFiles.value(name));
                folders.append(folder);
            }

            totalFiles += rootFiles;
            qDebug() << "BackupEngine scanMedia root" << root << "found" << rootFiles << "media files";
        }

        qDebug() << "BackupEngine scan finished:" << folders.length() << "folders,"
                 << totalFiles << "files, roots:" << m_roots;

        // Emit directly: auto-queued connections deliver it on the GUI thread
        emit m_engine->mediaScanStatus(picsExists, picsReadable, vidsExists, vidsReadable);
        emit m_engine->mediaScanFinished(folders);
    }

private:
    QStringList m_roots;
    BackupEngine *m_engine;
};

} // namespace

BackupEngine::BackupEngine(QObject *parent)
    : QObject(parent)
    , m_nam(new QNetworkAccessManager(this))
    , m_reply(nullptr)
    , m_downloadReply(nullptr)
    , m_mediaProxy(new MediaProxyServer(this))
    , m_stopRequested(false)
{
}

QString BackupEngine::mediaProxyUrl(const QString &url)
{
    if (!m_mediaProxy || url.isEmpty()) return QString();
    return static_cast<MediaProxyServer *>(m_mediaProxy)->registerUrl(url);
}

void BackupEngine::mediaProxyShutdown()
{
    if (m_mediaProxy) {
        static_cast<MediaProxyServer *>(m_mediaProxy)->shutdown();
    }
}

QString BackupEngine::picturesPath()
{
    QString path = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation);
    if (path.isEmpty()) {
        path = QDir::homePath() + QStringLiteral("/Pictures");
    }
    return path;
}

// Looks for a preview image stored next to a local video (same basename,
// image extension). The Ubuntu Touch camera apps keep poster/cover images
// beside the recordings in some cases.
QString BackupEngine::localVideoPreview(const QString &videoPath) const
{
    const QFileInfo video(videoPath);
    if (videoPath.isEmpty() || !video.exists()) return QString();

    const QString base = video.absolutePath() + QLatin1Char('/') + video.completeBaseName();
    static const QStringList exts = {
        QStringLiteral(".jpg"), QStringLiteral(".jpeg"), QStringLiteral(".png"),
        QStringLiteral(".webp"), QStringLiteral(".gif"), QStringLiteral(".bmp")
    };
    for (const QString &ext : exts) {
        const QString candidate = base + ext;
        if (QFileInfo::exists(candidate)) {
            return candidate;
        }
    }
    return QString();
}

void BackupEngine::scanMedia()
{
    QStringList roots;
    roots << picturesPath();
    QString videos = QStandardPaths::writableLocation(QStandardPaths::MoviesLocation);
    if (videos.isEmpty()) {
        videos = QDir::homePath() + QStringLiteral("/Videos");
    }
    roots << videos;

    QThreadPool::globalInstance()->start(new ScanTask(roots, this));
}

// Media Hub (the system player used by QtMultimedia on Ubuntu Touch) refuses
// to open media from ~/Pictures or ~/Videos for confined click apps. It only
// allows the app's own private dirs (~/.cache/<app>/, ~/.local/share/<app>/).
// So before playback we expose the video from the app cache: hardlink when
// possible (same filesystem, no extra disk usage), otherwise copy.
QString BackupEngine::cacheMediaForPlayback(const QString &srcPath)
{
    QFileInfo src(srcPath);
    if (srcPath.isEmpty() || !src.exists()) {
        return QUrl::fromLocalFile(srcPath).toString();
    }

    const QString cacheDir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    if (cacheDir.isEmpty()) {
        return QUrl::fromLocalFile(srcPath).toString();
    }
    QDir dir(cacheDir);
    if (!dir.exists()) {
        dir.mkpath(QStringLiteral("."));
    }

    const QString dest = dir.filePath(QStringLiteral("playback-")
                                      + src.fileName());
    const QFileInfo destInfo(dest);
    const bool needCreate = !destInfo.exists() || destInfo.size() != src.size();

    if (needCreate) {
        QFile::remove(dest);
        if (!QFile::link(srcPath, dest) && !QFile::copy(srcPath, dest)) {
            qWarning() << "BackupEngine cacheMediaForPlayback: failed to cache" << srcPath;
            return QUrl::fromLocalFile(srcPath).toString();
        }
    }

    qDebug() << "BackupEngine cacheMediaForPlayback:" << srcPath << "->" << dest;
    return QUrl::fromLocalFile(dest).toString();
}

// Read the display size ("WxH") of an mp4/mov file from its header
// (tkhd box: pixel size + rotation matrix; mvhd is used as a rotation
// fallback). Rotation of 90/270 degrees swaps the dimensions, matching
// what Media Hub renders.
QString BackupEngine::mediaDimensions(const QString &srcPath) const
{
    QFile f(srcPath);
    if (!f.open(QIODevice::ReadOnly)) return QString();
    const qint64 fileSize = f.size();

    auto readBoxHeader = [&f, fileSize](quint64 &size, QByteArray &type, quint64 &headerBytes) -> bool {
        QByteArray h = f.read(8);
        if (h.size() < 8) return false;
        type = h.mid(4, 4);
        quint64 sz = qFromBigEndian<quint32>(reinterpret_cast<const uchar *>(h.constData()));
        headerBytes = 8;
        if (sz == 1) {
            QByteArray big = f.read(8);
            if (big.size() < 8) return false;
            sz = qFromBigEndian<quint64>(reinterpret_cast<const uchar *>(big.constData()));
            headerBytes = 16;
        } else if (sz == 0) {
            sz = quint64(fileSize - f.pos() + qint64(headerBytes));
        }
        if (sz < headerBytes) return false;
        size = sz;
        return true;
    };

    auto readI32 = [](const QByteArray &p, int off) -> qint32 {
        if (off < 0 || off + 4 > p.size()) return 0;
        qint32 v = 0;
        memcpy(&v, p.constData() + off, 4);
        return qFromBigEndian<qint32>(v);
    };
    auto readU32 = [](const QByteArray &p, int off) -> quint32 {
        if (off < 0 || off + 4 > p.size()) return 0;
        quint32 v = 0;
        memcpy(&v, p.constData() + off, 4);
        return qFromBigEndian<quint32>(v);
    };

    quint32 width = 0;
    quint32 height = 0;
    bool rotated = false;

    while (f.pos() + 8 <= fileSize) {
        quint64 size;
        QByteArray type;
        quint64 hb;
        if (!readBoxHeader(size, type, hb)) break;
        if (size < hb) break;
        const qint64 step = qint64(size) - qint64(hb);
        if (step <= 0) break;
        if (type == "moov") {
            const qint64 moovEnd = f.pos() + step;
            while (f.pos() + 8 <= moovEnd) {
                quint64 csize;
                QByteArray ctype;
                quint64 chb;
                if (!readBoxHeader(csize, ctype, chb)) break;
                if (csize < chb) break;
                const qint64 cstep = qint64(csize) - qint64(chb);
                if (cstep <= 0) break;
                const qint64 childEnd = f.pos() + cstep;
                if (ctype == "mvhd") {
                    const QByteArray p = f.read(int(qMin<qint64>(childEnd - f.pos(), 4096)));
                    const int version = p.isEmpty() ? 0 : int(p.at(0));
                    const int moff = (version == 1) ? 48 : 36;
                    const qint32 a = readI32(p, moff);
                    const qint32 b = readI32(p, moff + 4);
                    const qint32 c = readI32(p, moff + 12);
                    const qint32 d = readI32(p, moff + 16);
                    if ((a == 0 && b == 0x00010000 && c == -0x00010000 && d == 0)
                            || (a == 0 && b == -0x00010000 && c == 0x00010000 && d == 0)) {
                        rotated = true;
                    }
                    f.seek(childEnd);
                } else if (ctype == "trak") {
                    const qint64 trakEnd = childEnd;
                    while (f.pos() + 8 <= trakEnd) {
                        quint64 ksize;
                        QByteArray ktype;
                        quint64 khb;
                        if (!readBoxHeader(ksize, ktype, khb)) break;
                        if (ksize < khb) break;
                        const qint64 kstep = qint64(ksize) - qint64(khb);
                        if (kstep <= 0) break;
                        const qint64 kEnd = f.pos() + kstep;
                        if (ktype == "tkhd" && ksize >= 92) {
                            const QByteArray p = f.read(int(qMin<qint64>(kEnd - f.pos(), 4096)));
                            const int version = p.isEmpty() ? 0 : int(p.at(0));
                            const int moff = (version == 1) ? 52 : 40;
                            const qint32 a = readI32(p, moff);
                            const qint32 b = readI32(p, moff + 4);
                            const qint32 c = readI32(p, moff + 12);
                            const qint32 d = readI32(p, moff + 16);
                            const quint32 w = readU32(p, moff + 36) >> 16;
                            const quint32 h = readU32(p, moff + 40) >> 16;
                            const bool r = (a == 0 && b == 0x00010000 && c == -0x00010000 && d == 0)
                                    || (a == 0 && b == -0x00010000 && c == 0x00010000 && d == 0);
                            if (r) rotated = true;
                            if (w > 0 && h > 0) {
                                width = w;
                                height = h;
                            }
                            if (width > 0 && height > 0) break;
                        }
                        f.seek(kEnd);
                    }
                    f.seek(trakEnd);
                } else {
                    f.seek(childEnd);
                }
            }
            break;
        }
        f.seek(f.pos() + step);
    }

    if (width == 0 || height == 0) {
        qDebug() << "BackupEngine mediaDimensions: not found in" << srcPath;
        return QString();
    }
    if (rotated) qSwap(width, height);
    qDebug() << "BackupEngine mediaDimensions result:" << srcPath
             << QString::number(width) + "x" + QString::number(height)
             << "rotated=" << rotated;
    return QString::number(width) + QLatin1Char('x') + QString::number(height);
}

// Download a server-side video into the app cache so Media Hub can play it
// from a file:// path it is allowed to access (https streaming through the
// Android media stack is unreliable on Ubuntu Touch).
void BackupEngine::downloadMediaForPlayback(const QString &url, const QString &destName)
{
    const QString cacheDir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    if (cacheDir.isEmpty() || url.isEmpty()) {
        emit mediaDownloaded(url, QString(), false, QStringLiteral("No cache dir available"));
        return;
    }
    QDir dir(cacheDir);
    if (!dir.exists()) {
        dir.mkpath(QStringLiteral("."));
    }

    // Keep the playback cache bounded: drop older playback files
    const QFileInfoList oldFiles = dir.entryInfoList(QStringList() << QStringLiteral("playback-*"),
                                                     QDir::Files);
    for (const QFileInfo &fi : oldFiles) {
        QFile::remove(fi.filePath());
    }

    if (m_downloadReply) {
        m_downloadReply->abort();
        m_downloadReply->deleteLater();
        m_downloadReply = nullptr;
    }

    const QString dest = dir.filePath(destName);
    QFile *file = new QFile(dest);
    if (!file->open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        qWarning() << "BackupEngine downloadMediaForPlayback: cannot open" << dest;
        delete file;
        emit mediaDownloaded(url, QString(), false, QStringLiteral("Cannot create cache file"));
        return;
    }

    QNetworkRequest req{QUrl(url)};
    req.setRawHeader("Accept", "*/*");
    QNetworkReply *reply = m_nam->get(req);
    m_downloadReply = reply;
    connect(reply, QOverload<const QList<QSslError>&>::of(&QNetworkReply::sslErrors),
            reply, QOverload<>::of(&QNetworkReply::ignoreSslErrors));
    qDebug() << "BackupEngine downloadMediaForPlayback: downloading" << maskedUrlForLog(url);

    QTimer *timeoutTimer = new QTimer(reply);
    timeoutTimer->setSingleShot(true);
    connect(timeoutTimer, &QTimer::timeout, reply, &QNetworkReply::abort);
    timeoutTimer->start(10 * 60 * 1000);

    connect(reply, &QNetworkReply::readyRead, this, [reply, file]() {
        if (file->isOpen()) {
            file->write(reply->readAll());
        }
    });

    connect(reply, &QNetworkReply::downloadProgress, this,
            [this, url](qint64 received, qint64 total) {
                emit mediaDownloadProgress(url, received, total);
            });

    connect(reply, &QNetworkReply::finished, this, [this, reply, file, url, dest]() {
        if (m_downloadReply == reply) m_downloadReply = nullptr;
        file->close();
        const bool ok = (reply->error() == QNetworkReply::NoError) && file->size() > 0;
        const QString err = reply->errorString();
        file->deleteLater();
        reply->deleteLater();
        if (!ok) {
            QFile::remove(dest);
            qWarning() << "BackupEngine downloadMediaForPlayback: failed:" << err;
        } else {
            qDebug() << "BackupEngine downloadMediaForPlayback: saved" << dest
                     << "bytes:" << QFileInfo(dest).size();
        }
        emit mediaDownloaded(url, ok ? dest : QString(), ok, err);
    });
}

void BackupEngine::onScanTaskDone(const QVariantList &folders)
{
    emit mediaScanFinished(folders);
}

// Uploads a file to Synology Photos via SYNO.Foto.Upload.Item.
// Reverse-engineered request format (see references/ and the community
// documentation of the Synology Photos API):
//   POST <server>/webapi/entry.cgi   (multipart/form-data)
//   fields:  api=SYNO.Foto.Upload.Item  version=1  method=upload
//            name='"<filename>"'  duplicate='"ignore"'  folder='["<folder>"]'
//   file:    <binary content>
//   headers: X-Syno-Token, Cookie: id=<sid>
//   response: {success:true, data:{action, id, unit_id}}
void BackupEngine::uploadAsset(const QString &serverUrl, const QString &sid,
                               const QString &synoToken, const QString &folder,
                               const QString &filePath)
{
    m_stopRequested = false;
    if (m_reply) {
        m_reply->abort();
        m_reply->deleteLater();
        m_reply = nullptr;
    }

    QFileInfo fileInfo(filePath);
    if (!fileInfo.exists()) {
        emit uploadFinished(filePath, false, 0, QString(), QString(), QStringLiteral("File not found"));
        return;
    }

    QString base = serverUrl.trimmed();
    if (base.endsWith(QLatin1Char('/'))) base.chop(1);
    QUrl url(base + QStringLiteral("/webapi/entry.cgi"));

    qDebug() << "BackupEngine upload start:" << fileInfo.fileName()
             << "to" << url.toString() << "folder=" << folder;

    QNetworkRequest request(url);
    request.setRawHeader("Accept", "application/json");
    if (!synoToken.isEmpty()) {
        request.setRawHeader("X-Syno-Token", synoToken.toUtf8());
    }
    if (!sid.isEmpty()) {
        request.setRawHeader("Cookie", ("id=" + sid).toUtf8());
    }

    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly)) {
        emit uploadFinished(filePath, false, 0, QString(), QString(), QStringLiteral("Cannot open file"));
        return;
    }

    // Build the multipart body by hand: the DSM upload parser rejects
    // Qt-generated multipart (quoted boundary -> error 101) and also parts
    // carrying a Content-Type header. Use a plain unquoted boundary.
    const QByteArray boundary = QByteArrayLiteral("SynoPhotosUploadBoundary7x3aQm9");
    const QByteArray fileName = fileInfo.fileName().toUtf8();

    QByteArray body;
    auto addField = [&body, &boundary](const QByteArray &name, const QByteArray &value) {
        body += "--" + boundary + "\r\n";
        body += "Content-Disposition: form-data; name=\"" + name + "\"\r\n";
        body += "\r\n";
        body += value + "\r\n";
    };

    // JSON-wrapped string values, matching the official mobile app
    addField("api", "SYNO.Foto.Upload.Item");
    addField("version", "1");
    addField("method", "upload");
    addField("name", "\"" + fileName + "\"");
    addField("duplicate", "\"ignore\"");
    addField("folder", "[\"" + (folder.isEmpty() ? QStringLiteral("PhotoLibrary") : folder).toUtf8() + "\"]");

    body += "--" + boundary + "\r\n";
    body += "Content-Disposition: form-data; name=\"file\"; filename=\"" + fileName + "\"\r\n";
    body += "Content-Type: " + mimeForFile(filePath).toUtf8() + "\r\n";
    body += "\r\n";
    body += file.readAll();
    file.close();
    body += "\r\n--" + boundary + "--\r\n";

    request.setHeader(QNetworkRequest::ContentTypeHeader,
                      QStringLiteral("multipart/form-data; boundary=") + QString::fromLatin1(boundary));

    QBuffer *buffer = new QBuffer;
    buffer->setData(body);
    buffer->open(QIODevice::ReadOnly);

    m_currentUploadPath = filePath;
    QNetworkReply *reply = m_nam->post(request, buffer);
    buffer->setParent(reply);
    m_reply = reply;
    connect(reply, QOverload<const QList<QSslError>&>::of(&QNetworkReply::sslErrors),
            reply, QOverload<>::of(&QNetworkReply::ignoreSslErrors));

    // Guard against server stalls: abort after 10 minutes of inactivity
    QTimer *timeoutTimer = new QTimer(reply);
    timeoutTimer->setSingleShot(true);
    connect(timeoutTimer, &QTimer::timeout, reply, &QNetworkReply::abort);
    timeoutTimer->start(10 * 60 * 1000);

    connect(reply, &QNetworkReply::uploadProgress, this,
            [this, filePath, reply](qint64 sent, qint64 total) {
                if (m_reply != reply) return; // stale (aborted) reply
                emit uploadProgress(filePath, sent, total);
            });

    connect(reply, &QNetworkReply::finished, this, [this, filePath, reply]() {
        bool stale = (m_reply != reply);
        if (m_reply == reply) m_reply = nullptr;

        QByteArray body = reply->readAll();
        bool success = (reply->error() == QNetworkReply::NoError);
        int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        QString status;
        QString assetId;
        QString errorMessage = reply->errorString();

        if (stale) {
            // This reply was aborted (stop) before it completed: ignore
            reply->deleteLater();
            return;
        }

        qDebug() << "BackupEngine upload finished:" << filePath
                 << "ok:" << success << "http:" << httpStatus
                 << "err:" << errorMessage
                 << "body:" << QString::fromUtf8(body.left(300));

        // The DSM webapi often closes the connection right after answering,
        // so Qt may report RemoteHostClosedError even though a complete JSON
        // response was received. Parse the body first and trust it when it
        // is a well-formed API response.
        QJsonDocument doc = QJsonDocument::fromJson(body);
        if (doc.isObject()) {
            QJsonObject root = doc.object();
            if (root.contains(QStringLiteral("success"))) {
                if (root.value(QStringLiteral("success")).toBool()) {
                    success = true;
                    errorMessage.clear();
                    QJsonObject data = root.value(QStringLiteral("data")).toObject();
                    const QString action = data.value(QStringLiteral("action")).toString();
                    assetId = data.value(QStringLiteral("id")).toString();
                    if (assetId.isEmpty()) {
                        assetId = QString::number(data.value(QStringLiteral("unit_id")).toDouble());
                    }
                    // The server skips the file when duplicate=ignore
                    if (action == QLatin1String("skip")) {
                        status = QStringLiteral("duplicate");
                    }
                    if (status.isEmpty()) status = QStringLiteral("created");
                } else {
                    success = false;
                    const QJsonObject errObj = root.value(QStringLiteral("error")).toObject();
                    const int errCode = errObj.value(QStringLiteral("code")).toInt();
                    errorMessage = QStringLiteral("Server error %1").arg(errCode > 0 ? errCode : 100);
                }
            }
        }

        if (!success && status.isEmpty()) {
            if (httpStatus == 401) {
                errorMessage = QStringLiteral("Session expired");
            } else if (reply->error() == QNetworkReply::OperationCanceledError) {
                errorMessage = m_stopRequested ? QStringLiteral("Stopped") : QStringLiteral("Upload timed out");
            }
        }

        emit uploadFinished(filePath, success, httpStatus, status, assetId, errorMessage);
        reply->deleteLater();
    });
}

void BackupEngine::cancelUpload()
{
    m_stopRequested = true;
    if (m_reply) {
        m_reply->abort();
        m_reply->deleteLater();
        m_reply = nullptr;
    }
}

QStringList BackupEngine::deleteLocalFiles(const QStringList &paths)
{
    QStringList deleted;
    for (const QString &path : paths) {
        if (QFile::remove(path)) {
            deleted.append(path);
        }
    }
    qDebug() << "BackupEngine deleted local files:" << deleted.length() << "of" << paths.length();
    return deleted;
}
