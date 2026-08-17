#ifndef SYNOIMAGEPROVIDER_H
#define SYNOIMAGEPROVIDER_H

#include <QObject>
#include <QPointer>
#include <QQuickAsyncImageProvider>
#include <QQuickImageResponse>
#include <QNetworkAccessManager>
#include <QNetworkRequest>
#include <QCache>
#include <QImage>
#include <QMutex>
#include <QTimer>

class SynoImageProvider;
class QNetworkReply;

// Decodes and delivers local image files (grid thumbs and full-screen
// previews) with EXIF orientation applied and an optional square crop,
// and fetches/caches remote server thumbnails.
class SynoImageResponse : public QQuickImageResponse
{
    Q_OBJECT
public:
    SynoImageResponse(const QString &localPath, const QString &cacheKey,
                      const QSize &requestedSize, SynoImageProvider *provider,
                      bool squareCrop = false);
    SynoImageResponse(const QNetworkRequest &request, const QString &cacheKey,
                      const QSize &requestedSize, SynoImageProvider *provider);
    explicit SynoImageResponse(const QImage &image);
    ~SynoImageResponse();

    QQuickTextureFactory *textureFactory() const override;
    QString errorString() const override;
    void cancel() override;

    Q_INVOKABLE void emitFinished();

private slots:
    void onLocalDecoded(const QImage &image, bool ok);

private:
    void onFinished();

    QNetworkAccessManager m_nam; // created in the pixmap reader thread; requests run there
    QNetworkReply *m_reply;
    QTimer *m_timer;
    QImage m_image;
    QString m_error;
    QString m_cacheKey;
    QSize m_requestedSize;
    QPointer<SynoImageProvider> m_provider;
    bool m_finished;
};

class SynoImageProvider : public QObject, public QQuickAsyncImageProvider
{
    Q_OBJECT
public:
    SynoImageProvider();

    QQuickImageResponse *requestImageResponse(const QString &id, const QSize &requestedSize) override;

    QImage cachedImage(const QString &key);
    void storeImage(const QString &key, const QImage &image, int cost);

    Q_INVOKABLE int cacheSizeBytes() const;
    Q_INVOKABLE void clearCache();

private:
    QCache<QString, QImage> m_cache;
    mutable QMutex m_cacheMutex;
};

#endif // SYNOIMAGEPROVIDER_H
