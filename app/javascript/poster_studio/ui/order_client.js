const ERROR_MESSAGES = {
  wrong_size: "The exported PDF doesn't match the selected format — try again.",
  too_large:
    "The exported PDF is too large (50 MB max). Lower the DPI cap or zoom out.",
  unknown_sku: "This format is not orderable right now.",
  payment_unavailable:
    "Payment is temporarily unavailable — try again in a minute.",
  not_pdf: "The export didn't produce a valid PDF — try again.",
  unreadable: "The exported PDF couldn't be read — try again.",
}

export async function submitPrintOrder({
  url,
  blob,
  sku,
  title,
  themeBase,
  layoutId,
}) {
  const form = new FormData()
  form.append("file", blob, "poster.pdf")
  form.append("sku", sku)
  form.append("title", title || "")
  form.append("theme_base", themeBase || "")
  form.append("layout_id", layoutId)

  let response
  try {
    response = await fetch(url, { method: "POST", body: form })
  } catch {
    throw new Error(
      "Could not reach the order service — check your connection.",
    )
  }

  const body = await response.json().catch(() => ({}))
  if (!response.ok) {
    throw new Error(
      ERROR_MESSAGES[body.error] || "Order upload failed — try again.",
    )
  }
  return { token: body.token, checkoutUrl: body.checkout_url }
}
