/**
 * Sign in to the app and leave the browser running for subsequent commands.
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

interface SignInOptions {
  url?: string;
  method?: string;
}

export async function signIn(options: SignInOptions): Promise<void> {
  const url = options.url ?? process.env.PW_URL ?? DEFAULT_URL;
  const method = options.method ?? (process.env.PW_EMAIL ? 'email' : 'anonymous');

  const browser = await launchBrowser(true);
  const { page } = await getPage(browser);

  await page.goto(url, { waitUntil: 'networkidle', timeout: 60_000 });

  console.log('Waiting for Flutter to load ...');
  await waitForFlutterLoaded(page);

  console.log('Enabling accessibility ...');
  await enableAccessibility(page);

  if (method === 'email') {
    const email = process.env.PW_EMAIL;
    const password = process.env.PW_PASSWORD;
    if (!email || !password) {
      console.error('Error: PW_EMAIL and PW_PASSWORD env vars required for email sign-in.');
      process.exit(1);
    }
    console.log(`Signing in as ${email} ...`);
    await signInWithEmail(page, email, password);
  } else {
    console.log('Signing in as guest ...');
    await signInAnonymously(page);
  }

  console.log('Confirming character ...');
  await page.waitForTimeout(3000);
  await confirmCharacter(page);

  await waitForAppReady(page);

  console.log('Signed in. Browser session is persistent — use `pw screenshot`, `pw eval`, etc.');
  console.log('Run `pw close` to terminate the browser.');
}
