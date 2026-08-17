#ifndef BACKUPENGINE_H
#define BACKUPENGINE_H

#include <QObject>
#include <QNetworkAccessManager>
#include <QVariantList>
#include <QStringList>

class QNetworkReply;

class BackupEngine : public QObject
{
    Q_OBJECT
public:
    explicit BackupEngine(QObject *parent = nullptr);

    Q_INVOKABLE QString picturesPath();
    Q_INVOKABLE QString cacheMediaForPlayback(const QString &srcPath);
    Q_INVOKABLE QString mediaDimensions(const QString &srcPath) const;
    // Returns the path of a local preview/cover image next to a video
    // (same basename, image extension), or "" when none exists.
    Q_INVOKABLE QString localVideoPreview(const QString &videoPath) const;
    Q_INVOKABLE void downloadMediaForPlayback(const QString &url, const QString &destName);
    Q_INVOKABLE QString mediaProxyUrl(const QString &url);
    Q_INVOKABLE void mediaProxyShutdown();
    Q_INVOKABLE void scanMedia();
    // Uploads a local file to the Synology Photos Personal Space via
    // SYNO.Foto.Upload.Item (multipart form data). `folder` is the target
    // folder name on the NAS (e.g. "MobileBackup").
    Q_INVOKABLE void uploadAsset(const QString &serverUrl, const QString &sid,
                                 const QString &synoToken, const QString &folder,
                                 const QString &filePath);
    Q_INVOKABLE void cancelUpload();
    Q_INVOKABLE QStringList deleteLocalFiles(const QStringList &paths);

signals:
    void mediaScanFinished(const QVariantList &folders);
    // Scan diagnostics: whether the media roots exist and are readable.
    // Helps the UI explain an empty folder list (e.g. AppArmor read denial).
    void mediaScanStatus(bool picturesExists, bool picturesReadable,
                         bool videosExists, bool videosReadable);
    void uploadProgress(const QString &filePath, qint64 sentBytes, qint64 totalBytes);
    void uploadFinished(const QString &filePath, bool success, int httpStatus,
                        const QString &status, const QString &assetId, const QString &errorMessage);
    void mediaDownloaded(const QString &url, const QString &filePath, bool success, const QString &error);
    void mediaDownloadProgress(const QString &url, qint64 received, qint64 total);

private slots:
    void onScanTaskDone(const QVariantList &folders);

private:
    QNetworkAccessManager *m_nam;
    QNetworkReply *m_reply;
    QNetworkReply *m_downloadReply;
    QObject *m_mediaProxy;
    QString m_currentUploadPath;
    bool m_stopRequested;
};

#endif // BACKUPENGINE_H
