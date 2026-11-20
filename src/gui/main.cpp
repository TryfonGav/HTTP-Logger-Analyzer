#include "httplogger/version.hpp"

#include <QApplication>
#include <QLabel>
#include <QString>

int main(int argc, char* argv[]) {
    QApplication app(argc, argv);
    const auto v = httplogger::version();
    QLabel label(QStringLiteral("HTTP Logger & Analyzer %1 - GUI arrives in Phase 3")
                     .arg(QString::fromUtf8(v.data(), static_cast<qsizetype>(v.size()))));
    label.resize(480, 120);
    label.show();
    return QApplication::exec();
}
