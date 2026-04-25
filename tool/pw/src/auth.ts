/**
 * Firebase auth via Flutter's semantic DOM elements.
 *
 * Flutter web only populates the semantics tree when accessibility is
 * enabled. We trigger it by dispatching a click on flt-semantics-placeholder,
 * then interact with the real input/button elements that appear.
 */

import type { Page } from 'playwright';

/** Enable Flutter's accessibility tree (required before any semantic interaction). */
export async function enableAccessibility(page: Page): Promise<void> {
  await page.evaluate(() => {
    document.querySelector('flt-semantics-placeholder')
      ?.dispatchEvent(new Event('click', { bubbles: true }));
  });
  // Wait for the semantics tree to populate
  await page.waitForTimeout(1000);
}

/**
 * Sign in with email/password by filling the AuthGate form.
 * Requires enableAccessibility() to have been called first.
 */
export async function signInWithEmail(
  page: Page,
  email: string,
  password: string,
): Promise<void> {
  const emailInput = page.locator('input[aria-label="Email"]');
  await emailInput.click({ force: true });
  await page.waitForTimeout(200);
  await emailInput.fill(email);

  const passwordInput = page.locator('input[aria-label="Password"]');
  await passwordInput.click({ force: true });
  await page.waitForTimeout(200);
  await passwordInput.fill(password);

  await page.keyboard.press('Enter');
}

/**
 * Sign in anonymously by clicking "continue as guest".
 * Requires enableAccessibility() to have been called first.
 */
export async function signInAnonymously(page: Page): Promise<void> {
  const guest = page.getByText('continue as guest');
  await guest.click({ force: true });
}

/**
 * Handle the character selection screen by clicking "Confirm"
 * with the default character (Explorer).
 */
export async function confirmCharacter(page: Page, timeout = 15_000): Promise<void> {
  const confirm = page.getByText('Confirm');
  try {
    await confirm.waitFor({ timeout });
    await confirm.click({ force: true });
  } catch {
    // Character selection might be skipped if user has a saved character
  }
}
