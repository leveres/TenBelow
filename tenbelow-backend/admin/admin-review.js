const queueGrid = document.querySelector("#queueGrid");
const emptyState = document.querySelector("#emptyState");
const queueCount = document.querySelector("#queueCount");
const queueFilterLabel = document.querySelector("#queueFilterLabel");
const feedbackText = document.querySelector("#feedbackText");
const refreshButton = document.querySelector("#refreshButton");
const refreshExchangeButton = document.querySelector("#refreshExchangeButton");
const refreshAuditButton = document.querySelector("#refreshAuditButton");
const exportAuditJsonButton = document.querySelector("#exportAuditJsonButton");
const exportAuditCsvButton = document.querySelector("#exportAuditCsvButton");
const refreshIncidentsButton = document.querySelector("#refreshIncidentsButton");
const refreshSnapshotsButton = document.querySelector("#refreshSnapshotsButton");
const statusFilter = document.querySelector("#statusFilter");
const sellerFilter = document.querySelector("#sellerFilter");
const listingTypeFilter = document.querySelector("#listingTypeFilter");
const sellerQueueSummary = document.querySelector("#sellerQueueSummary");
const sellerDirectoryList = document.querySelector("#sellerDirectoryList");
const sellerDirectoryCount = document.querySelector("#sellerDirectoryCount");
const accountKindFilter = document.querySelector("#accountKindFilter");
const accountSearchInput = document.querySelector("#accountSearchInput");
const accountPageSizeSelect = document.querySelector("#accountPageSizeSelect");
const refreshAccountsButton = document.querySelector("#refreshAccountsButton");
const accountTotalCount = document.querySelector("#accountTotalCount");
const accountList = document.querySelector("#accountList");
const accountPrevPage = document.querySelector("#accountPrevPage");
const accountNextPage = document.querySelector("#accountNextPage");
const accountPageInfo = document.querySelector("#accountPageInfo");
const customRequestStatusFilter = document.querySelector("#customRequestStatusFilter");
const customRequestSearchInput = document.querySelector("#customRequestSearchInput");
const refreshCustomRequestsButton = document.querySelector("#refreshCustomRequestsButton");
const customRequestCount = document.querySelector("#customRequestCount");
const customRequestEmpty = document.querySelector("#customRequestEmpty");
const customRequestList = document.querySelector("#customRequestList");
const exchangeStatusFilter = document.querySelector("#exchangeStatusFilter");
const exchangeQueueList = document.querySelector("#exchangeQueueList");
const exchangeQueueEmpty = document.querySelector("#exchangeQueueEmpty");
const exchangeQueueCount = document.querySelector("#exchangeQueueCount");
const exchangeDetailPanel = document.querySelector("#exchangeDetailPanel");
const auditLogList = document.querySelector("#auditLogList");
const auditSearchInput = document.querySelector("#auditSearchInput");
const auditPageSizeSelect = document.querySelector("#auditPageSizeSelect");
const auditPrevPage = document.querySelector("#auditPrevPage");
const auditNextPage = document.querySelector("#auditNextPage");
const auditPageInfo = document.querySelector("#auditPageInfo");
const metricAuthFailures = document.querySelector("#metricAuthFailures");
const metricOwnershipMismatches = document.querySelector("#metricOwnershipMismatches");
const metricTopScope = document.querySelector("#metricTopScope");
const alertTestSeverity = document.querySelector("#alertTestSeverity");
const alertTestMessage = document.querySelector("#alertTestMessage");
const triggerAlertTestButton = document.querySelector("#triggerAlertTestButton");
const incidentSearchInput = document.querySelector("#incidentSearchInput");
const incidentStateFilter = document.querySelector("#incidentStateFilter");
const incidentHistoryList = document.querySelector("#incidentHistoryList");
const snapshotKey = document.querySelector("#snapshotKey");
const snapshotSelect = document.querySelector("#snapshotSelect");
const compareSnapshotSelect = document.querySelector("#compareSnapshotSelect");
const previewRestoreButton = document.querySelector("#previewRestoreButton");
const restoreSnapshotButton = document.querySelector("#restoreSnapshotButton");
const compareSnapshotsButton = document.querySelector("#compareSnapshotsButton");
const restoreSearchInput = document.querySelector("#restoreSearchInput");
const restoreTypeFilter = document.querySelector("#restoreTypeFilter");
const snapshotPreview = document.querySelector("#snapshotPreview");
const restoreHistoryList = document.querySelector("#restoreHistoryList");
const incidentPrevPage = document.querySelector("#incidentPrevPage");
const incidentNextPage = document.querySelector("#incidentNextPage");
const incidentPageInfo = document.querySelector("#incidentPageInfo");
const restorePrevPage = document.querySelector("#restorePrevPage");
const restoreNextPage = document.querySelector("#restoreNextPage");
const restorePageInfo = document.querySelector("#restorePageInfo");
const auditScanMeta = document.querySelector("#auditScanMeta");
const adminKeyField = document.querySelector("#adminKeyField");
const adminKeyInput = document.querySelector("#adminKey");
const adminCodeField = document.querySelector("#adminCodeField");
const adminCodeInput = document.querySelector("#adminCode");
const loginButton = document.querySelector("#loginButton");
const logoutButton = document.querySelector("#logoutButton");
const template = document.querySelector("#productCardTemplate");
const lightbox = document.querySelector("#lightbox");
const lightboxImage = document.querySelector("#lightboxImage");
const lightboxThumbs = document.querySelector("#lightboxThumbs");
const lightboxClose = document.querySelector("#lightboxClose");
const lightboxPrev = document.querySelector("#lightboxPrev");
const lightboxNext = document.querySelector("#lightboxNext");

let activeLightboxImages = [];
let activeLightboxIndex = 0;
let activeLightboxAlt = "Product media preview";
let isAdminAuthenticated = false;
let isRefreshingAdminSession = false;
let selectedExchangeRequestId = null;
let incidentsPage = 1;
let restoresPage = 1;
let auditPage = 1;
let accountPage = 1;
let auditEntriesCache = [];
let productQueueCache = [];
let sellerDirectoryCache = [];
let pendingAdminChallengeId = "";

const currencyFormatter = new Intl.NumberFormat("en-US", {
  style: "currency",
  currency: "USD",
});

const dateTimeFormatter = new Intl.DateTimeFormat("en-US", {
  month: "short",
  day: "numeric",
  year: "numeric",
  hour: "numeric",
  minute: "2-digit",
});

function debounce(fn, ms) {
  let t;
  return (...args) => {
    clearTimeout(t);
    t = setTimeout(() => fn(...args), ms);
  };
}

function adminHeaders() {
  const headers = { "Content-Type": "application/json" };
  const adminKey = adminKeyInput.value.trim();
  if (adminKey) {
    headers["x-admin-key"] = adminKey;
  }
  return headers;
}

function setFeedback(message) {
  feedbackText.textContent = message;
}

function fallbackImageURL() {
  return "https://placehold.co/800x800/eaf2ff/5e84c7?text=No+media";
}

function resolveMediaURL(value) {
  const trimmed = String(value || "").trim();
  if (!trimmed) return null;
  if (trimmed.startsWith("/media/")) {
    return `${window.location.origin}${trimmed}`;
  }

  try {
    const url = new URL(trimmed);
    const host = url.hostname.toLowerCase();
    if ((host === "localhost" || host === "127.0.0.1") && url.pathname.startsWith("/media/")) {
      return `${window.location.origin}${url.pathname}${url.search}`;
    }
    if (url.protocol === "http:" || url.protocol === "https:") {
      return url.href;
    }
  } catch {
    // Fall through to the relative-url handling below.
  }

  if (!trimmed.startsWith("file:")) {
    try {
      return new URL(trimmed, window.location.origin).href;
    } catch {
      return null;
    }
  }

  return null;
}

function productImageURLs(product) {
  const urls = Array.isArray(product?.imageURLs)
    ? product.imageURLs.map(resolveMediaURL).filter(Boolean)
    : [];
  return urls.length ? urls : [fallbackImageURL()];
}

function renderLightbox() {
  if (!activeLightboxImages.length) return;

  lightboxImage.src = activeLightboxImages[activeLightboxIndex];
  lightboxImage.alt = activeLightboxAlt;
  lightboxThumbs.replaceChildren();

  activeLightboxImages.forEach((url, index) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "lightbox-thumbnail-button";
    if (index === activeLightboxIndex) {
      button.classList.add("is-selected");
    }

    const thumb = document.createElement("img");
    thumb.className = "lightbox-thumbnail-image";
    thumb.src = url;
    thumb.alt = `${activeLightboxAlt} ${index + 1}`;

    button.addEventListener("click", () => {
      activeLightboxIndex = index;
      renderLightbox();
    });

    button.appendChild(thumb);
    lightboxThumbs.appendChild(button);
  });

  const shouldShowNav = activeLightboxImages.length > 1;
  lightboxPrev.classList.toggle("hidden", !shouldShowNav);
  lightboxNext.classList.toggle("hidden", !shouldShowNav);
}

function openLightbox(images, index, alt) {
  activeLightboxImages = images;
  activeLightboxIndex = index;
  activeLightboxAlt = alt || "Product media preview";
  renderLightbox();
  lightbox.classList.remove("hidden");
}

function closeLightbox() {
  lightbox.classList.add("hidden");
  lightboxImage.src = "";
  lightboxImage.alt = "";
  lightboxThumbs.replaceChildren();
  activeLightboxImages = [];
  activeLightboxIndex = 0;
}

function showPreviousLightboxImage() {
  if (activeLightboxImages.length < 2) return;
  activeLightboxIndex =
    (activeLightboxIndex - 1 + activeLightboxImages.length) % activeLightboxImages.length;
  renderLightbox();
}

function showNextLightboxImage() {
  if (activeLightboxImages.length < 2) return;
  activeLightboxIndex = (activeLightboxIndex + 1) % activeLightboxImages.length;
  renderLightbox();
}

function selectedFilterLabel() {
  const selected = statusFilter.options[statusFilter.selectedIndex];
  const statusLabel = selected ? selected.textContent : "Submitted";
  const listingType = listingTypeFilter?.value || "";
  if (listingType === "weekly_drop") {
    return `${statusLabel} · Weekly Drop`;
  }
  if (listingType === "marketplace") {
    return `${statusLabel} · Marketplace`;
  }
  return statusLabel;
}

function isWeeklyDropProduct(product) {
  return product?.isDrop === true;
}

function hasRightsReviewData(product) {
  const flags = Array.isArray(product?.rightsReferenceFlags) ? product.rightsReferenceFlags : [];
  return Boolean(
    product?.requiresManualReview ||
    product?.reviewReason ||
    product?.rightsOwnershipType ||
    flags.length,
  );
}

function populateDetailField(element, label, value, fallback = "") {
  if (!element) return false;
  const trimmed = String(value || "").trim();
  if (!trimmed) {
    element.classList.add("hidden");
    element.textContent = "";
    return false;
  }
  element.classList.remove("hidden");
  element.textContent = label ? `${label}: ${trimmed}` : trimmed;
  return true;
}

