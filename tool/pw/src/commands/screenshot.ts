/**
 * Take a screenshot of the app. Navigates fresh each time.
 */

import { launchBrowser, getPage } from '../browser.js';
import { waitForFlutterLoaded } from '../detect.js';

const DEFAULT_URL = 'https://world.imagineering.cc';

interface ScreenshotOptions {
  url?: string;
  out?: string;
  fullPage?: boolean;
}

export async function screenshot(options: ScreenshotOptions): Promise<void> {
  const url = options.url ?? process.env.PW_URL ?? DEFAULT_URL;
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const outPath = options.out ?? `pw-screenshot-${timestamp}.png`;

  const browser = await launchBrowser();
  try {
    const { context, page } = await getPage(browser);

    await page.goto(url, { waitUntil: 'networkidle', timeout: 60_000 });
    await waitForFlutterLoaded(page).catch(() => {
      console.log('Note: loading screen may already be cleared.');
    });

    await page.screenshot({ path: outPath, fullPage: options.fullPage ?? true });
    console.log(`Screenshot saved: ${outPath}`);

    await context.close();
  } finally {
    await browser.close();
  }
}
