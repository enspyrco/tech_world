/**
 * Full deploy test: launch fresh browser → load app → sign in → screenshot.
 * This is the primary "did the deployment work?" workflow.
 *
 * Success state: reaching the room browser (proves Firebase, auth,
 * Firestore, and the full Flutter app are working).
 */

import { launchBrowser, getPage } from '../browser.js';
import {
  enableAccessibility,
  signInWithEmail,
  signInAnonymously,
  confirmCharacter,
} from '../auth.js';
import { waitForFlutterLoaded, waitForAppReady } from '../detect.js';

const DEFAULT_URL = 'https://world.imagineering.cc';

interface CheckOptions {
  url?: string;
  out?: string;
  method?: 'email' | 'anonymous';
}

export async function check(options: CheckOptions): Promise<void> {
  const url = options.url ?? process.env.PW_URL ?? DEFAULT_URL;
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const outPath = options.out ?? `pw-check-${timestamp}.png`;
  const method = options.method ?? (process.env.PW_EMAIL ? 'email' : 'anonymous');

  console.log(`Checking ${url} ...`);

  const browser = await launchBrowser();
  try {
    const { context, page } = await getPage(browser);

    await page.goto(url, { waitUntil: 'networkidle', timeout: 60_000 });

    console.log('Waiting for Flutter to load ...');
    await waitForFlutterLoaded(page);

    console.log('Enabling accessibility ...');
    await enableAccessibility(page);

    // Sign in
    if (method === 'email') {
      const email = process.env.PW_EMAIL;
      const password = process.env.PW_PASSWORD;
      if (!email || !password) {
        console.error('Error: PW_EMAIL and PW_PASSWORD env vars required for email sign-in.');
        console.error('Set them in tool/pw/.env or export them in your shell.');
        process.exit(1);
      }
      console.log(`Signing in as ${email} ...`);
      await signInWithEmail(page, email, password);
    } else {
      console.log('Signing in as guest ...');
      await signInAnonymously(page);
    }

    // Handle character selection
    console.log('Confirming character ...');
    await page.waitForTimeout(3000);
    await confirmCharacter(page);

    // Wait for the room browser or game to render
    await waitForAppReady(page);

    await page.screenshot({ path: outPath, fullPage: true });
    console.log(`Screenshot saved: ${outPath}`);

    await context.close();
  } finally {
    await browser.close();
  }
}