function syncAdminKeyVisibility() {
  if (isAdminAuthenticated) {
    adminKeyField.classList.add("hidden");
    adminCodeField.classList.add("hidden");
    loginButton.classList.add("hidden");
    logoutButton.classList.remove("hidden");
  } else {
    adminKeyField.classList.toggle("hidden", Boolean(pendingAdminChallengeId));
    adminCodeField.classList.toggle("hidden", !pendingAdminChallengeId);
    loginButton.textContent = pendingAdminChallengeId ? "Verify code" : "Unlock admin";
    loginButton.classList.remove("hidden");
    logoutButton.classList.add("hidden");
  }
}

function productSellerId(product) {
  return String(product?.sellerId || "").trim() || "unknown-seller";
}

function productSellerDisplayName(product) {
  return String(product?.sellerDisplayName || product?.sellerId || "Unknown seller").trim();
}

function sellerFilterLabel(product) {
  const name = productSellerDisplayName(product);
  const sellerId = productSellerId(product);
  return name === sellerId ? name : `${name} (${sellerId})`;
}

function sellerDirectoryLabel(seller) {
  const name = String(seller?.displayName || seller?.id || "Unknown seller").trim();
  const sellerId = String(seller?.id || "unknown-seller").trim();
  return name === sellerId ? name : `${name} (${sellerId})`;
}

function updateSellerFilterOptions(products) {
  if (!sellerFilter) return;

  const selectedSellerId = sellerFilter.value;
  const sellersById = new Map();
  for (const seller of sellerDirectoryCache) {
    const sellerId = String(seller?.id || "").trim();
    if (sellerId) {
      sellersById.set(sellerId, sellerDirectoryLabel(seller));
    }
  }
  for (const product of products) {
    const sellerId = productSellerId(product);
    if (!sellersById.has(sellerId)) {
      sellersById.set(sellerId, sellerFilterLabel(product));
    }
  }

  sellerFilter.replaceChildren();
  const allOption = document.createElement("option");
  allOption.value = "";
  allOption.textContent = "All sellers";
  sellerFilter.appendChild(allOption);

  Array.from(sellersById.entries())
    .sort((lhs, rhs) => lhs[1].localeCompare(rhs[1]))
    .forEach(([sellerId, label]) => {
      const option = document.createElement("option");
      option.value = sellerId;
      option.textContent = label;
      sellerFilter.appendChild(option);
    });

  sellerFilter.value = sellersById.has(selectedSellerId) ? selectedSellerId : "";
}

function visibleQueueProducts(products) {
  const selectedSellerId = sellerFilter?.value || "";
  const selectedListingType = listingTypeFilter?.value || "";
  return products.filter((product) => {
    if (selectedSellerId && productSellerId(product) !== selectedSellerId) {
      return false;
    }
    if (selectedListingType === "weekly_drop" && !isWeeklyDropProduct(product)) {
      return false;
    }
    if (selectedListingType === "marketplace" && isWeeklyDropProduct(product)) {
      return false;
    }
    return true;
  });
}

function groupedProductsBySeller(products) {
  const groupsById = new Map();
  for (const product of products) {
    const sellerId = productSellerId(product);
    const group = groupsById.get(sellerId) || {
      sellerId,
      sellerDisplayName: productSellerDisplayName(product),
      products: [],
    };
    group.products.push(product);
    groupsById.set(sellerId, group);
  }
  return Array.from(groupsById.values()).sort((lhs, rhs) =>
    lhs.sellerDisplayName.localeCompare(rhs.sellerDisplayName),
  );
}

function updateSellerQueueSummary(visibleProducts, groups) {
  if (!sellerQueueSummary) return;

  const sellerWord = groups.length === 1 ? "seller" : "sellers";
  const productWord = visibleProducts.length === 1 ? "product" : "products";
  const dropCount = visibleProducts.filter((product) => isWeeklyDropProduct(product)).length;
  const dropSuffix = dropCount
    ? ` ${dropCount} Weekly Drop ${dropCount === 1 ? "item" : "items"}.`
    : "";
  sellerQueueSummary.textContent = visibleProducts.length
    ? `${visibleProducts.length} ${productWord} grouped under ${groups.length} ${sellerWord}.${dropSuffix}`
    : "No products match the current seller/status filters.";
}

function renderSellerDirectory(sellers) {
  if (!sellerDirectoryList || !sellerDirectoryCount) return;

  sellerDirectoryList.replaceChildren();
  sellerDirectoryCount.textContent = String(sellers.length);

  if (!sellers.length) {
    const empty = document.createElement("p");
    empty.className = "audit-empty";
    empty.textContent = "No seller accounts found yet.";
    sellerDirectoryList.appendChild(empty);
    return;
  }

  const selectedSellerId = sellerFilter?.value || "";
  for (const seller of sellers) {
    const sellerId = String(seller?.id || "").trim();
    const card = document.createElement("button");
    card.type = "button";
    card.className = "seller-directory-card";
    if (sellerId && sellerId === selectedSellerId) {
      card.classList.add("is-selected");
    }

    const name = document.createElement("p");
    name.className = "seller-directory-name";
    name.textContent = seller?.displayName || sellerId || "Unknown seller";

    const meta = document.createElement("p");
    meta.className = "seller-directory-meta";
    const handle = seller?.handle ? ` · ${seller.handle}` : "";
    const email = seller?.email ? ` · ${seller.email}` : "";
    meta.textContent = `Seller ID: ${sellerId}${handle}${email}`;

    const stats = document.createElement("div");
    stats.className = "seller-directory-stats";
    const counts = seller?.productCounts || {};
    [
      `${seller?.totalProducts || 0} total`,
      `${counts.submitted || 0} submitted`,
      `${counts.approved || 0} approved`,
      `${currencyFormatter.format((Number(seller?.totalValueCents) || 0) / 100)} value`,
    ].forEach((text) => {
      const pill = document.createElement("span");
      pill.className = "seller-stat-pill";
      pill.textContent = text;
      stats.appendChild(pill);
    });

    card.append(name, meta, stats);
    card.addEventListener("click", () => {
      if (!sellerFilter || !sellerId) return;
      sellerFilter.value = sellerFilter.value === sellerId ? "" : sellerId;
      renderSellerDirectory(sellerDirectoryCache);
      renderQueue(productQueueCache);
    });
    sellerDirectoryList.appendChild(card);
  }
}

function accountKind() {
  return accountKindFilter?.value === "buyers" ? "buyers" : "sellers";
}

function accountPageSize() {
  return Math.max(5, Math.min(50, Number(accountPageSizeSelect?.value) || 12));
}

function accountQueryString() {
  const params = new URLSearchParams();
  params.set("kind", accountKind());
  params.set("page", String(accountPage));
  params.set("pageSize", String(accountPageSize()));
  const q = accountSearchInput?.value?.trim() || "";
  if (q) params.set("q", q);
  return params.toString();
}

function activityTotal(activity = {}) {
  return Object.entries(activity)
    .filter(([, value]) => typeof value === "number")
    .reduce((sum, [, value]) => sum + value, 0);
}

function formatAgreementTimestamp(value) {
  if (!value) return "";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  return date.toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" });
}

function sellerShippingOriginLabel(shippingOrigin = {}) {
  const country = String(shippingOrigin.country || "").trim();
  const state = String(shippingOrigin.state || "").trim();
  if (country && state) return `${country}, ${state}`;
  return country || state || "";
}

function buildSellerComplianceSection(account) {
  const section = document.createElement("div");
  section.className = "account-compliance";

  const title = document.createElement("p");
  title.className = "account-compliance-title";
  title.textContent = "Seller onboarding compliance";

  const pills = document.createElement("div");
  pills.className = "account-compliance-pills";

  const agreementAccepted = account.sellerAgreement?.accepted === true;
  const agreementPill = document.createElement("span");
  agreementPill.className = agreementAccepted ? "compliance-pill is-ok" : "compliance-pill is-missing";
  const agreementWhen = formatAgreementTimestamp(account.sellerAgreement?.acceptedAt);
  agreementPill.textContent = agreementAccepted
    ? `Seller agreement agreed${agreementWhen ? ` · ${agreementWhen}` : ""}`
    : "Seller agreement not accepted";

  const policiesAcknowledged = account.sellerPoliciesAcknowledged === true;
  const policiesPill = document.createElement("span");
  policiesPill.className = policiesAcknowledged ? "compliance-pill is-ok" : "compliance-pill is-missing";
  policiesPill.textContent = policiesAcknowledged
    ? "Seller policies acknowledged"
    : "Seller policies not acknowledged";

  pills.append(agreementPill, policiesPill);

  const details = document.createElement("p");
  details.className = "account-card-meta";
  const detailParts = [];
  if (account.legalName) detailParts.push(`Legal name: ${account.legalName}`);
  const origin = sellerShippingOriginLabel(account.shippingOrigin);
  if (origin) detailParts.push(`Shipping origin: ${origin}`);
  if (account.sellerAgreement?.version) {
    detailParts.push(`Agreement version: ${account.sellerAgreement.version}`);
  }
  details.textContent = detailParts.length ? detailParts.join(" · ") : "No onboarding compliance details recorded yet.";

  section.append(title, pills, details);
  return section;
}

