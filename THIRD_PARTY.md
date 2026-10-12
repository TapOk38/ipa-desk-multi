# Внешний компонент

IPA Desk Multi вызывает неизменённый ipatool-cpp 1.0.9 из проекта
[Sorvigolova/ipatool](https://github.com/Sorvigolova/ipatool/releases/tag/1.0.9).
Проект основан на ipatool Majd Alfhaily; опубликованный MIT-текст сохранён в
`licenses/ipatool-MIT.txt`. Лицензия нашей оболочки не распространяется на чужие компоненты.

URL: https://github.com/Sorvigolova/ipatool/releases/download/1.0.9/windows_amd64_ipatool-cpp.zip

SHA-256 архива:
`264BE72D4B70E8A5540647277690FB47FCF1D7D6178ACF84629E93C0E564A331`

Член архива: `ipatool-cpp-windows-amd64.exe`, локальное имя `tools/cpp-1.0.9/ipatool-cpp.exe`.
SHA-256 EXE:
`394E8953D317F39645F03A1BFE039D0DC0FFC04291EB9D0F535BD1BBCA4F4581`

Хеши сверены с ранее полученным официальным архивом этой версии.
Автоматическое обновление на latest отсутствует. Изменение версии требует проверки и нового выпуска.

README upstream описывает встроенные Apple FairPlay dylib и Unicorn для их выполнения:
https://raw.githubusercontent.com/Sorvigolova/ipatool/1.0.9/README.md
Его MIT-файл сам по себе не подтверждает право на повторное распространение файлов Apple.
Поэтому собственная публичная поставка не содержит этот EXE или извлечённые SAP assets.
Пользователь получает компонент непосредственно из upstream; это не заключение о лицензировании
всего upstream-релиза. Условия его компонентов необходимо учитывать отдельно.
