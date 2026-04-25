/**
 * Evaluate a JavaScript expression in the browser page context.
 * Prints the result to stdout.
 */

import { launchBrowser, getPage } from '../browser.js';

const DEFAULT_URL = 'https://world.imagineering.cc';

interface EvalOptions {
  url?: string;
}

export async function evalCommand(expression: string, options: EvalOptions): Promise<void> {
  const url = options.url ?? process.env.PW_URL ?? DEFAULT_URL;

  const browser = await launchBrowser();
  try {
    const { context, page } = await getPage(browser);

    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30_000 });
    // Brief settle for scripts to execute
    await page.waitForTimeout(3000);

    const result = await page.evaluate(expression);
    console.log(typeof result === 'string' ? result : JSON.stringify(result, null, 2));

    await context.close();
  } finally {
    await browser.close();
  }
}