function renderAccounts(payload) {
  if (!accountList || !accountTotalCount || !accountPageInfo || !accountPrevPage || !accountNextPage) return;

  const accounts = Array.isArray(payload?.accounts) ? payload.accounts : [];
  const total = Number(payload?.total) || 0;
  const page = Number(payload?.page) || 1;
  const pages = Math.max(1, Number(payload?.pages) || 1);
  const kindLabel = accountKind() === "buyers" ? "buyer" : "seller";

  accountList.replaceChildren();
  accountTotalCount.textContent = String(total);
  accountPageInfo.textContent = total ? `Page ${page} of ${pages} (${total} ${kindLabel} accounts)` : `No ${kindLabel} accounts`;
  accountPrevPage.disabled = page <= 1;
  accountNextPage.disabled = page >= pages || total === 0;

  if (!accounts.length) {
    const empty = document.createElement("p");
    empty.className = "audit-empty";
    empty.textContent = `No ${kindLabel} accounts match these filters.`;
    accountList.appendChild(empty);
    return;
  }

  for (const account of accounts) {
    const card = document.createElement("article");
    card.className = "account-card";

    const header = document.createElement("div");
    header.className = "account-card-header";
    const titleWrap = document.createElement("div");
    const title = document.createElement("h3");
    title.className = "account-card-title";
    title.textContent = account.displayName || account.id || "Account";
    const meta = document.createElement("p");
    meta.className = "account-card-meta";
    const handle = account.handle ? ` · ${account.handle}` : "";
    const email = account.email ? ` · ${account.email}` : "";
    meta.textContent = `${account.kind || kindLabel} ID: ${account.id}${handle}${email}`;
    titleWrap.append(title, meta);

    const status = document.createElement("span");
    const linkedActivity = activityTotal(account.activity || {});
    status.className = linkedActivity > 0 ? "account-status" : "account-status is-inactive";
    status.textContent = linkedActivity > 0 ? "Has activity" : "Inactive";
    header.append(titleWrap, status);

    const stats = document.createElement("div");
    stats.className = "account-stat-grid";
    const activity = account.activity || {};
    const statEntries = account.kind === "buyer"
      ? [
          ["Orders", activity.orderCount || 0],
          ["Exchanges", activity.exchangeCount || 0],
          ["Requests", activity.customOrderCount || 0],
          ["Reviews", activity.reviewCount || 0],
        ]
      : [
          ["Products", activity.productCount || 0],
          ["Orders", activity.orderCount || 0],
          ["Exchanges", activity.exchangeCount || 0],
          ["Requests", activity.customOrderCount || 0],
          ["Reviews", activity.reviewCount || 0],
        ];
    statEntries.forEach(([label, value]) => {
      const stat = document.createElement("span");
      stat.className = "seller-stat-pill";
      stat.textContent = `${label}: ${value}`;
      stats.appendChild(stat);
    });

    const footer = document.createElement("div");
    footer.className = "account-card-footer";
    const note = document.createElement("p");
    note.className = "account-card-meta";
    const productCount = Number(account.activity?.productCount) || 0;
    note.textContent = linkedActivity > 0
      ? account.kind === "seller" && productCount > 0
        ? `Delete is available. ${productCount} linked product${productCount === 1 ? "" : "s"} will be removed from the app; other history may remain for audit.`
        : `Delete is available. Linked activity remains in records: ${account.activity?.blockers?.join(", ") || `${linkedActivity} activity records`}.`
      : "No activity found. This account can be permanently deleted.";

    const deleteButton = document.createElement("button");
    deleteButton.type = "button";
    deleteButton.className = "danger-button";
    deleteButton.textContent = "Delete account";
    deleteButton.addEventListener("click", () => deleteAccount(account));
    footer.append(note, deleteButton);

    if (account.kind === "seller") {
      card.append(header, buildSellerComplianceSection(account), stats, footer);
    } else {
      card.append(header, stats, footer);
    }
    accountList.appendChild(card);
  }
}

async function loadAccounts() {
  if (!isAdminAuthenticated) {
    renderAccounts({ accounts: [], total: 0, page: 1, pages: 1 });
    return;
  }

  try {
    setFeedback("Loading accounts...");
    const response = await fetch(`/admin/accounts?${accountQueryString()}`, {
      headers: adminHeaders(),
    });
    if (!response.ok) {
      throw new Error(await response.text());
    }
    const payload = await response.json();
    renderAccounts(payload);
    setFeedback("Accounts ready");
  } catch (error) {
    renderAccounts({ accounts: [], total: 0, page: 1, pages: 1 });
    setFeedback("Failed to load accounts");
    console.error(error);
  }
}

function customRequestQueryString() {
  const params = new URLSearchParams();
  const status = customRequestStatusFilter?.value || "";
  const q = customRequestSearchInput?.value?.trim() || "";
  if (status) params.set("status", status);
  if (q) params.set("q", q);
  return params.toString();
}

function customRequestStatusLabel(status) {
  const normalized = String(status || "pending").trim().toLowerCase();
  if (normalized === "accepted") return "Accepted";
  if (normalized === "declined") return "Declined";
  return "Pending";
}

