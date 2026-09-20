const DEFAULT_SUPPORT_EMAIL = "support@tenbelow.com";
const DEFAULT_WEBSITE_URL = "https://tenbelow.com";

/**
 * Shared transactional email configuration.
 * Logo is only used when TENBELOW_EMAIL_LOGO_URL is explicitly set.
 */
export function getTransactionalEmailConfig(overrides = {}) {
  const backendBaseUrl = String(process.env.BACKEND_URL || "http://localhost:3000").replace(/\/$/, "");
  const logoUrl = String(process.env.TENBELOW_EMAIL_LOGO_URL || "").trim();
  const websiteUrl = String(process.env.TENBELOW_WEBSITE_URL || DEFAULT_WEBSITE_URL).replace(/\/$/, "");
  const shopUrl = String(process.env.TENBELOW_SHOP_URL || process.env.TENBELOW_WEBSITE_URL || websiteUrl).replace(
    /\/$/,
    ""
  );

  return {
    supportEmail: process.env.SUPPORT_EMAIL || DEFAULT_SUPPORT_EMAIL,
    sellerSupportEmail:
      process.env.SELLER_SUPPORT_EMAIL ||
      process.env.SUPPORT_EMAIL ||
      DEFAULT_SUPPORT_EMAIL,
    websiteUrl,
    shopUrl,
    ordersUrl: String(
      process.env.TENBELOW_ORDERS_URL ||
      process.env.TENBELOW_WEBSITE_URL ||
      websiteUrl
    ).replace(/\/$/, ""),
    sellerDashboardUrl: String(
      process.env.TENBELOW_SELLER_DASHBOARD_URL ||
      process.env.TENBELOW_WEBSITE_URL ||
      websiteUrl
    ).replace(/\/$/, ""),
    sellerOrdersUrl: String(
      process.env.TENBELOW_SELLER_ORDERS_URL ||
      process.env.TENBELOW_SELLER_DASHBOARD_URL ||
      process.env.TENBELOW_WEBSITE_URL ||
      websiteUrl
    ).replace(/\/$/, ""),
    sellerResourcesUrl: String(process.env.TENBELOW_SELLER_RESOURCES_URL || "").trim(),
    sellerProductsUrl: String(
      process.env.TENBELOW_SELLER_PRODUCTS_URL ||
      process.env.TENBELOW_SELLER_DASHBOARD_URL ||
      process.env.TENBELOW_WEBSITE_URL ||
      websiteUrl
    ).replace(/\/$/, ""),
    logoUrl,
    termsUrl: process.env.TENBELOW_TERMS_URL || `${backendBaseUrl}/terms.html`,
    privacyUrl: process.env.TENBELOW_PRIVACY_URL || `${backendBaseUrl}/privacy.html`,
    backendBaseUrl,
    companyName: "Innovative CodeWorks LLC",
    brandName: "TenBelow",
    ...overrides,
  };
}
