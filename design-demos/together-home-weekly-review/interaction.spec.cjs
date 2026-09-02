const { test, expect } = require('playwright/test');

test.use({
  channel: 'chrome',
  viewport: { width: 1400, height: 1120 },
});

test('weekly speed dial opens and both destinations respond', async ({ page }) => {
  const pageErrors = [];
  page.on('pageerror', (error) => pageErrors.push(error.message));

  await page.goto(
    'file:///Users/papertiger/Desktop/Together/design-demos/together-home-weekly-review/home-weekly-review-menu.html'
  );

  const menuButtons = page.getByTestId('week-menu-button');
  await expect(menuButtons).toHaveCount(2);
  await expect(page.getByTestId('weekly-menu')).toHaveCount(2);
  await expect(page.locator('[data-testid="weekly-menu"][data-state="open"]')).toHaveCount(1);

  const expandedCompletedItem = page.locator('[data-state="open"] [data-testid="completed-menu-item"]');
  await expect(expandedCompletedItem).toHaveCSS('justify-content', 'flex-start');
  await expect(expandedCompletedItem).toHaveCSS('transform-origin', '196px 22px');
  await expect(expandedCompletedItem).toHaveText('本周已完成');

  await menuButtons.first().click();
  await expect(page.locator('[data-testid="weekly-menu"][data-state="open"]')).toHaveCount(2);

  const openedCompletedItem = page.getByTestId('completed-menu-item').first();
  await expect(openedCompletedItem).toHaveCSS('opacity', '1');
  await expect(openedCompletedItem).toHaveCSS('transform', 'matrix(1, 0, 0, 1, 0, 0)');

  await openedCompletedItem.click();
  await expect(page.getByText('已打开「本周已完成」')).toBeVisible();
  await expect(openedCompletedItem).toHaveCSS('opacity', '0');

  await menuButtons.first().click();
  await page.getByTestId('review-menu-item').first().click();
  await expect(page.getByText('已打开「计划复盘」')).toBeVisible();

  expect(pageErrors).toEqual([]);
});
