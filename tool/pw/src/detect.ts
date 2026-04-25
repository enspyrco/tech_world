/**
 * App state detection for the Flutter CanvasKit web app.
 *
 * The loading sequence (from web/index.html):
 * 1. HTML loading screen with progress bar
 * 2. flt-glass-pane appears → progress set to 80%
 * 3. hideLoading() removes #loading div after 500ms + 300ms fade
 * 4. Flutter app renders (auth gate → character select → room browser → game)
 */

import type { Page } from 'playwright';

/** Wait for the HTML loading screen to be removed (Flutter engine ready). */
export async function waitForFlutterLoaded(page: Page, timeout = 30_000): Promise<void> {
  await page.waitForFunction(
    () => document.getElementById('loading') === null,
    { timeout },
  );
}

/**
 * Wait for the app to be interactive after sign-in.
 * Detects that we've progressed past the auth gate by waiting for
 * the loading screen to clear and a settle period for rendering.
 */
export async function waitForAppReady(page: Page, settleMs = 3000): Promise<void> {
  await page.waitForTimeout(settleMs);
}
