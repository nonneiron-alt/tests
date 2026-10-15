# Запуск и Cloudflare

## Разработка

Node.js 22+ LTS; зафиксированный Wrangler 4.151.0 устанавливается через `npm ci`. `wrangler.local.jsonc` не содержит реальных ресурсов: локальная D1 работает без удаленного database_id. Инициализация: `npm run db:local`. Секрет — в игнорируемом `.dev.vars`, образец рядом.

`npm run dev` запускает Worker, D1 и static assets в локальном runtime. Python не нужен. `server.py` — отдельный альтернативный сервер, не proxy к Workers.

## Первый деплой

В Windows запустите `deploy.ps1` из README. Для других ОС или ручного управления:

```bash
npm ci
export GROQ_API_KEY='your-new-key'
npm run deploy:setup
```

Ключ не передается в URL/аргументах Wrangler и не пишется в конфиг. Облачный Secret хранится отдельно от `.dev.vars`. После обновления с существующим ключом можно использовать:

```bash
KTO_KEEP_SECRET=1 npm run deploy:setup
```

Windows-аналог — `deploy.ps1 -KeepSecret`, который проверяет наличие секрета в Cloudflare. При обычном запуске будет предложен скрытый ввод ключа, если его нет в окружении.

Параметры Node-оркестратора через окружение:

- `KTO_WORKER_NAME`, по умолчанию `kto-ty-quiz`;
- `KTO_DATABASE_NAME`, по умолчанию `<worker-name>-db`;
- `KTO_DATABASE_ID`, необязательный **реальный** UUID существующей D1;
- `KTO_ACCOUNT_ID` или `CLOUDFLARE_ACCOUNT_ID`, фактический ID аккаунта;
- `KTO_KEEP_SECRET=1` — использовать имеющийся серверный ключ;
- `CLOUDFLARE_API_TOKEN` — опциональная token-auth вместо browser login, с правами на Workers/D1.

При нескольких аккаунтах может потребоваться явный account ID. Скрипт создает `wrangler.jsonc` с реальными binding DB/ASSETS, применяет миграции и публикует Worker. Этот файл игнорируется Git. Для последующих обновлений сохраняйте те же имена/ID. Обычный `npm run deploy` требует уже созданный `wrangler.jsonc` и не переустанавливает секрет.

Проверяйте адрес `workers.dev`, который напечатал Wrangler, и реально завершенное прохождение. Логи: `npm run logs`. Секрет можно сменить через `npm run secret` без изменения исходников. GitHub push сам по себе **не деплоит** сайт.

## Windows-ошибки из предыдущей сессии

- В старом PS1 `$PSScriptRoot` использовался в default-значении параметра и оказался пустым. В текущем wrapper путь вычисляется в теле скрипта.
- Список D1 раньше разбирался в PowerShell. Теперь JSON разбирается в Node, поддерживаются массивы/обертки и поля uuid/database_id/id. Это снижает зависимость от особенностей PowerShell 5.1.
- Текущий developer wrapper требует Node 22+, не скачивает portable Node и не является автономным install.ps1. Старый установщик намеренно исключен из Git из-за встроенного ключа.

## Старые SQLite-данные

В комплекте пользовательских данных нет. Чтобы разово перенести **свою** старую базу, сначала сохраните резервную копию, затем из папки проекта:

```powershell
New-Item -ItemType Directory -Force .deploy
python export_sqlite.py C:\path\to\quizzes.sqlite3 .deploy/import.sql
# После подготовки wrangler.jsonc:
npx wrangler d1 execute kto-ty-quiz-db --remote --file .deploy/import.sql --config wrangler.jsonc
Remove-Item .deploy/import.sql
```

Используйте ваше имя базы, если оно отличается. SQL содержит темы/ответы/результаты и не должен попадать в Git. Экспорт открывает SQLite только для чтения. Совпадающие темы не перезаписываются, plays обновляется по максимуму; сессии с уже существующим ID не заменяются. Это не двусторонняя синхронизация и не полноценный merge конфликтующих данных.

## Схема и миграции

Не редактируйте примененную `0001_schema.sql` ради production-обновления. Новая схема — новый пронумерованный SQL в `migrations/`, проверка локально и план обратной совместимости. Перед миграцией продакшена сделайте резервную копию/экспорт средствами D1. Никогда не удаляйте базу для устранения проблемы промпта.

Собственный домен подключается в Cloudflare Dashboard → Worker → Settings → Domains & Routes. В этом комплекте домен, аккаунт и ID базы не зафиксированы.
