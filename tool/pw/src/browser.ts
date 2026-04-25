/**
 * Browser lifecycle management with session persistence.
 *
 * Uses Playwright's browser server for persistent sessions.
 * `pw check` always launches fresh. Other commands reuse an existing session
 * if available, tracked via /tmp/pw-session.json.
 */

import { chromium, type Browser, type BrowserContext, type Page } from 'playwright';
import { readFileSync, writeFileSync, unlinkSync, existsSync } from 'node:fs';

const SESSION_FILE = '/tmp/pw-session.json';

interface Session {
  wsEndpoint: string;
  pid: number;
}

/**
 * Launch a new browser server and persist its WebSocket endpoint.
 * Returns a connected Browser instance.
 * If `persistent` is false, the session file is not written (for one-shot use).
 */
export async function launchBrowser(persistent = false): Promise<Browser> {
  // Clean up any stale session
  await closeBrowser();

  const server = await chromium.launchServer({
    headless: true,
    args: ['--disable-gpu', '--no-sandbox'],
  });

  if (persistent) {
    const session: Session = {
      wsEndpoint: server.wsEndpoint(),
      pid: server.process()!.pid!,
    };
    writeFileSync(SESSION_FILE, JSON.stringify(session));
  }

  // Store server reference so we can kill it when browser.close() is called
  const browser = await chromium.connect(server.wsEndpoint());

  // When this browser disconnects, also kill the server (unless persistent)
  if (!persistent) {
    browser.on('disconnected', () => {
      server.close().catch(() => {});
    });
  }

  return browser;
}

/** Connect to an existing browser session, or launch a new one. */
export async function getOrLaunchBrowser(): Promise<Browser> {
  if (existsSync(SESSION_FILE)) {
    try {
      const session: Session = JSON.parse(readFileSync(SESSION_FILE, 'utf-8'));
      // Quick liveness check: is the process still running?
      try {
        process.kill(session.pid, 0);
      } catch {
        // Process dead — clean up
        cleanupSessionFile();
        return launchBrowser();
      }
      const browser = await chromium.connect(session.wsEndpoint);
      return browser;
    } catch {
      cleanupSessionFile();
    }
  }
  return launchBrowser();
}

/** Get a page from the browser, creating a context if needed. */
export async function getPage(browser: Browser): Promise<{ context: BrowserContext; page: Page }> {
  const context = await browser.newContext({
    viewport: { width: 1280, height: 800 },
    deviceScaleFactor: 2,
  });
  const page = await context.newPage();
  return { context, page };
}

/** Close the persistent browser session. */
export async function closeBrowser(): Promise<void> {
  if (!existsSync(SESSION_FILE)) return;

  try {
    const session: Session = JSON.parse(readFileSync(SESSION_FILE, 'utf-8'));
    // Kill the server process directly
    try {
      process.kill(session.pid, 'SIGTERM');
    } catch {
      // Already dead
    }
  } catch {
    // Bad session file
  }
  cleanupSessionFile();
}

function cleanupSessionFile(): void {
  try {
    unlinkSync(SESSION_FILE);
  } catch {
    // Already gone
  }
}
