// Display prices only — Stripe charges the price configured server-side.
export const PRINT_PRODUCTS = {
  "print-30x40": { sku: "poster-30x40", priceLabel: "€34.99" },
  "print-50x70": { sku: "poster-50x70", priceLabel: "€54.99" },
  "print-70x100": { sku: "poster-70x100", priceLabel: "€74.99" },
}

export function printProductFor(layoutId) {
  return PRINT_PRODUCTS[layoutId] || null
}
