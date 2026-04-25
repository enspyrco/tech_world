/**
 * Navigate to the app and capture console output for a specified duration.
 */

import { launchBrowser, getPage } from '../browser.js';

const DEFAULT_URL = 'https://world.imagineering.cc';

interface ConsoleOptions {
  url?: string;
  duration?: string;
  filter?: string;
}

export async function consoleCommand(options: ConsoleOptions): Promise<void> {
  const url = options.url ?? process.env.PW_URL ?? DEFAULT_URL;
  const duration = parseInt(options.duration ?? '30') * 1000;
  const filter = options.filter ?? 'all';

  const browser = await launchBrowser();
  try {
    const { context, page } = await getPage(browser);
    const messages: string[] = [];

    page.on('console', (msg) => {
      const type = msg.type();
      if (filter !== 'all' && type !== filter) return;
      const prefix = type === 'error' ? 'ERR' : type === 'warning' ? 'WRN' : 'LOG';
      messages.push(`[${prefix}] ${msg.text()}`);
    });

    page.on('pageerror', (error) => {
      if (filter !== 'all' && filter !== 'error') return;
      messages.push(`[EXC] ${error.message}`);
    });

    console.log(`Capturing console from ${url} for ${duration / 1000}s (filter: ${filter}) ...`);
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30_000 });

    await page.waitForTimeout(duration);

    if (messages.length === 0) {
      console.log('(no console messages captured)');
    } else {
      for (const msg of messages) {
        console.log(msg);
      }
      console.log(`\n--- ${messages.length} messages captured ---`);
    }

    await context.close();
  } finally {
    await browser.close();
  }
}
