/// Playwright / promo capture only — never enabled in production builds.
const screenshotDemo = bool.fromEnvironment('SCREENSHOT_DEMO', defaultValue: false);
