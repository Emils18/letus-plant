# GreenGuard AI release readiness

November 21, 2026 (Philippines)

## Release decision

The integration candidate is ready for controlled staging. The website can be deployed first, after approval and a signed-in staging checkout, to bridge the existing and new schemas. Stop before applying inventory SQL until the bridge is live and tested, and the Android delivery-fee update is ready.

- Web Health Logs has expandable individual reports, farmer-owned session reports, and a dedicated Overall Health Report. The overall view derives total scans, healthy and at-risk totals, each disease count, unknown results, and average valid confidence from the visible Supabase records. The responsive layout refreshes through Supabase events or polling.
- Flutter has individual, session, and overall Health Logs, a compatible buyer catalog read, farmer listing management, and permission-based live weather.
- The public catalog comparison returned nine listings on both paths. The local production build served real weather for two locations and a read-only Supabase check found 19 scan records. The final production build and TypeScript passed, with 89 web tests and 13 Flutter tests passing. The updated Android 1.0.7 inventory APK signature verified with the existing project signing configuration.
- Production Vercel serves the previous deployment. Signed-in reconciliation between Web and Mobile, live product writes, and physical Android testing remain pending.

## Inventory migration review

`supabase/migrations/202611210003_manage_product_inventory.sql`

1. Adds nullable `products.archived_at`. Existing products remain active. Enables product RLS, retains public reads, permits unarchived writes by the owning farmer, and removes the named physical-delete policy. Both storefronts filter archived rows.
2. Adds authenticated restock and archive functions. Restock validates and atomically increments stock. Archive locks the listing, zeroes stock, and retains the listing and its order references.
3. Adds checkout triggers. The order trigger normalizes Delivery or Pickup, starts orders Unpaid, and preserves the delivery method and charge against direct edits. The line insert validates an owned pending order, locks stock, uses the stored product name and price, and recomputes the parent total from canonical line subtotals.
4. Enforces **₱50 per delivery order** and no fee for Pickup in PostgreSQL. The grouping flag only controls whether more than one seller is accepted. Mobile shows the fee per farmer before submission. Direct signed-in legacy writes receive the same database pricing. Older APKs can still submit signed-in orders, but they display the old delivery estimate. Confirm availability of the updated APK before enabling the migration.
5. The authenticated checkout RPC validates buyer role, contact fields and quantities, locks products, and creates all headers and lines in one transaction. The migration also enrolls products in the existing realtime publication if necessary.
6. The prior public web route already validated a signed-in buyer. Its database mutations used the anonymous Supabase client. The bridge keeps the HTTP and sign-in contract and writes with the verified buyer token. The website uses the existing server-priced checkout only if PostgREST explicitly says the new RPC is missing and the archive column is absent. An ambiguous response, timeout, or stock failure never attempts a second checkout. Guest checkout was not a supported public flow. Deploy the bridge before enabling the trigger that rejects unverified anonymous line writes.
7. Website, Flutter and Admin display new orders as Unpaid and normalize older records where the payment method was stored as the status. Existing Paid records and the delivered-to-received action remain supported. Receipt confirmation is a manual status transition, not proof from an external payment provider.

**Verification:** The disposable PostgreSQL fixture passed migration reapplication, delivery and pickup totals, grouped carts, tampered fee and status inputs, database prices, insufficient-stock rollback, existing signed-in order writes, restock, archive and anonymous RPC denial. A local HTTP fixture exercised the actual Next.js route with the pre-migration schema and the new RPC, plus the existing sign-in gate and no replay after rejection. Checkout unit tests cover the narrow fallback and payment display. SQL has not been applied to any shared database.

## Safe GitHub synchronization plan

1. The local integration branch is `integration/greenguard-inventory-20261121`, created from verified release commit `b08580a2`. Both original checkouts stay intact. The original Flutter checkout has `0adf6571` and uncommitted web work; the nested web checkout also has staged work and a generated `tsconfig.tsbuildinfo` conflict.
2. With approval, fetch current GitHub refs. Keep this local candidate intact and create a new integration branch from the latest `origin/main` if it has advanced. Replay only reviewed changes and compare the Flutter backup before selecting missing hunks. Rebuild and retest the exact candidate.
3. **First publish the bridge-only branch** `rollout/greenguard-checkout-bridge-20261121`, after approval for any push and automatic preview. It contains only the route and its two helper modules on the verified upstream base. Verify a signed-in order with the pre-migration schema and check its seller notification. This step does not introduce the new inventory controls.
4. **Then apply the individually reviewed migration 003**, only after database approval, the live bridge check, staging tests, and the mobile fee-display rollout decision. Check RPC schema-cache availability, then verify signed-in delivery/pickup, cross-client payment status, stock events and archived history. Omit unrelated pending SQL. Keep a rollback plan for both the app and database because the pre-bridge site is incompatible with the new trigger.
5. Verify the existing Vercel production alias and the Android phone after rollout. No push, deploy, or migration has been done as part of this change.

## Android phone verification

- Install or update the APK on the target phone and verify launch, sign-in and app data retention.
- Use real GPS with permission allowed, denied and disabled. Check fresh location, movement between areas, offline handling and retry.
- On the phone hotspot, connect to ESP32-CAM, capture one and several photos, test reconnect and upload retry, finish the session, and confirm each photo and the overall report appear without duplicate records on Web and Mobile.
- After the inventory migration is approved and validated, check buyer catalog refresh, photo replacement from camera and gallery, restock, archive, order-history preservation, and checkout on current and older APKs.
- Verify earlier soil-monitor changes on the real hotspot if those changes are included in a separate release. This release does not change INAV configuration.

Updated APK: `build/app/outputs/flutter-apk/GreenGuard-AI-1.0.7-inventory-candidate.apk` (128,680,005 bytes). SHA-256 `168A6B3F56FC1E45D1AC69BC6E2103370FA0D1EF39DD32F62243742281344B59`.
