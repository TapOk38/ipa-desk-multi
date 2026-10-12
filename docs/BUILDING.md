# Проверки и упаковка

Нужны Windows x64, Windows PowerShell 5.1 / .NET Framework. В PowerShell 7 тесты
CodeDOM/System.Web могут работать иначе; используйте `powershell.exe` из Windows.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Engine.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Tools.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\Build-Release.ps1
```

Тесты не используют реальные Apple ID и не подключаются к Apple. У Test-Tools есть
необязательный `-OfficialArchive`, чтобы дополнительно проверить распаковку уже скачанного
официального архива по его хешу. Без него тестируются синтетические архивы и отказы.
ZIP создаётся в `dist/` по явному списку файлов. `tools/`, скачанные IPA, учётки и тестовые
данные никогда не упаковываются. Наличие локально скачанного EXE не меняет состав ZIP.

Перед релизом проверьте реальное скачивание с согласованной учёткой, 2FA,
путь с кириллицей и отмену. Не публикуйте личные журналы. GitHub Actions выполняет
только локальные автоматические проверки, без аккаунта Apple.
