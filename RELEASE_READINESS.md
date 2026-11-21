# GreenGuard AI release readiness

November 21, 2026 (Philippines)

## Release decision

The code and signed Android APK are ready for controlled testing. Production rollout is on hold pending the inventory and checkout checks below and explicit approval for each remote action.

- Web Health Logs has expandable individual reports, farmer-owned session reports, and a dedicated Overall Health Report. The overall view derives total scans, healthy and at-risk totals, each disease count, unknown results, and average valid confidence from the visible Supabase records. The responsive layout refreshes through Supabase events or polling.
- Flutter has individual, session, and overall Health Logs, a compatible buyer catalog read, farmer listing management, and permission-based live weather.
- The public catalog comparison returned nine listings on both paths. The local production build served real weather for two locations and a read-only Supabase check found 19 scan records. The web suite has 87 passing tests and Flutter has 12. The Android 1.0.7 release APK signature verified with the existing project signing configuration.
- Production Vercel serves the previous deployment. Signed-in reconciliation between Web and Mobile, live product writes, and physical Android testing remain pending.

## Inventory migration review

`supabase/migrations/202611210003_manage_product_inventory.sql`

1. Adds nullable `products.archived_at`. Existing product rows start unarchived. Enables products RLS with public reads, farmer-owned insert and update for unarchived rows, and removes the named farmer physical-delete policy. Archived rows stay readable at the table level for historical references. Both public storefronts exclude them from catalog results.
2. Adds authenticated `restock_farmer_product`. It validates a positive integer, atomically increments stock, updates availability and timestamp, and checks ownership, role, and archive state.
3. Adds authenticated `archive_farmer_product`. It locks and checks the farmer's row, reports whether order items reference it, timestamps the archive, and sets stock to zero and status to Out of Stock. This preserves product and order history. An existing stock trigger can still create an out-of-stock notification.
4. Adds an after-insert trigger on order items. It requires a pending order owned by the signed-in user, a positive quantity, and matching farmer and available product. It deducts stock atomically and rejects invalid or insufficient quantities. Existing data is unaffected by the trigger until a new order line is inserted.
5. Adds authenticated `place_marketplace_order`. It checks the buyer role and contact fields, combines duplicate product lines, locks product rows in a stable order, uses database prices, and inserts orders and lines in one transaction. It supports the established single-farmer web and grouped mobile flows. It adds products to the existing Supabase realtime publication when needed.

**Rollout blockers.** The older web checkout uses anonymous inserts that the new trigger would reject. Test a coordinated rollout with the new authenticated route, the current APK, and any installed older APKs. Confirm the delivery pricing rules before applying the migration. The client-supplied `p_single_farmer` flag currently also determines whether the server adds the ₱50 web delivery fee, so an authenticated caller can select the mobile path and avoid the fee. Separate pricing from this client-controlled grouping flag. Verify payment-state semantics as well. The candidate currently copies the payment method into `payment_status`, matching an earlier mobile convention. Review the resulting status across Web, Mobile, and Admin.

Use a staging database with the same policies, triggers, and constraints to verify concurrent orders, stock rollback, seller ownership, archived-product order history, and compatibility with the existing stock notification trigger. Review the pending migration list before any database write. The unrelated name-uniqueness migration and the unused capture-ID migration are outside this release.

## Safe GitHub synchronization plan

1. Keep the local release branch and both original checkouts intact. The release started from `c24c6d2b`. The original Flutter checkout has local commit `0adf6571` plus uncommitted web work. The original nested web checkout has staged and unstaged files and a conflict in generated `tsconfig.tsbuildinfo`.
2. After approval, fetch the current remote refs and create a separate integration branch from the latest `origin/main`. Compare the release diff with upstream and with the Flutter backup branch. Cherry-pick the release commit, then port only missing, reviewed Flutter hunks from the backup if needed. This avoids resurrecting unrelated changes or overwriting a newer remote fix.
3. Resolve any source conflicts on the integration branch. Repeat the build and tests there. Review the complete diff against `origin/main`, excluding generated registrants, SDK paths, build artifacts and credentials.
4. Push a review branch only after approval for the push and any automated Vercel preview. Keep it out of production `main` until the migration, compatibility and deployment plan are approved. A merge to a connected production branch can deploy automatically.
5. After separate database and deployment approvals, coordinate the cutover and verify the actual Vercel alias with signed-in test accounts. Review the database rollback plan together with application rollback because reverting Vercel alone would leave the new checkout trigger active.

## Android phone verification

- Install or update the APK on the target phone and verify launch, sign-in and app data retention.
- Use real GPS with permission allowed, denied and disabled. Check fresh location, movement between areas, offline handling and retry.
- On the phone hotspot, connect to ESP32-CAM, capture one and several photos, test reconnect and upload retry, finish the session, and confirm each photo and the overall report appear without duplicate records on Web and Mobile.
- After the inventory migration is approved and validated, check buyer catalog refresh, photo replacement from camera and gallery, restock, archive, order-history preservation, and checkout on current and older APKs.
- Verify earlier soil-monitor changes on the real hotspot if those changes are included in a separate release. This release does not change INAV configuration.
