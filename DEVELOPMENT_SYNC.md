# GreenGuard AI Development Sync Report

November 21, 2026 (Philippines)

## Checkout and release state

Continue in `C:\Users\monda\.codex\worktrees\greenguard-reports-release\letus-plant-buyer-web`, on local branch `release/greenguard-readiness-20261121` based on `c24c6d2b`. Use `git log -1 --oneline` to identify the local release commit. The original Flutter checkout in `C:\Capstone\letus_plant` remains on local `main` at `0adf6571`, previously observed one commit ahead and 15 behind its tracked `origin/main`. The original nested web checkout has staged and unstaged work and a conflict in the generated `tsconfig.tsbuildinfo`. Keep both original checkouts intact. See `RELEASE_READINESS.md` for the latest overall report and rollout blockers. Exclude SDK paths, generated build files, and credentials from any future commit.

The user's current approval requirements cover pushing, deploying, applying migrations, installing dependencies, and altering INAV settings. None of those actions was taken while resuming from the master handover.

## Buyer marketplace

- Files changed: `lib/services/product_service.dart`, `lib/screens/buyer_home_screen.dart`, `app/api/route.ts`, and `app/page.tsx`.
- Production lacks `products.archived_at`. The earlier Flutter query returned PostgreSQL error `42703` and the UI rendered an empty catalog. Flutter retries only the missing archive-column case and surfaces other failures with a retry control. Web reads work with both schemas. Current stock and product identity come from Supabase, and sold out listings can be viewed without being purchased. Buyer listings refresh using realtime where available and periodic reads as a fallback.
- Real read checks: deployed web returned nine listings. The original Flutter projection with the archive filter returned 400 / 42703, and the compatible read returned 200 with nine listings. The updated local web production build also returned those nine listings.
- Pending: sign in as a new buyer on a phone, verify images and stock refresh after an authorized product change, and smoke-test signed-in checkout before rollout.

## Farmer product management

- Files: `lib/screens/sell_crop_screen.dart`, `lib/services/product_service.dart`, `lib/services/order_service.dart`, `app/page.tsx`, `app/api/route.ts`, and `supabase/migrations/202611210003_manage_product_inventory.sql`.
- The existing My Products implementation has Restock, Edit, and a confirmed Delete action that archives the listing while preserving order references. The latest mobile UI adds listing totals, search, and an out-of-stock filter. Publish Product keeps its existing form.
- Prior local PostgreSQL tests against the disposable matching schema passed for ownership checks, stock validation/restock, preserving order references during archive, and transactional checkout. Production writes were not tested. Listing reads work on the current schema. Safe product edits, restocks, archives, and the new checkout path need migration 003 and a coordinated rollout. Do not assume the new checkout works on the unmodified production schema.

## Health Logs and scan reports

- Files: `lib/screens/shared/health_logs_screen.dart`, `lib/screens/shared/scan_session_report_screen.dart`, `lib/screens/scan_screen.dart`, `lib/services/monitoring_service.dart`, `lib/models/lettuce_scan_report.dart`, `lib/widgets/lettuce_scan_report_card.dart`, `app/health-logs/page.tsx`, `app/page.tsx`, and `test/lettuce_scan_report_test.dart`.
- Scan History now has an explicit Overall Health Report action. Individual reports keep their photo and observed result, and saved sessions reopen their own reports. Counts come from the retrieved records. Both apps refresh history using scoped subscriptions where events are available and periodic refresh as a fallback. Web history reads scan records in pages.
- New Flutter captures use the existing UUID primary key for write retry deduplication, so migration 004 is not needed for mobile capture retries. The optional capture-location input was removed. Historical locations and marketplace listing locations are preserved.
- The latest local Health Logs entry returned HTTP 200. A read-only Supabase probe reported 19 real diagnostic records. Flutter tests covered expanded per-photo reports, the final session report, and overall report. A physical ESP32-CAM capture, signed-in realtime record creation, and cross-platform updates following a real write remain unverified.

## Live weather

- Files: `app/api/weather/route.ts`, `lib/use-weather-location.ts`, `app/page.tsx`, `app/health-logs/page.tsx`, `lib/screens/weather_screen.dart`, and `lib/services/weather_service.dart`.
- The website offers permission-based current location. Flutter checks permission and GPS first, and labels saved farm weather when using that fallback. City, temperature, humidity, condition, rain chance, and forecast come from the existing weather provider. Changed location triggers a new request, and failed requests display an unavailable state rather than fabricated defaults.
- Actual local web smoke tests returned provider locations, temperature, humidity and forecast for Cebu and Manila coordinates. An empty location returned HTTP 400. Android GPS permission denial and live movement still need device testing.

## Build and remaining verification

- Local Next.js production build and TypeScript checks passed. The web test suite passed 87 tests. The Flutter test suite passed 12 tests. Focused Dart analysis earlier found existing warnings and no errors; the final Android build compiled and packaged the latest Flutter source.
- APK: `build\app\outputs\flutter-apk\GreenGuard-AI-1.0.7-release.apk` in this worktree. Size 128,680,005 bytes. SHA-256 `45F30C22F36C69092251C49623AA854D3DCC47DB2A2DE0C7952133184E9D71E6`. Android signature verified using the project's existing debug signing configuration for the release variant.
- The existing Vercel website was queried as a baseline. The new version is local and has no production verification. No new production policies or migrations were applied. A read-only audit found pre-existing row security disabled for `products` and `diagnostic_logs`; review intended access before rollout.
- Next: obtain authorization for the migration and deployment, verify signed-in buyer and farmer actions and realtime updates with controlled records, then confirm the updated Vercel build. Keep any legacy device checkout compatibility in the rollout plan.
