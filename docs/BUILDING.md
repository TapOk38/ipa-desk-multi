# Сборка и тесты

Нужны Windows x64 и Windows PowerShell 5.1. Выполняйте команды из корня репозитория:

```powershell
$ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
& $ps -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Engine.ps1
& $ps -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Tools.ps1
& $ps -NoProfile -ExecutionPolicy Bypass -File .\Build-Release.ps1
```

Тесты используют вымышленные учётки и не подключаются к Apple.
У `Test-Tools.ps1` есть параметр `-OfficialArchive` для проверки уже скачанного официального ZIP.

Готовый архив создаётся в `dist/`. Сборка включает файлы по заданному списку;
учётки, скачанные IPA, журналы и папка `tools/` в него не входят.
Для повторной сборки укажите новую папку через `-Destination`.

Перед выпуском с изменениями программы проверьте скачивание, ввод 2FA, русские пути и отмену на реальной учётке.