function absoluteMediaURL(url) {
  const value = String(url || "").trim();
  if (!value) return "";
  if (/^https?:\/\//i.test(value)) return value;
  return `${window.location.origin}${value.startsWith("/") ? value : `/${value}`}`;
}

function renderCustomRequests(requests) {
  if (!customRequestList || !customRequestCount || !customRequestEmpty) return;

  customRequestList.replaceChildren();
  customRequestCount.textContent = String(requests.length);

  if (!requests.length) {
    customRequestEmpty.classList.remove("hidden");
    return;
  }

  customRequestEmpty.classList.add("hidden");

  for (const request of requests) {
    const card = document.createElement("article");
    card.className = "custom-request-card";

    const header = document.createElement("div");
    header.className = "custom-request-header";

    const titleWrap = document.createElement("div");
    const title = document.createElement("h3");
    title.className = "custom-request-title";
    title.textContent = request.buyerName || request.buyerEmail || "Buyer request";
    const meta = document.createElement("p");
    meta.className = "custom-request-meta";
    meta.textContent = [
      request.buyerEmail ? `Buyer: ${request.buyerEmail}` : "",
      request.sellerDisplayName ? `Seller: ${request.sellerDisplayName}` : `Seller ID: ${request.sellerId || "—"}`,
      request.createdAt ? `Sent ${formatDateTime(request.createdAt)}` : "",
    ].filter(Boolean).join(" · ");
    titleWrap.append(title, meta);

    const status = document.createElement("span");
    const normalizedStatus = String(request.status || "pending").trim().toLowerCase();
    status.className = `custom-request-status status-${normalizedStatus}`;
    status.textContent = customRequestStatusLabel(normalizedStatus);
    header.append(titleWrap, status);

    const sellerMeta = document.createElement("p");
    sellerMeta.className = "custom-request-meta";
    const sellerParts = [];
    if (request.sellerId) sellerParts.push(`Seller ID: ${request.sellerId}`);
    if (request.sellerHandle) sellerParts.push(`Handle: ${request.sellerHandle}`);
    if (request.sellerEmail) sellerParts.push(`Seller email: ${request.sellerEmail}`);
    if (request.statusUpdatedAt) sellerParts.push(`Updated ${formatDateTime(request.statusUpdatedAt)}`);
    sellerMeta.textContent = sellerParts.join(" · ") || "No seller details recorded.";

    const description = document.createElement("p");
    description.className = "custom-request-description";
    description.textContent = request.description || "No request description submitted.";

    card.append(header, sellerMeta, description);

    const references = Array.isArray(request.referenceImageURLs) ? request.referenceImageURLs : [];
    if (references.length) {
      const referenceWrap = document.createElement("div");
      referenceWrap.className = "custom-request-references";
      for (const referenceURL of references) {
        const absoluteURL = absoluteMediaURL(referenceURL);
        const link = document.createElement("a");
        link.className = "custom-request-thumb";
        link.href = absoluteURL;
        link.target = "_blank";
        link.rel = "noreferrer";
        const img = document.createElement("img");
        img.src = absoluteURL;
        img.alt = "Custom request reference";
        link.appendChild(img);
        referenceWrap.appendChild(link);
      }
      card.appendChild(referenceWrap);
    }

    const auditMeta = document.createElement("p");
    auditMeta.className = "custom-request-meta";
    auditMeta.textContent = [
      request.id ? `Request ID: ${request.id}` : "",
      request.clientIp ? `IP: ${request.clientIp}` : "",
    ].filter(Boolean).join(" · ");
    card.appendChild(auditMeta);

    customRequestList.appendChild(card);
  }
}

async function loadCustomRequests() {
  if (!isAdminAuthenticated) {
    renderCustomRequests([]);
    return;
  }

  try {
    setFeedback("Loading custom requests...");
    const query = customRequestQueryString();
    const response = await fetch(`/admin/custom-order-requests${query ? `?${query}` : ""}`, {
      headers: adminHeaders(),
    });
    if (!response.ok) {
      throw new Error(await response.text());
    }
    const payload = await response.json();
    renderCustomRequests(Array.isArray(payload.requests) ? payload.requests : []);
    setFeedback("Custom requests ready");
  } catch (error) {
    renderCustomRequests([]);
    setFeedback("Failed to load custom requests");
    console.error(error);
  }
}

async function deleteAccount(account) {
  const kind = account.kind === "buyer" ? "buyers" : "sellers";
  const label = account.displayName || account.id;
  const linkedActivity = activityTotal(account.activity || {});
  const productCount = Number(account.activity?.productCount) || 0;
  let activityWarning = "";
  if (linkedActivity > 0) {
    activityWarning = account.kind === "seller" && productCount > 0
      ? `\n\nThis seller has ${productCount} linked product${productCount === 1 ? "" : "s"}. The seller account and those products will be removed from the app. Other linked history may remain for audit.`
      : `\n\nThis account has linked activity (${account.activity?.blockers?.join(", ") || `${linkedActivity} records`}). The account will be removed, but those records may remain for history/audit.`;
  }
  const confirmed = window.confirm(`Permanently delete ${label}? This cannot be undone.${activityWarning}`);
  if (!confirmed) return;

  try {
    setFeedback("Deleting account...");
    const response = await fetch(`/admin/accounts/${encodeURIComponent(kind)}/${encodeURIComponent(account.id)}`, {
      method: "DELETE",
      headers: adminHeaders(),
    });
    if (!response.ok) {
      let message = await response.text();
      try {
        const parsed = JSON.parse(message);
        message = parsed.blockers?.length
          ? `${parsed.error} Blocked by: ${parsed.blockers.join(", ")}`
          : parsed.error || message;
      } catch {
        // Use raw message.
      }
      throw new Error(message);
    }
    setFeedback("Account deleted");
    await Promise.all([loadAccounts(), loadSellerDirectory(), loadQueue(false)]);
  } catch (error) {
    setFeedback(error.message || "Account delete failed");
    console.error(error);
  }
}

function buildProductCard(product) {
  const fragment = template.content.cloneNode(true);
  const image = fragment.querySelector(".product-image");
  const mediaCount = fragment.querySelector(".media-count");
  const thumbnails = fragment.querySelector(".media-thumbnails");
  const sellerName = fragment.querySelector(".seller-name");
  const productName = fragment.querySelector(".product-name");
  const statusPill = fragment.querySelector(".status-pill");
  const productPrice = fragment.querySelector(".product-price");
  const productCategory = fragment.querySelector(".product-category");
  const productMaterial = fragment.querySelector(".product-material");
  const productSubmitted = fragment.querySelector(".product-submitted");
  const productNote = fragment.querySelector(".product-note");
  const mediaPill = fragment.querySelector(".media-pill");
  const dropDetailBlock = fragment.querySelector(".drop-detail-block");
  const dropHeadline = fragment.querySelector(".drop-headline");
  const dropStory = fragment.querySelector(".drop-story");
  const dropBestUseCase = fragment.querySelector(".drop-best-use-case");
  const rightsReviewBlock = fragment.querySelector(".rights-review-block");
  const rightsManualReviewFlag = fragment.querySelector(".rights-manual-review-flag");
  const rightsReviewReason = fragment.querySelector(".rights-review-reason");
  const rightsOwnershipType = fragment.querySelector(".rights-ownership-type");
  const rightsReferenceFlags = fragment.querySelector(".rights-reference-flags");
  const notesField = fragment.querySelector("textarea");
  const approveButton = fragment.querySelector(".approve-button");
  const rejectButton = fragment.querySelector(".reject-button");
  const archiveButton = fragment.querySelector(".archive-button");

  const imageURLs = productImageURLs(product);

  let selectedImageIndex = 0;
  image.src = imageURLs[selectedImageIndex];
  image.alt = product.name || "Product media";

  if (imageURLs.length > 1) {
    mediaCount.textContent = `${imageURLs.length} photos`;
    mediaCount.classList.remove("hidden");
  } else {
    mediaCount.classList.add("hidden");
  }

  imageURLs.forEach((url, index) => {
    const thumbnailButton = document.createElement("button");
    thumbnailButton.type = "button";
    thumbnailButton.className = "thumbnail-button";
    if (index === 0) {
      thumbnailButton.classList.add("is-selected");
    }

    const thumbnailImage = document.createElement("img");
    thumbnailImage.className = "thumbnail-image";
    thumbnailImage.src = url;
    thumbnailImage.alt = `${product.name || "Product"} image ${index + 1}`;

    thumbnailButton.addEventListener("click", () => {
      selectedImageIndex = index;
      image.src = url;
      image.alt = product.name || "Product media";
      thumbnails.querySelectorAll(".thumbnail-button").forEach((button) => {
        button.classList.remove("is-selected");
      });
      thumbnailButton.classList.add("is-selected");
    });

    thumbnailButton.appendChild(thumbnailImage);
    thumbnails.appendChild(thumbnailButton);
  });

  image.addEventListener("click", () => openLightbox(imageURLs, selectedImageIndex, image.alt));

  sellerName.textContent = `Seller ID: ${productSellerId(product)}`;
  productName.textContent = product.name || "Untitled product";

  const status = String(product.approvalStatus || "submitted").trim().toLowerCase();
  statusPill.textContent =
    status === "approved"
      ? "Approved"
      : status === "rejected"
        ? "Rejected"
        : status === "archived"
          ? "Archived"
          : "Submitted";
  statusPill.classList.add(`status-${status}`);

  productPrice.textContent = currencyFormatter.format((Number(product.priceCents || 0) / 100));
  productCategory.textContent = product.category || "Desk";
  productMaterial.textContent = product.material || "PLA+";
  productSubmitted.textContent = product.submittedAt
    ? dateTimeFormatter.format(new Date(product.submittedAt))
    : "Just now";

  const isDrop = isWeeklyDropProduct(product);
  if (mediaPill) {
    mediaPill.textContent = isDrop ? "Weekly Drop" : "Marketplace review";
    mediaPill.classList.toggle("is-weekly-drop", isDrop);
  }

  if (dropDetailBlock) {
    if (isDrop) {
      dropDetailBlock.classList.remove("hidden");
      const hasHeadline = populateDetailField(dropHeadline, "Headline", product.dropHeadline);
      const hasStory = populateDetailField(dropStory, "Story", product.dropStory);
      const hasBestUseCase = populateDetailField(dropBestUseCase, "Best use", product.dropBestUseCase);
      if (!hasHeadline && !hasStory && !hasBestUseCase) {
        dropHeadline?.classList.remove("hidden");
        if (dropHeadline) {
          dropHeadline.textContent = "No Weekly Drop copy provided.";
        }
      }
    } else {
      dropDetailBlock.classList.add("hidden");
    }
  }

  if (rightsReviewBlock) {
    if (hasRightsReviewData(product)) {
      rightsReviewBlock.classList.remove("hidden");
      rightsManualReviewFlag?.classList.toggle("hidden", !product.requiresManualReview);
      populateDetailField(rightsReviewReason, "Review reason", product.reviewReason);
      populateDetailField(rightsOwnershipType, "Ownership", product.rightsOwnershipType);

      const flags = Array.isArray(product.rightsReferenceFlags)
        ? product.rightsReferenceFlags.filter((flag) => String(flag || "").trim())
        : [];
      if (rightsReferenceFlags) {
        rightsReferenceFlags.replaceChildren();
        if (flags.length) {
          rightsReferenceFlags.classList.remove("hidden");
          for (const flag of flags) {
            const item = document.createElement("li");
            item.textContent = flag;
            rightsReferenceFlags.appendChild(item);
          }
        } else {
          rightsReferenceFlags.classList.add("hidden");
        }
      }
    } else {
      rightsReviewBlock.classList.add("hidden");
    }
  }

  productNote.textContent = product.durabilityNote || "No durability note provided.";
  notesField.value = product.reviewNotes || "";

  if (status === "archived") {
    approveButton.classList.add("hidden");
    rejectButton.classList.add("hidden");
    archiveButton.classList.add("hidden");
    notesField.readOnly = true;
  } else {
    approveButton.addEventListener("click", () =>
      reviewProduct(product.id, "approve", notesField.value, approveButton, rejectButton, archiveButton),
    );
    rejectButton.addEventListener("click", () =>
      reviewProduct(product.id, "reject", notesField.value, approveButton, rejectButton, archiveButton),
    );
    archiveButton.addEventListener("click", () =>
      archiveProduct(product.id, notesField.value, approveButton, rejectButton, archiveButton),
    );
  }

  return fragment;
}

function renderQueue(products) {
  queueGrid.replaceChildren();
  updateSellerFilterOptions(products);
  const visibleProducts = visibleQueueProducts(products);
  const sellerGroups = groupedProductsBySeller(visibleProducts);
  queueCount.textContent = String(visibleProducts.length);
  queueFilterLabel.textContent = selectedFilterLabel();
  updateSellerQueueSummary(visibleProducts, sellerGroups);

  if (!visibleProducts.length) {
    emptyState.classList.remove("hidden");
    return;
  }

  emptyState.classList.add("hidden");

  for (const group of sellerGroups) {
    const sellerSection = document.createElement("section");
    sellerSection.className = "seller-product-group";

    const totalCents = group.products.reduce(
      (sum, product) => sum + (Number(product.priceCents) || 0),
      0,
    );
    const latestSubmittedAt = group.products.reduce((latest, product) => {
      const submittedAt = new Date(product.submittedAt || 0).getTime();
      return Math.max(latest, Number.isFinite(submittedAt) ? submittedAt : 0);
    }, 0);

    const header = document.createElement("div");
    header.className = "seller-product-group-header";
    const sellerTitleWrap = document.createElement("div");
    const sellerTitle = document.createElement("h2");
    sellerTitle.className = "seller-product-group-title";
    sellerTitle.textContent = group.sellerDisplayName;
    const sellerId = document.createElement("p");
    sellerId.className = "seller-product-group-id";
    sellerId.textContent = `Seller ID: ${group.sellerId}`;
    sellerTitleWrap.append(sellerTitle, sellerId);

    const stats = document.createElement("div");
    stats.className = "seller-product-group-stats";
    [
      `${group.products.length} product${group.products.length === 1 ? "" : "s"}`,
      `${currencyFormatter.format(totalCents / 100)} total`,
      `Latest ${latestSubmittedAt ? dateTimeFormatter.format(new Date(latestSubmittedAt)) : "unknown"}`,
    ].forEach((text) => {
      const pill = document.createElement("span");
      pill.className = "seller-stat-pill";
      pill.textContent = text;
      stats.appendChild(pill);
    });
    header.append(sellerTitleWrap, stats);

    const productList = document.createElement("div");
    productList.className = "seller-product-list";
    for (const product of group.products) {
      productList.appendChild(buildProductCard(product));
    }

    sellerSection.append(header, productList);
    queueGrid.appendChild(sellerSection);
  }
}

function renderExchangeQueue(exchangeRequests) {
  exchangeQueueList.replaceChildren();
  exchangeQueueCount.textContent = String(exchangeRequests.length);

  if (!exchangeRequests.length) {
    exchangeQueueEmpty.classList.remove("hidden");
    exchangeDetailPanel.innerHTML = '<p class="audit-empty">No exchange request selected.</p>';
    return;
  }

  exchangeQueueEmpty.classList.add("hidden");

  for (const request of exchangeRequests) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "exchange-queue-card";
    if (selectedExchangeRequestId === request.id) {
      button.classList.add("is-selected");
    }

    const proofCount = Array.isArray(request.buyerProofAssets) ? request.buyerProofAssets.length : 0;
    button.innerHTML = `
      <div class="exchange-queue-top">
        <span class="status-pill">${String(request.status || "submitted").replaceAll("_", " ")}</span>
        <span class="exchange-queue-date">${formatDateTime(request.submittedDate || request.updatedAt || request.createdAt)}</span>
      </div>
      <strong>${request.product || request.productTitle || "Exchange request"}</strong>
      <p class="exchange-queue-meta">Order ${request.orderId || request.orderNumber || "—"} · ${request.buyer || "Buyer unavailable"}</p>
      <p class="exchange-queue-meta">Proof assets: ${proofCount} · Reason: ${String(request.reasonCode || "other").replaceAll("_", " ")}</p>
    `;
    button.addEventListener("click", () => {
      selectedExchangeRequestId = request.id;
      void loadExchangeDetail(request.id);
      renderExchangeQueue(exchangeRequests);
    });
    exchangeQueueList.appendChild(button);
  }
}

function renderExchangeDetail(payload) {
  if (!payload?.exchangeRequest) {
    exchangeDetailPanel.innerHTML = '<p class="audit-empty">No exchange request selected.</p>';
    return;
  }

  const request = payload.exchangeRequest;
  const proofAssets = Array.isArray(request.buyerProofAssets) ? request.buyerProofAssets : [];
  const timeline = Array.isArray(request.timelineEvents) ? request.timelineEvents : [];
  const proofMarkup = proofAssets.length
    ? proofAssets
        .map((asset) => {
          if (asset.type === "image" && asset.url) {
            return `<a class="exchange-proof-thumb" href="${asset.url}" target="_blank" rel="noreferrer"><img src="${asset.url}" alt="Exchange proof" /></a>`;
          }
          return `<div class="exchange-proof-thumb exchange-proof-thumb-video"><span>Video</span></div>`;
        })
        .join("")
    : '<p class="audit-empty">No proof uploaded.</p>';

  const timelineMarkup = timeline.length
    ? timeline
        .slice()
        .sort((lhs, rhs) => new Date(rhs.createdAt).getTime() - new Date(lhs.createdAt).getTime())
        .map(
          (event) => `
            <div class="exchange-timeline-row">
              <strong>${event.message || "Timeline event"}</strong>
              <span>${formatDateTime(event.createdAt)}</span>
            </div>
          `
        )
        .join("")
    : '<p class="audit-empty">No timeline events yet.</p>';

  exchangeDetailPanel.innerHTML = `
    <div class="exchange-detail-header">
      <span class="status-pill">${String(request.status || "submitted").replaceAll("_", " ")}</span>
      <strong>${request.productTitle || payload.orderItem?.productName || "Exchange request"}</strong>
      <p>Order ${request.orderId} · Item ${request.orderItemId}</p>
    </div>
    <div class="exchange-detail-group">
      <span class="summary-label">Buyer explanation</span>
      <p>${request.buyerExplanation || "No buyer explanation submitted."}</p>
    </div>
    <div class="exchange-detail-group">
      <span class="summary-label">Eligibility</span>
      <p>${request.eligibleAtSubmission ? "Eligible at submission" : "Submission had eligibility issues"}${request.eligibilityFailureReason ? ` · ${request.eligibilityFailureReason}` : ""}</p>
    </div>
    <div class="exchange-detail-group">
      <span class="summary-label">Proof</span>
      <div class="exchange-proof-grid">${proofMarkup}</div>
    </div>
    <div class="exchange-detail-group">
      <span class="summary-label">Timeline</span>
      <div class="exchange-timeline-list">${timelineMarkup}</div>
    </div>
  `;
}

