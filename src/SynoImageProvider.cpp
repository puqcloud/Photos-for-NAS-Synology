#include "SynoImageProvider.h"
#include <QUrl>
#include <QNetworkReply>
#include <QStringList>
#include <QDebug>
#include <QQuickTextureFactory>
#include <QImageReader>
#include <QThreadPool>
#include <QRunnable>
#include <QMetaObject>

namespace {

// Decodes a local image file in a worker thread, forcing EXIF orientation
// (Qt 5.12's JPEG plugin does not transform by default, so QML Image shows
// portrait photos sideways)
class LocalDecodeTask : public QRunnable
{
public:
    LocalDecodeTask(const QString &path, const QSize &requestedSize, bool squareCrop,
                    QPointer<SynoImageResponse> response)
        : m_path(path), m_requestedSize(requestedSize), m_squareCrop(squareCrop), m_response(response)
    {
        setAutoDelete(true);
    }

    void run() override
    {
        QImage result;
        bool ok = false;
        QImageReader reader(m_path);
        reader.setAutoTransform(true);
        if (!m_squareCrop && m_requestedSize.isValid() && m_requestedSize.width() > 0) {
            const QSize src = reader.size();
            if (src.isValid()
                && (src.width() > m_requestedSize.width() * 2 || src.height() > m_requestedSize.height() * 2)) {
                reader.setScaledSize(m_requestedSize * 2);
            }
        }
        QImage img = reader.read();
        if (!img.isNull()) {
            // Grid thumbnails: center-crop to a square so the image can never
            // be stretched regardless of the item's fill mode
            if (m_squareCrop) {
                const int side = qMin(img.width(), img.height());
                if (side > 0) {
                    const int x = (img.width() - side) / 2;
                    const int y = (img.height() - side) / 2;
                    img = img.copy(x, y, side, side);
                    if (side > 512) {
                        img = img.scaled(512, 512, Qt::KeepAspectRatio, Qt::SmoothTransformation);
                    }
                }
            }
            result = img;
            ok = true;
        }
        if (m_response) {
            QMetaObject::invokeMethod(m_response.data(), "onLocalDecoded", Qt::QueuedConnection,
                                      Q_ARG(QImage, result), Q_ARG(bool, ok));
        }
    }

private:
    QString m_path;
    QSize m_requestedSize;
    bool m_squareCrop;
    QPointer<SynoImageResponse> m_response;
};

} // namespace

SynoImageProvider::SynoImageProvider()
    : QObject(nullptr)
{
    m_cache.setMaxCost(50 * 1024 * 1024); // 50 MB cache
}

QImage SynoImageProvider::cachedImage(const QString &key)
{
    QMutexLocker locker(&m_cacheMutex);
    QImage *cached = m_cache.object(key);
    return cached ? *cached : QImage();
}

void SynoImageProvider::storeImage(const QString &key, const QImage &image, int cost)
{
    if (image.isNull() || key.isEmpty()) return;
    QMutexLocker locker(&m_cacheMutex);
    if (!m_cache.contains(key)) {
        m_cache.insert(key, new QImage(image), qMax(1, cost));
    }
}

int SynoImageProvider::cacheSizeBytes() const
{
    QMutexLocker locker(&m_cacheMutex);
    return m_cache.totalCost();
}

void SynoImageProvider::clearCache()
{
    QMutexLocker locker(&m_cacheMutex);
    m_cache.clear();
}

QQuickImageResponse *SynoImageProvider::requestImageResponse(const QString &id, const QSize &requestedSize)
{
    // id formats:
    //   local/<percent-encoded path>/<size token>  — device file decode
    //   remote/<encoded url>/<size token>          — server thumbnail fetch
    QStringList parts = id.split("/");
    if (parts.length() < 2) {
        qWarning() << "Invalid Syno image ID format:" << id;
        QImage empty(1, 1, QImage::Format_ARGB32);
        empty.fill(Qt::transparent);
        return new SynoImageResponse(empty);
    }

    // Local file scheme: local/<percent-encoded path>/<size token>
    if (parts[0] == QLatin1String("local")) {
        // QUrl's id string may decode %2F into '/', so rebuild the path from
        // all segments between "local" and the trailing size token
        QString encPath;
        for (int i = 1; i < parts.length() - 1; ++i) {
            if (i > 1) encPath += QLatin1Char('/');
            encPath += parts[i];
        }
        const QString path = QUrl::fromPercentEncoding(encPath.toUtf8());
        if (path.isEmpty()) {
            QImage empty(1, 1, QImage::Format_ARGB32);
            empty.fill(Qt::transparent);
            return new SynoImageResponse(empty);
        }
        const QString sizeToken = parts.length() > 1 ? parts[parts.length() - 1] : QStringLiteral("m");
        QSize target;
        if (sizeToken == QLatin1String("sm")) target = QSize(256, 256);
        else if (sizeToken == QLatin1String("m")) target = QSize(1024, 1024);
        else if (sizeToken == QLatin1String("xl")) target = QSize(2560, 2560);
        const bool squareCrop = (sizeToken == QLatin1String("sm"));

        const QString cacheKey = QStringLiteral("local|") + path + QLatin1Char('|') + sizeToken;
        QImage cached = cachedImage(cacheKey);
        if (!cached.isNull()) {
            SynoImageResponse *response = new SynoImageResponse(cached);
            // Deliver asynchronously so the engine's signal connection is already in place
            QMetaObject::invokeMethod(response, "emitFinished", Qt::QueuedConnection);
            return response;
        }
        return new SynoImageResponse(path, cacheKey, target, this, squareCrop);
    }

    // Remote scheme: remote/<encoded url>/<size token>
    if (parts[0] == QLatin1String("remote")) {
        QString encUrl;
        for (int i = 1; i < parts.length() - 1; ++i) {
            if (i > 1) encUrl += QLatin1Char('/');
            encUrl += parts[i];
        }
        const QString urlStr = QUrl::fromPercentEncoding(encUrl.toUtf8());
        if (urlStr.isEmpty()) {
            QImage empty(1, 1, QImage::Format_ARGB32);
            empty.fill(Qt::transparent);
            return new SynoImageResponse(empty);
        }

        const QString cacheKey = QStringLiteral("remote|") + urlStr;
        QImage cached = cachedImage(cacheKey);
        if (!cached.isNull()) {
            SynoImageResponse *response = new SynoImageResponse(cached);
            QMetaObject::invokeMethod(response, "emitFinished", Qt::QueuedConnection);
            return response;
        }

        QNetworkRequest request{QUrl(urlStr)};
        request.setRawHeader("Accept", "image/jpeg, image/png, image/webp, */*");
        return new SynoImageResponse(request, cacheKey, requestedSize, this);
    }

    qWarning() << "Invalid Syno image ID format:" << id;
    QImage empty(1, 1, QImage::Format_ARGB32);
    empty.fill(Qt::transparent);
    return new SynoImageResponse(empty);
}

