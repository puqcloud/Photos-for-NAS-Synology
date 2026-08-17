#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickView>
#include <QQmlContext>
#include "SynoImageProvider.h"
#include "BackupEngine.h"

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationName("photos-for-nas-synology.puqsoftware");

    QQuickView view;
    view.setResizeMode(QQuickView::SizeRootObjectToView);

    // Async local-image provider (ownership is transferred to the engine)
    SynoImageProvider *imageProvider = new SynoImageProvider;
    view.engine()->addImageProvider(QLatin1String("syno"), imageProvider);
    view.rootContext()->setContextProperty("synoImageCache", imageProvider);

    // Backup engine (folder scan, media proxy for video playback, uploads)
    view.rootContext()->setContextProperty("backupEngine", new BackupEngine(&view));

    QString qmlPath = app.applicationDirPath() + "/qml/Main.qml";
    view.setSource(QUrl::fromLocalFile(qmlPath));
    view.show();

    return app.exec();
}