function formatDateTime(value) {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  return dateTimeFormatter.format(date);
}

async function loadExchangeQueue() {
  if (!isAdminAuthenticated) {
    renderExchangeQueue([]);
    renderExchangeDetail(null);
    return;
  }

  try {
    const status = exchangeStatusFilter?.value || "";
    const query = status ? `?status=${encodeURIComponent(status)}` : "";
    const response = await fetch(`/admin/exchange-requests${query}`, {
      headers: adminHeaders(),
    });
    if (!response.ok) {
      throw new Error(await response.text());
    }
    const payload = await response.json();
    const exchangeRequests = Array.isArray(payload.exchangeRequests) ? payload.exchangeRequests : [];
    if (!selectedExchangeRequestId && exchangeRequests.length) {
      selectedExchangeRequestId = exchangeRequests[0].id;
    }
    renderExchangeQueue(exchangeRequests);
    if (selectedExchangeRequestId) {
      await loadExchangeDetail(selectedExchangeRequestId);
    } else {
      renderExchangeDetail(null);
    }
  } catch (error) {
    renderExchangeQueue([]);
    renderExchangeDetail(null);
    console.error(error);
  }
}

async function loadExchangeDetail(exchangeRequestId) {
  if (!exchangeRequestId || !isAdminAuthenticated) {
    renderExchangeDetail(null);
    return;
  }

  try {
    const response = await fetch(`/admin/exchange-requests/${encodeURIComponent(exchangeRequestId)}`, {
      headers: adminHeaders(),
    });
    if (!response.ok) {
      throw new Error(await response.text());
    }
    const payload = await response.json();
    renderExchangeDetail(payload);
  } catch (error) {
    exchangeDetailPanel.innerHTML = '<p class="audit-empty">Unable to load this exchange request.</p>';
    console.error(error);
  }
}

function auditEntryFields(entry) {
  return {
    ts: entry?.ts ? dateTimeFormatter.format(new Date(entry.ts)) : "Unknown time",
    action: entry?.action || "unknown_action",
    requestId: entry?.requestId || "n/a",
    method: entry?.method || "-",
    route: entry?.path || "-",
    ip: entry?.ip || "-",
  };
}

function auditEntryMatchesQuery(entry, query) {
  if (!query) {
    return true;
  }
  const haystack = [
    entry?.action,
    entry?.requestId,
    entry?.method,
    entry?.path,
    entry?.ip,
  ]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();
  return haystack.includes(query.toLowerCase());
}

function filteredAuditEntries() {
  const query = auditSearchInput?.value?.trim() || "";
  return auditEntriesCache.filter((entry) => auditEntryMatchesQuery(entry, query));
}

function auditPageSize() {
  return Math.max(5, Math.min(50, Number(auditPageSizeSelect?.value) || 20));
}

function updateAuditPaginationUI(total, page, pageSize) {
  if (!auditPageInfo || !auditPrevPage || !auditNextPage) {
    return;
  }
  const pages = Math.max(1, Math.ceil(total / pageSize) || 1);
  auditPageInfo.textContent = total
    ? `Page ${page} of ${pages} (${total} events)`
    : auditSearchInput?.value?.trim()
      ? "No matching events"
      : "No audit events";
  auditPrevPage.disabled = page <= 1 || total === 0;
  auditNextPage.disabled = page >= pages || total === 0;
}

function appendAuditDetailLine(container, label, value) {
  const line = document.createElement("div");
  line.className = "audit-detail";
  line.textContent = `${label}: ${value}`;
  container.appendChild(line);
}

function createAuditRow(entry) {
  const { ts, action, requestId, method, route, ip } = auditEntryFields(entry);
  const row = document.createElement("button");
  row.type = "button";
  row.className = "audit-row";
  row.setAttribute("aria-expanded", "false");

  const meta = document.createElement("div");
  meta.className = "audit-meta";

  const tsEl = document.createElement("span");
  tsEl.className = "audit-ts";
  tsEl.textContent = ts;

  const actionEl = document.createElement("span");
  actionEl.className = "audit-action";
  actionEl.textContent = action;

  const chevron = document.createElement("span");
  chevron.className = "audit-row-chevron";
  chevron.setAttribute("aria-hidden", "true");
  chevron.textContent = "▸";

  meta.append(tsEl, actionEl, chevron);

  const details = document.createElement("div");
  details.className = "audit-row-details";
  details.hidden = true;
  appendAuditDetailLine(details, "req", requestId);
  appendAuditDetailLine(details, "route", `${method} ${route}`);
  appendAuditDetailLine(details, "ip", ip);

  row.append(meta, details);
  row.addEventListener("click", () => {
    const expanded = row.getAttribute("aria-expanded") === "true";
    row.setAttribute("aria-expanded", expanded ? "false" : "true");
    row.classList.toggle("is-expanded", !expanded);
    details.hidden = expanded;
  });

  return row;
}

function renderAuditPage() {
  if (!auditLogList) {
    return;
  }

  auditLogList.replaceChildren();
  const filtered = filteredAuditEntries();
  const pageSize = auditPageSize();
  const total = filtered.length;
  const pages = Math.max(1, Math.ceil(total / pageSize) || 1);
  if (auditPage > pages) {
    auditPage = pages;
  }
  if (auditPage < 1) {
    auditPage = 1;
  }

  if (!total) {
    const empty = document.createElement("p");
    empty.className = "audit-empty";
    empty.textContent = auditSearchInput?.value?.trim()
      ? "No audit events match your search."
      : "No audit events yet.";
    auditLogList.appendChild(empty);
    updateAuditPaginationUI(0, 1, pageSize);
    return;
  }

  const start = (auditPage - 1) * pageSize;
  for (const entry of filtered.slice(start, start + pageSize)) {
    auditLogList.appendChild(createAuditRow(entry));
  }
  updateAuditPaginationUI(total, auditPage, pageSize);
}

function renderAuditEntries(entries) {
  auditEntriesCache = Array.isArray(entries) ? entries : [];
  auditPage = 1;
  renderAuditPage();
}

function pickTopCountKey(record) {
  if (!record || typeof record !== "object") return "-";
  const entries = Object.entries(record);
  if (!entries.length) return "-";
  entries.sort((lhs, rhs) => rhs[1] - lhs[1]);
  return entries[0][0];
}

function renderSecurityMetrics(metrics) {
  if (!metrics) {
    metricAuthFailures.textContent = "0";
    metricOwnershipMismatches.textContent = "0";
    metricTopScope.textContent = "-";
    return;
  }

  const byAction = metrics.countsByAction || {};
  const authFailures =
    Number(byAction.admin_auth_failed || 0) +
    Number(byAction.app_client_auth_failed || 0) +
    Number(byAction.user_session_missing_or_invalid || 0) +
    Number(byAction.buyer_session_missing_or_invalid || 0) +
    Number(byAction.seller_session_missing_or_invalid || 0) +
    Number(byAction.admin_login_failed || 0);

  metricAuthFailures.textContent = String(authFailures);
  metricOwnershipMismatches.textContent = String(byAction.ownership_mismatch || 0);
  metricTopScope.textContent = pickTopCountKey(metrics.countsByScope);
}

function incidentHistoryQueryString() {
  const params = new URLSearchParams();
  params.set("incidentsPage", String(incidentsPage));
  params.set("incidentsPageSize", "20");
  params.set("restoresPage", String(restoresPage));
  params.set("restoresPageSize", "20");
  const iq = incidentSearchInput.value.trim();
  if (iq) params.set("incidentsQ", iq);
  const st = incidentStateFilter.value.trim();
  if (st) params.set("incidentsState", st);
  const rq = restoreSearchInput.value.trim();
  if (rq) params.set("restoresQ", rq);
  const ra = restoreTypeFilter.value.trim();
  if (ra) params.set("restoresAction", ra);
  return params.toString();
}

function updateIncidentPaginationUI(payload) {
  if (!incidentPageInfo || !incidentPrevPage || !incidentNextPage) return;
  const total = Number(payload?.incidentsTotal) || 0;
  const page = Number(payload?.incidentsPage) || 1;
  const size = Number(payload?.incidentsPageSize) || 20;
  const pages = Math.max(1, Math.ceil(total / size) || 1);
  incidentPageInfo.textContent = total ? `Page ${page} of ${pages} (${total} incidents)` : "No incidents";
  incidentPrevPage.disabled = page <= 1;
  incidentNextPage.disabled = page >= pages || total === 0;
}

function updateRestorePaginationUI(payload) {
  if (!restorePageInfo || !restorePrevPage || !restoreNextPage) return;
  const total = Number(payload?.restoresTotal) || 0;
  const page = Number(payload?.restoresPage) || 1;
  const size = Number(payload?.restoresPageSize) || 20;
  const pages = Math.max(1, Math.ceil(total / size) || 1);
  restorePageInfo.textContent = total ? `Page ${page} of ${pages} (${total} restores)` : "No restore activity";
  restorePrevPage.disabled = page <= 1;
  restoreNextPage.disabled = page >= pages || total === 0;
}

function resetIncidentHistoryPaginationUI() {
  if (incidentPageInfo) incidentPageInfo.textContent = "";
  if (incidentPrevPage) incidentPrevPage.disabled = true;
  if (incidentNextPage) incidentNextPage.disabled = true;
  if (restorePageInfo) restorePageInfo.textContent = "";
  if (restorePrevPage) restorePrevPage.disabled = true;
  if (restoreNextPage) restoreNextPage.disabled = true;
  if (auditScanMeta) {
    auditScanMeta.textContent = "";
    auditScanMeta.classList.add("hidden");
  }
}

function updateAuditScanMeta(payload) {
  if (!auditScanMeta) return;
  const scanned = payload?.auditLinesScanned;
  const cap = payload?.auditScanCap;
  if (scanned == null || cap == null) {
    auditScanMeta.textContent = "";
    auditScanMeta.classList.add("hidden");
    return;
  }
  auditScanMeta.classList.remove("hidden");
  const atCap = Number(scanned) >= Number(cap);
  auditScanMeta.textContent = atCap
    ? `Audit scan uses the newest ${Number(scanned).toLocaleString()} lines (cap ${Number(cap).toLocaleString()}). Older events may be outside this window; increase AUDIT_LOG_MAX_SCAN_LINES on the server if needed.`
    : `Audit scan read ${Number(scanned).toLocaleString()} lines (cap ${Number(cap).toLocaleString()}).`;
}

