#!/usr/bin/env node

/**
 * pw — Playwright workflow tool for Tech World.
 *
 * High-level browser automation commands that replace the Playwright MCP
 * plugin, which injected 20+ tool definitions into every Claude Code session.
 */

import { config } from 'dotenv';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Command } from 'commander';
import { check } from './commands/check.js';
import { screenshot } from './commands/screenshot.js';
import { evalCommand } from './commands/eval.js';
import { consoleCommand } from './commands/console.js';
import { signIn } from './commands/sign-in.js';
import { closeBrowser } from './browser.js';

// Load .env from the tool/pw directory
const __dirname = dirname(fileURLToPath(import.meta.url));
config({ path: resolve(__dirname, '..', '.env') });

const program = new Command();

program
  .name('pw')
  .description('Playwright workflow tool for Tech World')
  .version('0.1.0');

program
  .command('check')
  .description('Full deploy test: load app, sign in, take screenshot')
  .option('--url <url>', 'App URL')
  .option('--out <path>', 'Screenshot output path')
  .option('--method <method>', 'Auth method: email or anonymous')
  .action(check);

program
  .command('screenshot')
  .description('Take a screenshot of the app')
  .option('--url <url>', 'App URL')
  .option('--out <path>', 'Screenshot output path')
  .option('--full-page', 'Capture full page', true)
  .action(screenshot);

program
  .command('eval <expression>')
  .description('Evaluate JavaScript in the browser and print result')
  .option('--url <url>', 'App URL')
  .action(evalCommand);

program
  .command('console')
  .description('Capture console output for a duration')
  .option('--url <url>', 'App URL')
  .option('--duration <seconds>', 'Capture duration in seconds', '30')
  .option('--filter <level>', 'Filter: log, warn, error, all', 'all')
  .action(consoleCommand);

program
  .command('sign-in')
  .description('Sign in and leave browser running for subsequent commands')
  .option('--url <url>', 'App URL')
  .option('--method <method>', 'Auth method: email or anonymous')
  .action(signIn);

program
  .command('close')
  .description('Close any running browser session')
  .action(async () => {
    await closeBrowser();
    console.log('Browser session closed.');
  });

program.parse();