SynoImageResponse::SynoImageResponse(const QString &localPath, const QString &cacheKey,
                                     const QSize &requestedSize, SynoImageProvider *provider,
                                     bool squareCrop)
    : m_reply(nullptr)
    , m_timer(nullptr)
    , m_cacheKey(cacheKey)
    , m_requestedSize(requestedSize)
    , m_provider(provider)
    , m_finished(false)
{
    QThreadPool::globalInstance()->start(new LocalDecodeTask(localPath, requestedSize, squareCrop, this));
}

SynoImageResponse::SynoImageResponse(const QNetworkRequest &request, const QString &cacheKey,
                                     const QSize &requestedSize, SynoImageProvider *provider)
    : m_reply(nullptr)
    , m_timer(new QTimer(this))
    , m_cacheKey(cacheKey)
    , m_requestedSize(requestedSize)
    , m_provider(provider)
    , m_finished(false)
{
    m_timer->setSingleShot(true);
    connect(m_timer, &QTimer::timeout, this, [this]() {
        if (m_reply && !m_finished) m_reply->abort();
    });
    m_timer->start(20000); // 20s timeout

    // m_nam is created in this object's constructor, i.e. in the pixmap reader
    // thread, so issuing the request from here is thread-safe.
    m_reply = m_nam.get(request);
    connect(m_reply, QOverload<const QList<QSslError>&>::of(&QNetworkReply::sslErrors),
            m_reply, QOverload<>::of(&QNetworkReply::ignoreSslErrors));
    connect(m_reply, &QNetworkReply::finished, this, &SynoImageResponse::onFinished);
}

void SynoImageResponse::onLocalDecoded(const QImage &image, bool ok)
{
    if (m_finished) return;
    m_finished = true;
    m_image = image;
    if (!ok || m_image.isNull()) {
        m_image = QImage(1, 1, QImage::Format_ARGB32);
        m_image.fill(Qt::transparent);
    }
    if (m_provider && !m_cacheKey.isEmpty() && m_image.width() > 1) {
        m_provider->storeImage(m_cacheKey, m_image,
                               int(qint64(m_image.width()) * m_image.height() * 4));
    }
    emit finished();
}

SynoImageResponse::SynoImageResponse(const QImage &image)
    : m_reply(nullptr)
    , m_timer(nullptr)
    , m_image(image)
    , m_finished(false)
{
}

SynoImageResponse::~SynoImageResponse()
{
    if (m_reply) {
        m_reply->abort();
        m_reply->deleteLater();
    }
}

void SynoImageResponse::cancel()
{
    if (m_reply && !m_finished) m_reply->abort();
}

void SynoImageResponse::emitFinished()
{
    if (m_finished) return;
    m_finished = true;
    emit finished();
}

void SynoImageResponse::onFinished()
{
    if (m_finished) return;
    m_finished = true;
    if (m_timer) m_timer->stop();

    if (m_reply) {
        if (m_reply->error() == QNetworkReply::NoError) {
            m_image.loadFromData(m_reply->readAll());
        } else if (m_reply->error() != QNetworkReply::OperationCanceledError) {
            m_error = m_reply->errorString();
        }
        m_reply->deleteLater();
        m_reply = nullptr;
    }

    if (m_image.isNull()) {
        m_image = QImage(1, 1, QImage::Format_ARGB32);
        m_image.fill(Qt::transparent);
    }

    // Downscale to the requested size to save memory (only when it makes sense)
    if (m_requestedSize.isValid() && m_requestedSize.width() > 0 && m_requestedSize.height() > 0) {
        int w = m_image.width();
        int h = m_image.height();
        if (w > m_requestedSize.width() * 2 || h > m_requestedSize.height() * 2) {
            m_image = m_image.scaled(m_requestedSize * 2, Qt::KeepAspectRatio, Qt::SmoothTransformation);
        }
    }

    if (m_provider && !m_cacheKey.isEmpty() && m_image.width() > 1) {
        m_provider->storeImage(m_cacheKey, m_image, int(qint64(m_image.width()) * m_image.height() * 4));
    }

    emit finished();
}

QQuickTextureFactory *SynoImageResponse::textureFactory() const
{
    return QQuickTextureFactory::textureFactoryForImage(m_image);
}

QString SynoImageResponse::errorString() const
{
    return m_error;
}