const debouncedReloadIncidentHistory = debounce(() => {
  incidentsPage = 1;
  void loadIncidentHistory();
}, 350);

const debouncedReloadRestoreHistory = debounce(() => {
  restoresPage = 1;
  void loadIncidentHistory();
}, 350);

const debouncedRenderAuditPage = debounce(() => {
  auditPage = 1;
  renderAuditPage();
}, 250);

function renderIncidentHistory(incidents) {
  incidentHistoryList.replaceChildren();
  if (!Array.isArray(incidents) || !incidents.length) {
    const empty = document.createElement("p");
    empty.className = "audit-empty";
    empty.textContent = "No incident escalations yet.";
    incidentHistoryList.appendChild(empty);
    return;
  }

  for (const incident of incidents) {
    const row = document.createElement("div");
    row.className = "history-row";

    const ts = incident?.ts ? dateTimeFormatter.format(new Date(incident.ts)) : "Unknown time";
    const status = incident?.currentState || "open";
    const severity = String(incident?.severity || "high");
    const note =
      incident?.closedNote || incident?.resolvedNote || incident?.acknowledgmentNote || "";

    row.innerHTML = `
      <div class="history-meta">
        <span class="history-title">${incident?.code || "incident"}</span>
        <span class="history-pill severity-${severity}">${severity}</span>
      </div>
      <div class="audit-detail">${ts}</div>
      <div class="audit-detail">trigger: ${incident?.trigger || "-"}</div>
      <div class="audit-detail">count: ${incident?.count ?? "n/a"} / threshold: ${incident?.threshold ?? "n/a"}</div>
      <div class="audit-detail">state: ${status}</div>
      ${note ? `<div class="audit-detail">note: ${note}</div>` : ""}
    `;

    if (incident?.currentState !== "closed") {
      const actions = document.createElement("div");
      actions.className = "history-actions";
      if (incident?.currentState === "open") {
        const ackButton = document.createElement("button");
        ackButton.type = "button";
        ackButton.className = "secondary-button";
        ackButton.textContent = "Acknowledge";
        ackButton.addEventListener("click", async () => {
          const ackNote = window.prompt("Optional acknowledgment note:", "") || "";
          await updateIncidentState(incident.incidentId, "acknowledged", ackNote);
        });
        actions.appendChild(ackButton);
      }
      if (incident?.currentState === "open" || incident?.currentState === "acknowledged") {
        const resolveButton = document.createElement("button");
        resolveButton.type = "button";
        resolveButton.className = "secondary-button";
        resolveButton.textContent = "Resolve";
        resolveButton.addEventListener("click", async () => {
          const noteText = window.prompt("Resolution note:", "") || "";
          await updateIncidentState(incident.incidentId, "resolved", noteText);
        });
        actions.appendChild(resolveButton);
      }
      if (incident?.currentState !== "closed") {
        const closeButton = document.createElement("button");
        closeButton.type = "button";
        closeButton.className = "secondary-button";
        closeButton.textContent = "Close";
        closeButton.addEventListener("click", async () => {
          const noteText = window.prompt("Closure note:", "") || "";
          await updateIncidentState(incident.incidentId, "closed", noteText);
        });
        actions.appendChild(closeButton);
      }
      row.appendChild(actions);
    }

    incidentHistoryList.appendChild(row);
  }
}

function renderRestoreHistory(items) {
  restoreHistoryList.replaceChildren();
  if (!Array.isArray(items) || !items.length) {
    const empty = document.createElement("p");
    empty.className = "audit-empty";
    empty.textContent = "No restore activity yet.";
    restoreHistoryList.appendChild(empty);
    return;
  }

  for (const item of items) {
    const row = document.createElement("div");
    row.className = "history-row";
    const ts = item?.ts ? dateTimeFormatter.format(new Date(item.ts)) : "Unknown time";
    const label =
      item?.action === "admin_snapshot_restore_dry_run"
        ? "Dry run"
        : item?.action === "admin_snapshot_compare"
          ? "Compare"
          : "Restore";
    const diff = item?.diff || {};
    const snapshotLabel =
      item?.action === "admin_snapshot_compare"
        ? `${item?.leftSnapshotId || "-"} -> ${item?.rightSnapshotId || "-"}`
        : item?.snapshotId || "-";
    row.innerHTML = `
      <div class="history-meta">
        <span class="history-title">${label}</span>
        <span class="history-pill">${item?.key || "-"}</span>
      </div>
      <div class="audit-detail">${ts}</div>
      <div class="audit-detail">snapshot: ${snapshotLabel}</div>
      <div class="audit-detail">changed: ${item?.changed ? "yes" : "no"}</div>
      <div class="audit-detail">top-level changed: ${(diff.topLevelChanged || []).join(", ") || "none"}</div>
    `;
    restoreHistoryList.appendChild(row);
  }
}

function renderSnapshotOptions(snapshots) {
  snapshotSelect.replaceChildren();
  compareSnapshotSelect.replaceChildren();
  if (!Array.isArray(snapshots) || !snapshots.length) {
    const option = document.createElement("option");
    option.value = "";
    option.textContent = "No snapshots available";
    snapshotSelect.appendChild(option);
    compareSnapshotSelect.appendChild(option.cloneNode(true));
    return;
  }

  for (const snapshot of snapshots) {
    const option = document.createElement("option");
    option.value = snapshot.snapshotId;
    option.textContent = `${snapshot.snapshotId} (${snapshot.sizeBytes || 0} bytes)`;
    snapshotSelect.appendChild(option);
    compareSnapshotSelect.appendChild(option.cloneNode(true));
  }
}

function renderSnapshotPreview(payload) {
  snapshotPreview.replaceChildren();
  if (!payload) {
    const empty = document.createElement("p");
    empty.className = "audit-empty";
    empty.textContent = "Choose a snapshot to preview its diff.";
    snapshotPreview.appendChild(empty);
    return;
  }

  const diff = payload.diff || {};
  const card = document.createElement("div");
  card.className = "history-row";
  const title = payload.leftSnapshot && payload.rightSnapshot
    ? `${payload.leftSnapshot.snapshotId} vs ${payload.rightSnapshot.snapshotId}`
    : payload.snapshotId || "Snapshot preview";
  card.innerHTML = `
    <div class="history-meta">
      <span class="history-title">${title}</span>
      <span class="history-pill">${payload.key || "-"}</span>
    </div>
    <div class="audit-detail">integrity: ${
      payload.integrity?.ok ? "verified" :
      payload.leftSnapshot?.integrity?.ok && payload.rightSnapshot?.integrity?.ok ? "verified" :
      "unknown"
    }</div>
    <div class="audit-detail">changed: ${diff.changed ? "yes" : "no"}</div>
    <div class="audit-detail">before bytes: ${diff.beforeBytes ?? 0} / after bytes: ${diff.afterBytes ?? 0}</div>
    <div class="audit-detail">added: ${(diff.topLevelAdded || []).join(", ") || "none"}</div>
    <div class="audit-detail">removed: ${(diff.topLevelRemoved || []).join(", ") || "none"}</div>
    <div class="audit-detail">changed keys: ${(diff.topLevelChanged || []).join(", ") || "none"}</div>
  `;
  snapshotPreview.appendChild(card);
}

async function loadAuditLog() {
  if (!isAdminAuthenticated) {
    renderAuditEntries([]);
    return;
  }

  try {
    const response = await fetch("/admin/audit-log?limit=120", {
      headers: adminHeaders(),
    });
    if (!response.ok) {
      throw new Error(await response.text());
    }
    const payload = await response.json();
    renderAuditEntries(Array.isArray(payload.entries) ? payload.entries : []);
  } catch (error) {
    console.error(error);
    renderAuditEntries([
      {
        ts: new Date().toISOString(),
        action: "audit_log_load_failed",
      },
    ]);
  }
}

async function exportAuditLog(format) {
  if (!isAdminAuthenticated) {
    setFeedback("Sign in required");
    return;
  }

  try {
    const params = new URLSearchParams({
      format,
      limit: "1000",
    });
    const query = auditSearchInput?.value?.trim() || "";
    if (query) {
      params.set("q", query);
    }

    setFeedback(`Exporting audit ${format.toUpperCase()}...`);
    const response = await fetch(`/admin/audit-log/export?${params.toString()}`, {
      headers: adminHeaders(),
    });
    if (!response.ok) {
      throw new Error(await response.text());
    }

    const blob = await response.blob();
    const disposition = response.headers.get("Content-Disposition") || "";
    const filenameMatch = disposition.match(/filename="([^"]+)"/);
    const filename = filenameMatch?.[1] || `tenbelow-audit.${format}`;
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = filename;
    document.body.appendChild(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(url);
    await loadAuditLog();
    setFeedback(`Audit ${format.toUpperCase()} exported`);
  } catch (error) {
    console.error(error);
    setFeedback("Audit export failed");
  }
}

async function loadSecurityMetrics() {
  if (!isAdminAuthenticated) {
    renderSecurityMetrics(null);
    return;
  }

  try {
    const response = await fetch("/admin/security-metrics?limit=1000", {
      headers: adminHeaders(),
    });
    if (!response.ok) {
      throw new Error(await response.text());
    }
    const payload = await response.json();
    renderSecurityMetrics(payload);
  } catch (error) {
    console.error(error);
    renderSecurityMetrics(null);
  }
}

async function loadIncidentHistory() {
  if (!isAdminAuthenticated) {
    incidentsPage = 1;
    restoresPage = 1;
    renderIncidentHistory([]);
    renderRestoreHistory([]);
    resetIncidentHistoryPaginationUI();
    return;
  }

  try {
    const response = await fetch(`/admin/incident-history?${incidentHistoryQueryString()}`, {
      headers: adminHeaders(),
    });
    if (!response.ok) {
      throw new Error(await response.text());
    }
    const payload = await response.json();
    renderIncidentHistory(Array.isArray(payload.incidents) ? payload.incidents : []);
    renderRestoreHistory(Array.isArray(payload.restoreHistory) ? payload.restoreHistory : []);
    updateIncidentPaginationUI(payload);
    updateRestorePaginationUI(payload);
    updateAuditScanMeta(payload);
  } catch (error) {
    console.error(error);
    renderIncidentHistory([]);
    renderRestoreHistory([]);
    resetIncidentHistoryPaginationUI();
  }
}

async function loadSnapshots() {
  if (!isAdminAuthenticated) {
    renderSnapshotOptions([]);
    renderSnapshotPreview(null);
    return;
  }

  try {
    const key = snapshotKey.value;
    const response = await fetch(`/admin/data-snapshots?key=${encodeURIComponent(key)}&limit=50`, {
      headers: adminHeaders(),
    });
    if (!response.ok) {
      throw new Error(await response.text());
    }
    const payload = await response.json();
    renderSnapshotOptions(Array.isArray(payload.snapshots) ? payload.snapshots : []);
    if (compareSnapshotSelect.options.length > 1 && compareSnapshotSelect.value === snapshotSelect.value) {
      compareSnapshotSelect.selectedIndex = 1;
    }
    renderSnapshotPreview(null);
  } catch (error) {
    console.error(error);
    renderSnapshotOptions([]);
    renderSnapshotPreview(null);
  }
}

async function previewSnapshotRestore() {
  const key = snapshotKey.value;
  const snapshotId = snapshotSelect.value;
  if (!snapshotId) {
    setFeedback("Choose a snapshot first");
    return;
  }

  try {
    setFeedback("Previewing restore...");
    const response = await fetch("/admin/data-snapshots/restore", {
      method: "POST",
      headers: adminHeaders(),
      body: JSON.stringify({ key, snapshotId, dryRun: true }),
    });
    if (!response.ok) {
      throw new Error(await response.text());
    }
    const payload = await response.json();
    renderSnapshotPreview(payload);
    await loadIncidentHistory();
    setFeedback("Restore preview ready");
  } catch (error) {
    console.error(error);
    setFeedback("Restore preview failed");
  }
}

async function compareSnapshots() {
  const key = snapshotKey.value;
  const leftSnapshotId = snapshotSelect.value;
  const rightSnapshotId = compareSnapshotSelect.value;
  if (!leftSnapshotId || !rightSnapshotId) {
    setFeedback("Choose two snapshots to compare");
    return;
  }
  if (leftSnapshotId === rightSnapshotId) {
    setFeedback("Choose two different snapshots");
    return;
  }

  try {
    setFeedback("Comparing snapshots...");
    const response = await fetch("/admin/data-snapshots/compare", {
      method: "POST",
      headers: adminHeaders(),
      body: JSON.stringify({ key, leftSnapshotId, rightSnapshotId }),
    });
    if (!response.ok) {
      throw new Error(await response.text());
    }
    const payload = await response.json();
    renderSnapshotPreview(payload);
    await Promise.all([loadIncidentHistory(), loadAuditLog()]);
    setFeedback("Snapshot comparison ready");
  } catch (error) {
    console.error(error);
    setFeedback("Snapshot comparison failed");
  }
}

async function performSnapshotRestore() {
  const key = snapshotKey.value;
  const snapshotId = snapshotSelect.value;
  if (!snapshotId) {
    setFeedback("Choose a snapshot first");
    return;
  }
  if (!window.confirm(`Restore snapshot ${snapshotId} for ${key}?`)) {
    return;
  }

  try {
    setFeedback("Restoring snapshot...");
    const response = await fetch("/admin/data-snapshots/restore", {
      method: "POST",
      headers: adminHeaders(),
      body: JSON.stringify({ key, snapshotId }),
    });
    if (!response.ok) {
      throw new Error(await response.text());
    }
    const payload = await response.json();
    renderSnapshotPreview(payload);
    await Promise.all([loadIncidentHistory(), loadAuditLog(), loadSecurityMetrics()]);
    setFeedback("Snapshot restored");
  } catch (error) {
    console.error(error);
    setFeedback("Snapshot restore failed");
  }
}

async function triggerSecurityAlertTest() {
  try {
    setFeedback("Triggering synthetic alert...");
    const response = await fetch("/admin/security-alert-test", {
      method: "POST",
      headers: adminHeaders(),
      body: JSON.stringify({
        severity: alertTestSeverity.value,
        message: alertTestMessage.value.trim(),
      }),
    });
    if (!response.ok) {
      throw new Error(await response.text());
    }
    await Promise.all([loadIncidentHistory(), loadAuditLog(), loadSecurityMetrics()]);
    setFeedback("Synthetic alert dispatched");
  } catch (error) {
    console.error(error);
    setFeedback("Synthetic alert failed");
  }
}

async function updateIncidentState(incidentId, state, note) {
  try {
    setFeedback(`Updating incident to ${state}...`);
    const response = await fetch("/admin/incidents/state", {
      method: "POST",
      headers: adminHeaders(),
      body: JSON.stringify({ incidentId, state, note }),
    });
    if (!response.ok) {
      throw new Error(await response.text());
    }
    await Promise.all([loadIncidentHistory(), loadAuditLog()]);
    setFeedback(`Incident marked ${state}`);
  } catch (error) {
    console.error(error);
    setFeedback("Incident update failed");
  }
}

async function loadQueue(shouldAttemptSessionRefresh = true) {
  if (!isAdminAuthenticated) {
    if (shouldAttemptSessionRefresh) {
      await refreshAdminSessionState({ loadData: false });
      if (isAdminAuthenticated) {
        return loadQueue(false);
      }
    }
    setFeedback("Sign in required");
    productQueueCache = [];
    renderQueue([]);
    return;
  }

  try {
    setFeedback("Loading queue...");
    const status = statusFilter.value;
    const query = status ? `?status=${encodeURIComponent(status)}` : "";
    const response = await fetch(`/admin/products/review-queue${query}`, {
      headers: adminHeaders(),
    });

    if (!response.ok) {
      throw new Error(await response.text());
    }

    const payload = await response.json();
    productQueueCache = Array.isArray(payload.products) ? payload.products : [];
    renderQueue(productQueueCache);
    setFeedback("Queue ready");
  } catch (error) {
    productQueueCache = [];
    renderQueue([]);
    setFeedback("Failed to load queue");
    console.error(error);
  }
}

async function loadSellerDirectory() {
  if (!isAdminAuthenticated) {
    sellerDirectoryCache = [];
    renderSellerDirectory([]);
    return;
  }

  try {
    const response = await fetch("/admin/sellers", {
      headers: adminHeaders(),
    });
    if (!response.ok) {
      throw new Error(await response.text());
    }
    const payload = await response.json();
    sellerDirectoryCache = Array.isArray(payload.sellers) ? payload.sellers : [];
    renderSellerDirectory(sellerDirectoryCache);
    renderQueue(productQueueCache);
  } catch (error) {
    sellerDirectoryCache = [];
    renderSellerDirectory([]);
    console.error(error);
  }
}

async function refreshAdminSessionState(options = {}) {
  const { loadData = true } = options;
  if (isRefreshingAdminSession) {
    return;
  }

  isRefreshingAdminSession = true;
  try {
    const response = await fetch("/admin/session");
    if (!response.ok) {
      throw new Error(await response.text());
    }
    const payload = await response.json();
    isAdminAuthenticated = payload.authenticated === true;
    if (isAdminAuthenticated) {
      pendingAdminChallengeId = "";
      adminKeyInput.value = "";
      adminCodeInput.value = "";
    }
    syncAdminKeyVisibility();
    setFeedback(isAdminAuthenticated ? "Ready" : "Sign in required");
    if (isAdminAuthenticated && loadData) {
      await Promise.all([
        loadQueue(false),
        loadSellerDirectory(),
        loadAccounts(),
        loadCustomRequests(),
        loadExchangeQueue(),
        loadAuditLog(),
        loadSecurityMetrics(),
        loadIncidentHistory(),
        loadSnapshots(),
      ]);
    } else {
      incidentsPage = 1;
      restoresPage = 1;
      accountPage = 1;
      selectedExchangeRequestId = null;
      productQueueCache = [];
      sellerDirectoryCache = [];
      renderQueue([]);
      renderSellerDirectory([]);
      renderAccounts({ accounts: [], total: 0, page: 1, pages: 1 });
      renderCustomRequests([]);
      renderExchangeQueue([]);
      renderExchangeDetail(null);
      renderAuditEntries([]);
      renderSecurityMetrics(null);
      renderIncidentHistory([]);
      renderRestoreHistory([]);
      resetIncidentHistoryPaginationUI();
      renderSnapshotOptions([]);
      renderSnapshotPreview(null);
    }
  } catch (error) {
    isAdminAuthenticated = false;
    incidentsPage = 1;
    restoresPage = 1;
    accountPage = 1;
    selectedExchangeRequestId = null;
    productQueueCache = [];
    sellerDirectoryCache = [];
    syncAdminKeyVisibility();
    renderQueue([]);
    renderSellerDirectory([]);
    renderAccounts({ accounts: [], total: 0, page: 1, pages: 1 });
    renderCustomRequests([]);
    renderExchangeQueue([]);
    renderExchangeDetail(null);
    renderAuditEntries([]);
    renderSecurityMetrics(null);
    renderIncidentHistory([]);
    renderRestoreHistory([]);
    resetIncidentHistoryPaginationUI();
    renderSnapshotOptions([]);
    renderSnapshotPreview(null);
    setFeedback("Admin session unavailable");
    console.error(error);
  } finally {
    isRefreshingAdminSession = false;
  }
}

async function loginAdminSession() {
  try {
    const body = pendingAdminChallengeId
      ? {
          challengeId: pendingAdminChallengeId,
          code: adminCodeInput.value.trim(),
        }
      : {
          key: adminKeyInput.value.trim(),
        };

    setFeedback(pendingAdminChallengeId ? "Verifying code..." : "Sending admin code...");
    const response = await fetch("/admin/login", {
      method: "POST",
      headers: adminHeaders(),
      body: JSON.stringify(body),
    });
    if (!response.ok) {
      const raw = await response.text();
      let message = "Admin sign-in failed";
      try {
        const errPayload = JSON.parse(raw);
        message = errPayload.error || message;
      } catch {
        if (raw) message = raw;
      }
      throw new Error(message);
    }
    const payload = await response.json();

    if (payload.requiresCode) {
      pendingAdminChallengeId = payload.challengeId || "";
      adminKeyInput.value = "";
      adminCodeInput.value = "";
      syncAdminKeyVisibility();
      const devCode = payload.devCode ? ` Dev code: ${payload.devCode}` : "";
      setFeedback(`Code sent to ${payload.deliveryTarget || "admin email"}.${devCode}`);
      adminCodeInput.focus();
      return;
    }

    pendingAdminChallengeId = "";
    adminCodeInput.value = "";
    adminKeyInput.value = "";
    await refreshAdminSessionState();
  } catch (error) {
    if (pendingAdminChallengeId) {
      adminCodeInput.value = "";
      adminCodeInput.focus();
    }
    setFeedback(error?.message || "Admin sign-in failed");
    console.error(error);
  }
}

async function logoutAdminSession() {
  try {
    await fetch("/admin/logout", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
    });
  } finally {
    isAdminAuthenticated = false;
    pendingAdminChallengeId = "";
    adminCodeInput.value = "";
    adminKeyInput.value = "";
    incidentsPage = 1;
    restoresPage = 1;
    accountPage = 1;
    selectedExchangeRequestId = null;
    productQueueCache = [];
    sellerDirectoryCache = [];
    syncAdminKeyVisibility();
    renderQueue([]);
    renderSellerDirectory([]);
    renderAccounts({ accounts: [], total: 0, page: 1, pages: 1 });
    renderCustomRequests([]);
    renderExchangeQueue([]);
    renderExchangeDetail(null);
    renderAuditEntries([]);
    renderSecurityMetrics(null);
    renderIncidentHistory([]);
    renderRestoreHistory([]);
    resetIncidentHistoryPaginationUI();
    renderSnapshotOptions([]);
    renderSnapshotPreview(null);
    setFeedback("Signed out");
  }
}

function setReviewButtonsBusy(approveButton, rejectButton, archiveButton, disabled) {
  approveButton.disabled = disabled;
  rejectButton.disabled = disabled;
  archiveButton.disabled = disabled;
}

async function reviewProduct(productId, decision, notes, approveButton, rejectButton, archiveButton) {
  try {
    setReviewButtonsBusy(approveButton, rejectButton, archiveButton, true);
    setFeedback(decision === "approve" ? "Approving product..." : "Rejecting product...");

    const response = await fetch(`/admin/products/${encodeURIComponent(productId)}/review`, {
      method: "POST",
      headers: adminHeaders(),
      body: JSON.stringify({ decision, notes }),
    });

    if (!response.ok) {
      throw new Error(await response.text());
    }

    setFeedback(decision === "approve" ? "Product approved" : "Product rejected");
    await Promise.all([loadQueue(), loadSellerDirectory()]);
  } catch (error) {
    setFeedback("Review action failed");
    console.error(error);
    setReviewButtonsBusy(approveButton, rejectButton, archiveButton, false);
  }
}

async function archiveProduct(productId, notes, approveButton, rejectButton, archiveButton) {
  try {
    setReviewButtonsBusy(approveButton, rejectButton, archiveButton, true);
    setFeedback("Archiving product...");

    const response = await fetch(`/admin/products/${encodeURIComponent(productId)}/archive`, {
      method: "POST",
      headers: adminHeaders(),
      body: JSON.stringify({ notes }),
    });

    if (!response.ok) {
      throw new Error(await response.text());
    }

    setFeedback("Product archived");
    await Promise.all([loadQueue(), loadSellerDirectory()]);
  } catch (error) {
    setFeedback("Archive failed");
    console.error(error);
    setReviewButtonsBusy(approveButton, rejectButton, archiveButton, false);
  }
}

refreshButton.addEventListener("click", () => refreshAdminSessionState());
refreshAuditButton.addEventListener("click", () => Promise.all([loadAuditLog(), loadSecurityMetrics(), loadIncidentHistory()]));
if (exportAuditJsonButton) {
  exportAuditJsonButton.addEventListener("click", () => exportAuditLog("json"));
}
if (exportAuditCsvButton) {
  exportAuditCsvButton.addEventListener("click", () => exportAuditLog("csv"));
}
refreshIncidentsButton.addEventListener("click", loadIncidentHistory);
refreshSnapshotsButton.addEventListener("click", loadSnapshots);
statusFilter.addEventListener("change", loadQueue);
if (sellerFilter) {
  sellerFilter.addEventListener("change", () => {
    renderSellerDirectory(sellerDirectoryCache);
    renderQueue(productQueueCache);
  });
}
if (listingTypeFilter) {
  listingTypeFilter.addEventListener("change", () => {
    renderQueue(productQueueCache);
  });
}
if (refreshAccountsButton) {
  refreshAccountsButton.addEventListener("click", loadAccounts);
}
if (accountKindFilter) {
  accountKindFilter.addEventListener("change", () => {
    accountPage = 1;
    loadAccounts();
  });
}
if (accountPageSizeSelect) {
  accountPageSizeSelect.addEventListener("change", () => {
    accountPage = 1;
    loadAccounts();
  });
}
if (accountSearchInput) {
  accountSearchInput.addEventListener("input", debounce(() => {
    accountPage = 1;
    loadAccounts();
  }, 300));
}
if (accountPrevPage) {
  accountPrevPage.addEventListener("click", () => {
    accountPage = Math.max(1, accountPage - 1);
    loadAccounts();
  });
}
if (accountNextPage) {
  accountNextPage.addEventListener("click", () => {
    accountPage += 1;
    loadAccounts();
  });
}
if (refreshCustomRequestsButton) {
  refreshCustomRequestsButton.addEventListener("click", loadCustomRequests);
}
if (customRequestStatusFilter) {
  customRequestStatusFilter.addEventListener("change", loadCustomRequests);
}
if (customRequestSearchInput) {
  customRequestSearchInput.addEventListener("input", debounce(loadCustomRequests, 300));
}
if (refreshExchangeButton) {
  refreshExchangeButton.addEventListener("click", loadExchangeQueue);
}
if (exchangeStatusFilter) {
  exchangeStatusFilter.addEventListener("change", () => {
    selectedExchangeRequestId = null;
    void loadExchangeQueue();
  });
}
snapshotKey.addEventListener("change", loadSnapshots);
previewRestoreButton.addEventListener("click", previewSnapshotRestore);
restoreSnapshotButton.addEventListener("click", performSnapshotRestore);
compareSnapshotsButton.addEventListener("click", compareSnapshots);
triggerAlertTestButton.addEventListener("click", triggerSecurityAlertTest);
incidentSearchInput.addEventListener("input", debouncedReloadIncidentHistory);
incidentStateFilter.addEventListener("change", () => {
  incidentsPage = 1;
  void loadIncidentHistory();
});
restoreSearchInput.addEventListener("input", debouncedReloadRestoreHistory);
restoreTypeFilter.addEventListener("change", () => {
  restoresPage = 1;
  void loadIncidentHistory();
});
if (incidentPrevPage) {
  incidentPrevPage.addEventListener("click", () => {
    if (incidentsPage > 1) {
      incidentsPage -= 1;
      void loadIncidentHistory();
    }
  });
}
if (incidentNextPage) {
  incidentNextPage.addEventListener("click", () => {
    incidentsPage += 1;
    void loadIncidentHistory();
  });
}
if (restorePrevPage) {
  restorePrevPage.addEventListener("click", () => {
    if (restoresPage > 1) {
      restoresPage -= 1;
      void loadIncidentHistory();
    }
  });
}
if (restoreNextPage) {
  restoreNextPage.addEventListener("click", () => {
    restoresPage += 1;
    void loadIncidentHistory();
  });
}
if (auditSearchInput) {
  auditSearchInput.addEventListener("input", debouncedRenderAuditPage);
}
if (auditPageSizeSelect) {
  auditPageSizeSelect.addEventListener("change", () => {
    auditPage = 1;
    renderAuditPage();
  });
}
if (auditPrevPage) {
  auditPrevPage.addEventListener("click", () => {
    if (auditPage > 1) {
      auditPage -= 1;
      renderAuditPage();
    }
  });
}
if (auditNextPage) {
  auditNextPage.addEventListener("click", () => {
    auditPage += 1;
    renderAuditPage();
  });
}
loginButton.addEventListener("click", loginAdminSession);
logoutButton.addEventListener("click", logoutAdminSession);
adminKeyInput.addEventListener("keydown", (event) => {
  if (event.key === "Enter") {
    event.preventDefault();
    void loginAdminSession();
  }
});
adminCodeInput.addEventListener("keydown", (event) => {
  if (event.key === "Enter") {
    event.preventDefault();
    void loginAdminSession();
  }
});
lightboxClose.addEventListener("click", closeLightbox);
lightboxPrev.addEventListener("click", showPreviousLightboxImage);
lightboxNext.addEventListener("click", showNextLightboxImage);
lightbox.addEventListener("click", (event) => {
  if (event.target === lightbox) {
    closeLightbox();
  }
});
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && !lightbox.classList.contains("hidden")) {
    closeLightbox();
  }
  if (event.key === "ArrowLeft" && !lightbox.classList.contains("hidden")) {
    showPreviousLightboxImage();
  }
  if (event.key === "ArrowRight" && !lightbox.classList.contains("hidden")) {
    showNextLightboxImage();
  }
});

const ADMIN_PANEL_IDS = ["products", "accounts", "custom-requests", "exchanges", "audit", "incidents", "snapshots"];
const OPEN_PANEL_STORAGE_KEY = "tenbelow.admin.openPanel";

function getAdminPanelElements() {
  return {
    nav: document.querySelector(".admin-section-nav"),
    panels: Array.from(document.querySelectorAll(".admin-panel[data-panel-id]")),
    links: Array.from(document.querySelectorAll(".admin-section-link[data-panel-id]")),
  };
}

function setAdminPanelOpen(panelId, { scroll = false, persist = true } = {}) {
  const { panels, links } = getAdminPanelElements();
  if (!panels.length) {
    return;
  }

  panels.forEach((panel) => {
    const open = panel.dataset.panelId === panelId;
    panel.classList.toggle("is-open", open);
    const toggle = panel.querySelector(".admin-panel-toggle");
    const body = panel.querySelector(".admin-panel-body");
    if (toggle) {
      toggle.setAttribute("aria-expanded", open ? "true" : "false");
    }
    if (body) {
      body.hidden = !open;
    }
  });

  links.forEach((link) => {
    link.classList.toggle("is-active", link.dataset.panelId === panelId);
  });

  if (persist) {
    try {
      sessionStorage.setItem(OPEN_PANEL_STORAGE_KEY, panelId);
    } catch {
      // ignore private browsing quota errors
    }
  }

  if (scroll) {
    document.getElementById(`admin-panel-${panelId}`)?.scrollIntoView({ behavior: "smooth", block: "start" });
  }
}

function toggleAdminPanel(panelId) {
  const panel = document.querySelector(`.admin-panel[data-panel-id="${panelId}"]`);
  if (!panel) {
    return;
  }

  if (panel.classList.contains("is-open")) {
    panel.classList.remove("is-open");
    panel.querySelector(".admin-panel-toggle")?.setAttribute("aria-expanded", "false");
    const body = panel.querySelector(".admin-panel-body");
    if (body) {
      body.hidden = true;
    }
    getAdminPanelElements().links.forEach((link) => link.classList.remove("is-active"));
    try {
      sessionStorage.removeItem(OPEN_PANEL_STORAGE_KEY);
    } catch {
      // ignore
    }
    return;
  }

  setAdminPanelOpen(panelId, { scroll: true });
}

function initAdminPanels() {
  const { nav, panels } = getAdminPanelElements();
  if (!nav || !panels.length) {
    return;
  }

  let initialPanelId = "products";
  try {
    const stored = sessionStorage.getItem(OPEN_PANEL_STORAGE_KEY);
    if (stored && ADMIN_PANEL_IDS.includes(stored)) {
      initialPanelId = stored;
    }
  } catch {
    // ignore
  }

  setAdminPanelOpen(initialPanelId, { scroll: false, persist: false });

  nav.addEventListener("click", (event) => {
    const link = event.target.closest(".admin-section-link[data-panel-id]");
    if (!link) {
      return;
    }
    setAdminPanelOpen(link.dataset.panelId, { scroll: true });
  });

  panels.forEach((panel) => {
    const toggle = panel.querySelector(".admin-panel-toggle");
    const panelId = panel.dataset.panelId;
    if (!toggle || !panelId) {
      return;
    }
    toggle.addEventListener("click", () => toggleAdminPanel(panelId));
  });
}

initAdminPanels();
refreshAdminSessionState();
