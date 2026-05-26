//
//  LegalDocumentView.swift
//  TenBelow
//

import SwiftUI

enum LegalDocument: Identifiable {
    case termsOfService
    case privacyPolicy
    case dmcaPolicy
    case sellerAgreement
    case exchangePolicy

    var id: String {
        switch self {
        case .termsOfService: return "termsOfService"
        case .privacyPolicy: return "privacyPolicy"
        case .dmcaPolicy: return "dmcaPolicy"
        case .sellerAgreement: return "sellerAgreement"
        case .exchangePolicy: return "exchangePolicy"
        }
    }

    var title: String {
        switch self {
        case .termsOfService:
            return "Terms of Service"
        case .privacyPolicy:
            return "Privacy Policy"
        case .dmcaPolicy:
            return "DMCA Policy"
        case .sellerAgreement:
            return "Seller Agreement"
        case .exchangePolicy:
            return "Exchange Policy"
        }
    }

    var subtitle: String {
        switch self {
        case .termsOfService, .privacyPolicy, .sellerAgreement, .exchangePolicy:
            return "Effective Date: April 24, 2026"
        case .dmcaPolicy:
            return "In-app document coming next"
        }
    }

    var bodyText: String {
        switch self {
        case .termsOfService:
            return """
TERMS OF SERVICE

Effective Date: April 24, 2026

These Terms of Service govern your access to and use of the TenBelow mobile application, related marketplace tools, storefront features, buyer tools, seller tools, creator tools, support channels, and related services operated by Innovative Codeworks LLC, doing business as TenBelow. In these Terms, “TenBelow,” “Company,” “we,” “us,” and “our” mean Innovative Codeworks LLC. “You” means any person or entity accessing or using TenBelow, including buyers, sellers, creators, browsers, and account holders.

By creating an account, browsing the app, listing products, purchasing products, uploading content, submitting reviews, requesting exchanges, using seller tools, submitting custom requests, uploading maker videos, or otherwise using TenBelow, you agree to be bound by these Terms of Service, our Privacy Policy, our Seller Agreement, our Exchange Policy, and any additional policies, rules, or feature-specific requirements we make available through the app. If you do not agree to these Terms, do not use TenBelow.

Seller membership fees help support the operation, growth, improvement, and promotion of the TenBelow platform, including seller tools, buyer-facing improvements, and marketplace marketing initiatives, as determined by TenBelow in its discretion.

1. Eligibility

You must be at least eighteen (18) years old, or the age of legal majority in your jurisdiction, to create an account or use TenBelow for buying, selling, or creator participation. By using TenBelow, you represent and warrant that you have the legal capacity to enter into a binding agreement and that all information you provide to TenBelow is truthful, accurate, current, and complete.

If you use TenBelow on behalf of a business or other legal entity, you represent and warrant that you have the authority to bind that business or entity to these Terms.

2. Nature of the Platform

TenBelow is a two-sided marketplace platform. Buyers use TenBelow to browse products, place orders, track shipments, request eligible exchanges, and leave reviews. Sellers and creators use TenBelow to build storefronts, upload products, manage listings, fulfill orders, participate in special release experiences such as Drops, respond to custom requests where available, upload maker videos where available, and manage their seller presence on the platform.

Unless TenBelow expressly states otherwise for a specific product or transaction, TenBelow is not the manufacturer of third-party goods listed by sellers, is not the owner of third-party inventory, and does not independently warrant the safety, legality, quality, durability, merchantability, or fitness of products sold by third-party sellers through the platform.

For third-party marketplace transactions, the sale is between the buyer and the seller. TenBelow provides marketplace infrastructure, app functionality, content presentation, payment coordination, promotional tools, seller tools, moderation tools, communications tools, support tools, and limited dispute assistance, but does not assume seller obligations unless expressly stated by TenBelow in writing.

3. Accounts and Security

To access certain features, you may be required to create an account. You agree to provide complete and accurate information, maintain the confidentiality of your login credentials, update your information when it changes, and notify TenBelow immediately if you become aware of unauthorized access to your account.

You are solely responsible for all activity that occurs under your account. TenBelow may suspend, restrict, or terminate accounts that contain false information, violate these Terms, create legal or operational risk, interfere with the experience of other users, or otherwise threaten the integrity of the platform.

4. Buyer Rules

As a buyer, you agree to:
- review product listings carefully before placing an order;
- provide accurate shipping, billing, and contact information;
- use lawful and valid payment methods;
- communicate honestly and respectfully through the platform;
- submit truthful exchange requests, support requests, reviews, and custom-request information;
- comply with all applicable laws and platform rules.

Buyers may not use TenBelow to submit fraudulent orders, false exchange claims, abusive reviews, chargeback abuse, harassment, or any conduct that undermines marketplace trust.

5. Seller and Creator Rules

As a seller or creator, you agree to:
- comply with the Seller Agreement and all applicable laws;
- provide accurate product descriptions, dimensions, materials, pricing, images, processing times, shipping estimates, and storefront information;
- list only products you have the legal right to display, market, and sell;
- fulfill accepted orders in a timely, professional, and lawful manner;
- cooperate with approved exchange requests and support processes;
- avoid misleading, infringing, unsafe, counterfeit, unlawful, or prohibited listings.

Sellers may not upload copied content, false shipping promises, inaccurate product claims, unsafe products, or unlawful goods, and may not use TenBelow in a fraudulent or abusive manner.

No illegal products under United States law may be listed, promoted, requested, sold, traded, or arranged through TenBelow. This includes, without limitation, ghost guns, firearm parts, weapon components, unserialized weapons, explosives, ammunition, dangerous devices, controlled substances, stolen goods, counterfeit goods, recalled products, or any item that is unlawful, unsafe, or designed to cause harm. TenBelow may remove the listing, delete the account, ban the user permanently, preserve records, and report activity to appropriate authorities when prohibited or dangerous products are monitored, discovered, or reported.

6. Listings, Availability, and Product Information

Sellers are solely responsible for the content and accuracy of their listings. Each listing must accurately describe the product being offered, including material details, dimensions, compatibility information where relevant, intended use, important limitations, normal production characteristics, pricing, shipping expectations, and any other information a reasonable buyer would need before purchasing.

Because many items on TenBelow may be creator-made, 3D printed, made to order, or produced in small batches, minor visual or process-based variation may occur. Sellers must disclose characteristics that a reasonable buyer would want to know before purchase.

Listings submitted by sellers may be held as pending, reviewed through TenBelow’s admin review tools, approved, rejected, archived, removed, reordered, or returned for more information before or after they appear in the marketplace. Admin review may consider listing quality, product safety, intellectual property concerns, seller identity, marketplace fit, product accuracy, user reports, past account activity, and operational risk.

TenBelow does not guarantee listing availability, seller inventory levels, delivery dates, or the success of any listing, storefront, or promotional placement. TenBelow reserves the right to edit, remove, reject, archive, reorder, hide, suspend, or limit listings at its discretion.

7. Higher-Risk Product Categories

Certain product categories may present elevated safety, compliance, or consumer-protection risk, including products involving lighting, electrical components, batteries, charging functions, internal or external wiring, heat-producing elements, powered decorative features, or similar characteristics.

TenBelow reserves the right to prohibit, restrict, review, remove, reject, suspend, or require additional documentation for any product category that TenBelow determines may create product-safety, consumer-protection, regulatory, fire, burn, electrical, charging, or marketplace-liability concerns.

Sellers listing higher-risk products must provide accurate and complete information sufficient for a reasonable buyer to understand safe use, foreseeable limitations, and any warnings or instructions necessary to reduce the risk of misuse, damage, injury, or property loss.

TenBelow may require supporting documentation, warnings, instructions, component information, sourcing details, certification information, or other materials before allowing a higher-risk product to be listed or remain active.

8. Orders, Payments, and Seller Memberships

When a buyer places an order through TenBelow, payment may be processed through a third-party payment processor such as Stripe or a related service provider. By submitting payment information, the buyer authorizes the applicable processor to charge the amounts due for the transaction, including the product price, taxes where applicable, shipping charges, and other disclosed fees.

Physical product purchases made by buyers are separate from seller membership fees. Seller access to seller tools or seller features may be offered through a paid membership structure, including subscription billing where applicable.

At the current stage of TenBelow’s marketplace structure, TenBelow does not charge commission on product sales unless TenBelow later updates its pricing structure through revised terms, revised seller policies, or other written notice.

TenBelow may delay, review, hold, reverse, or offset payments or payouts where necessary to address fraud, chargebacks, disputes, approved exchanges, policy violations, legal requests, risk review, or technical or operational concerns.

9. Shipping and Fulfillment

Sellers are responsible for shipping orders within the timeframe stated in their listings or storefront materials. Sellers must not state unrealistic shipping times or make shipping promises they do not reasonably expect to meet.

If a seller cannot ship within the stated or promised timeframe, TenBelow may require delay handling, buyer notification, cancellation, refund processing where legally required, or other action necessary to comply with law or protect users and the platform.

Buyers are responsible for providing accurate shipping information. TenBelow is not responsible for delivery failures caused by incorrect buyer address information or carrier issues outside TenBelow’s control, although TenBelow may assist in reviewing marketplace issues.

10. Exchanges, Cancellations, and Refunds

TenBelow’s standard remedy for eligible delivered-item issues is exchange or replacement rather than refund, particularly for creator-made and 3D-printed products. Buyers may request one exchange per purchased item in accordance with the Exchange Policy.

Eligible exchange requests generally include products that arrive damaged, defective, materially different from the listing, or incorrect due to seller fulfillment error. Exchange requests must be supported by required evidence and submitted within the timeframe stated in the Exchange Policy.

TenBelow reviews exchange requests first and may approve, deny, or request additional information. TenBelow may also seek seller input before making a final determination. Sellers must comply with approved exchange decisions.

Refunds are generally not offered for delivered items except where required by law, where an order cannot be fulfilled or replaced, where a shipping-delay cancellation must be honored, where a seller fails to comply with an approved remedy, or where TenBelow determines that a refund is necessary to resolve a valid claim, marketplace failure, or legal obligation.

11. Custom Requests and Optional Seller Features

TenBelow may allow buyers to submit custom requests or quote requests to sellers who opt into that feature. Sellers are not required to accept custom requests. TenBelow may review, route, moderate, or remove custom request activity where necessary.

Any custom request feature is provided for marketplace convenience and communication. Unless TenBelow expressly states otherwise, TenBelow does not guarantee that a custom request will be accepted, completed, or fulfilled, and TenBelow is not the designer or manufacturer of custom products offered by third-party sellers.

12. Drops, Special Releases, and Promotional Features

TenBelow may provide special release experiences such as Weekly Drops, curated release programs, featured slots, or other promotional features. Participation in these features is subject to TenBelow’s rules, seller eligibility, platform capacity, and editorial discretion.

TenBelow does not guarantee that any product, storefront, creator, or campaign will be selected for a Drop, featured placement, social repost, homepage placement, or any other promotional treatment.

13. Reviews, User Content, and Platform License

You may submit content to TenBelow, including profile information, storefront information, product photos, product videos, descriptions, reviews, custom request content, support messages, maker videos, and other content. You retain ownership of your original content, subject to the rights you grant to TenBelow.

By submitting content to TenBelow, you grant Innovative Codeworks LLC a non-exclusive, worldwide, royalty-free, sublicensable license to host, store, reproduce, adapt, publish, display, distribute, promote, and otherwise use that content in connection with operating, securing, moderating, improving, and marketing the platform.

You represent and warrant that you own or control the rights necessary to submit that content and that your content does not infringe any third-party right, violate any law, or mislead users.

14. Platform Rights and Enforcement

TenBelow may review, moderate, remove, hide, reorder, restrict, suspend, or refuse any content, listing, storefront, account, payout, or platform access where TenBelow believes such action is necessary to enforce its rules, comply with law, address safety or intellectual property concerns, protect users, or preserve marketplace integrity.

TenBelow’s admin tools may allow authorized personnel to review seller directories, buyer and seller accounts, product queues, custom requests, exchange requests, audit logs, security events, account activity, and related marketplace records. TenBelow may delete or disable accounts where needed for moderation, mock-data cleanup, fraud prevention, legal compliance, or platform operations. If a seller account is deleted, related seller products may be removed from the active catalog; historical records such as orders, exchanges, audit logs, payment records, or support records may remain where needed for safety, accounting, dispute, legal, or operational reasons.

TenBelow may also retain records, maintain audit logs, cooperate with law enforcement or regulatory authorities, and take any other action reasonably necessary to protect the platform, its users, or the public.

15. Prohibited Conduct

You may not use TenBelow to:
- violate any law or regulation;
- infringe copyrights, trademarks, publicity rights, privacy rights, patents, or other rights;
- upload or sell counterfeit, copied, unsafe, recalled, stolen, unlawful, or prohibited goods;
- list, sell, request, promote, or arrange ghost guns, firearm parts, weapon components, explosives, ammunition, controlled substances, dangerous devices, or any product illegal under United States law;
- submit deceptive or misleading listings or platform information;
- bypass platform fees, order flows, or moderation tools;
- interfere with the platform, its code, security, or normal operations;
- upload malicious code, spam, or abusive content;
- manipulate reviews, disputes, exchange claims, or payment activity;
- impersonate another person or business;
- harass, threaten, or exploit another user.

16. Privacy

Your use of TenBelow is also governed by the Privacy Policy. You acknowledge that TenBelow may collect, use, share, store, and process information as described in that Privacy Policy.

17. Disclaimers

TENBELOW IS PROVIDED ON AN “AS IS” AND “AS AVAILABLE” BASIS TO THE MAXIMUM EXTENT PERMITTED BY LAW. TENBELOW DISCLAIMS ALL WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, TITLE, NON-INFRINGEMENT, ACCURACY, RELIABILITY, SECURITY, AND AVAILABILITY.

TENBELOW DOES NOT GUARANTEE THAT THE PLATFORM WILL BE UNINTERRUPTED, ERROR-FREE, OR COMPLETELY SECURE, OR THAT THIRD-PARTY SELLER PRODUCTS WILL BE SAFE, LAWFUL, DELIVERED ON TIME, FIT FOR ANY PARTICULAR PURPOSE, OR FREE FROM DEFECTS, EXCEPT AS REQUIRED BY APPLICABLE LAW.

18. Limitation of Liability

TO THE MAXIMUM EXTENT PERMITTED BY LAW, INNOVATIVE CODEWORKS LLC, TENBELOW, AND THEIR AFFILIATES, MEMBERS, MANAGERS, OFFICERS, EMPLOYEES, CONTRACTORS, AND AGENTS SHALL NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, EXEMPLARY, OR PUNITIVE DAMAGES, OR FOR ANY LOSS OF PROFITS, REVENUE, GOODWILL, DATA, BUSINESS, OR OPPORTUNITY ARISING OUT OF OR RELATING TO YOUR USE OF TENBELOW, ANY PRODUCT PURCHASED THROUGH TENBELOW, ANY SELLER OR BUYER DISPUTE, OR ANY CONTENT MADE AVAILABLE THROUGH THE PLATFORM.

TO THE MAXIMUM EXTENT PERMITTED BY LAW, TENBELOW’S TOTAL LIABILITY FOR ANY CLAIM ARISING OUT OF OR RELATING TO TENBELOW SHALL NOT EXCEED THE GREATER OF ONE HUNDRED U.S. DOLLARS (US $100.00) OR THE AMOUNT YOU PAID DIRECTLY TO TENBELOW IN THE TWELVE (12) MONTHS PRECEDING THE EVENT GIVING RISE TO THE CLAIM.

19. Indemnification

You agree to indemnify, defend, and hold harmless Innovative Codeworks LLC, TenBelow, and their affiliates, members, managers, officers, employees, contractors, and agents from and against any claims, liabilities, damages, losses, judgments, fines, penalties, costs, and expenses, including reasonable attorneys’ fees, arising out of or relating to your use of the platform, your products, your listings, your content, your conduct, your violation of these Terms, or your violation of any law or third-party right.

20. Suspension and Termination

TenBelow may suspend, restrict, remove, or terminate your account, listings, storefront, payouts, access, or platform privileges at any time, with or without prior notice, if TenBelow believes you have violated these Terms, created legal or operational risk, harmed users, engaged in fraud, infringed rights, or otherwise acted inconsistently with the integrity of the platform.

Accounts involved in prohibited, illegal, dangerous, weapon-related, ghost-gun-related, controlled-substance-related, counterfeit, stolen, or intentionally harmful activity may be permanently banned from TenBelow. TenBelow may delete or disable the account, remove related listings, block future access, preserve relevant records, and cooperate with law enforcement or regulatory authorities where appropriate.

21. Governing Law and Venue

These Terms are governed by the laws of the Commonwealth of Pennsylvania, without regard to conflict-of-law principles. Any dispute arising out of or relating to TenBelow or these Terms shall be brought exclusively in the state or federal courts located in Pennsylvania, and you consent to personal jurisdiction and venue in those courts.

22. Changes to These Terms

TenBelow may update these Terms from time to time. Updated Terms become effective when posted in the app, made available through the platform, or otherwise communicated to users. Your continued use of TenBelow after an update constitutes acceptance of the revised Terms.

23. Contact

Innovative Codeworks LLC
Doing Business As: TenBelow
Founder: Steven LeVere
admin@innovativecodeworks.com

By using TenBelow, you acknowledge that you have read, understood, and agreed to these Terms of Service.
"""
        case .privacyPolicy:
            return """
PRIVACY POLICY

Effective Date: April 24, 2026

This Privacy Policy explains how Innovative Codeworks LLC, doing business as TenBelow, collects, uses, shares, stores, and protects information when you access or use the TenBelow mobile application, related marketplace tools, storefront tools, buyer tools, seller tools, creator tools, support channels, and related services.

In this Privacy Policy, “TenBelow,” “Company,” “we,” “us,” and “our” mean Innovative Codeworks LLC. “You” means any person who accesses or uses TenBelow, including buyers, sellers, creators, and account holders.

By using TenBelow, you acknowledge the practices described in this Privacy Policy.

1. Information We Collect

We may collect information you provide directly to us, information collected automatically through your use of TenBelow, information received from third-party service providers, and information created through marketplace activity.

Information you provide directly may include:
- your name;
- email address;
- username;
- password credentials or authentication-related data;
- profile information;
- storefront information;
- seller profile materials;
- shipping information;
- billing-related information;
- customer support communications;
- exchange request submissions;
- custom request submissions;
- product descriptions;
- product images;
- product videos;
- maker videos;
- reviews;
- messages;
- and other content you choose to upload.

If you are a seller or creator, we may also collect additional information needed for onboarding, payment setup, payout setup, tax-related setup, verification, moderation, storefront display, seller review, or compliance-related functions.

If you make a purchase, payment information may be collected and processed by a third-party payment processor. TenBelow may receive limited transaction-related information such as payment status, order confirmation information, billing-related metadata, processor identifiers, and records needed to operate the marketplace, but may not directly store full payment card information.

Information collected automatically may include:
- device type;
- operating system;
- app version;
- crash data;
- usage data;
- analytics data;
- activity logs;
- push notification token or device registration data;
- approximate identifiers;
- session-related data;
- and information about how users interact with TenBelow.

We may also collect marketplace activity information such as:
- listings;
- orders;
- order status changes;
- shipment updates;
- tracking information;
- exchange requests;
- seller responses;
- support records;
- moderation actions;
- admin review actions;
- account-management actions;
- audit logs and security event records;
- dispute-related activity;
- custom request activity;
- and review activity.

2. How We Use Information

We may use collected information to:
- create and manage accounts;
- operate, maintain, improve, and secure TenBelow;
- facilitate buying and selling activity;
- process or support transactions;
- support payouts and payment operations;
- review listings and user content;
- review exchanges, custom requests, and support claims;
- operate admin review, account-management, audit, and security tools;
- send transactional communications;
- send administrative or service-related notices;
- provide customer support;
- detect fraud, abuse, and policy violations;
- enforce our terms and policies;
- comply with legal obligations;
- monitor marketplace quality and trust;
- support internal analytics and operational decisions;
- personalize marketplace content;
- promote the platform, products, storefronts, and creators.

3. How We Share Information

We may share information with service providers and partners that help us operate TenBelow, including payment processors, payout providers, hosting providers, storage providers, analytics vendors, notification providers, communications vendors, support tools, email services, and security services.

We may share information between buyers and sellers as reasonably necessary to complete orders, process shipping, resolve support issues, evaluate approved exchanges, respond to custom requests, or comply with marketplace requirements.

For example:
- sellers may receive buyer shipping information and order details needed to fulfill an order;
- buyers may receive seller storefront information, shipment details, and order status updates;
- sellers may receive relevant exchange-related information necessary to fulfill an approved replacement;
- sellers who opt into custom requests may receive information submitted by buyers in those requests.

We may also share information:
- when required by law, subpoena, court order, governmental request, or legal process;
- when we believe sharing is reasonably necessary to protect rights, safety, property, users, TenBelow, or the public;
- in connection with a merger, acquisition, financing, restructuring, sale of assets, or similar business transaction involving all or part of the Company.

4. Public and Marketplace-Facing Information

Certain information you provide may be visible to other users or the public depending on how you use the platform. This may include:
- your username;
- storefront name;
- profile information;
- creator bio;
- product listings;
- listing photos;
- listing videos;
- reviews;
- and promotional content.

Sellers and creators should not upload private or sensitive information they do not want displayed or used in connection with marketplace operations and promotion.

5. Notifications and Communications

TenBelow may send transactional, operational, and service-related communications, including:
- order confirmations;
- receipts;
- order status updates;
- exchange-related notifications;
- support messages;
- seller onboarding notices;
- security notices;
- marketing or promotional communications where permitted.

You may be able to manage certain notification settings through the app or your device settings, but you may still receive non-optional transactional communications related to your account or transactions.

6. Data Retention

We retain information for as long as reasonably necessary to operate the platform, maintain marketplace records, fulfill transactions, resolve disputes, investigate fraud, support exchanges, enforce agreements, comply with legal obligations, maintain financial and tax records, and protect TenBelow and its users.

Retention periods may vary depending on the nature of the information, the reason it was collected, operational needs, legal obligations, dispute status, and fraud-prevention needs.

If an account is deleted or disabled, TenBelow may remove active account access and related active storefront or listing content while retaining certain records that are reasonably needed for order history, exchange history, payment records, audit logs, security review, legal compliance, fraud prevention, tax or accounting obligations, support history, and marketplace integrity. Seller account deletion may remove that seller’s active products from the marketplace catalog, while some historical activity may remain in internal records.

7. Your Choices

You may update certain account information through the app or by contacting us. You may request deletion of your account by contacting us, subject to legal, operational, compliance, fraud-prevention, financial-recordkeeping, dispute-resolution, and tax-related retention obligations that may require us to keep certain records.

You may also manage certain device-level permissions and notification settings through your device or system settings.

8. Data Security

We use reasonable administrative, technical, and organizational measures designed to protect information against unauthorized access, alteration, disclosure, or destruction. However, no method of transmission, storage, or security system is completely secure, and TenBelow cannot guarantee absolute security.

9. Children’s Privacy

TenBelow is not intended for children under thirteen (13) years of age, and we do not knowingly collect personal information from children under thirteen. If we learn that we have collected personal information from a child under thirteen without appropriate authorization, we will take reasonable steps to delete that information.

10. Third-Party Services

TenBelow may contain links to or integrations with third-party services. This Privacy Policy does not apply to the privacy practices of third-party services, and we encourage users to review their policies separately.

11. International Use

TenBelow is operated from the United States. If you access the platform from outside the United States, you understand that your information may be transferred to, stored in, and processed in the United States or other jurisdictions where our service providers operate.

12. Changes to This Privacy Policy

We may update this Privacy Policy from time to time. Revised versions become effective when posted in the app, made available through the platform, or otherwise communicated to users. Your continued use of TenBelow after an update constitutes acknowledgment of the revised policy.

13. Contact

Innovative Codeworks LLC
Doing Business As: TenBelow
Founder: Steven LeVere
admin@innovativecodeworks.com

If you have questions about this Privacy Policy or TenBelow’s privacy practices, contact us at admin@innovativecodeworks.com.
"""
        case .dmcaPolicy:
            return """
This document will be added in a future update.

For now, DMCA policy content can be provided here in-app once TenBelow is ready to publish the finalized policy.
"""
        case .sellerAgreement:
            return """
SELLER AGREEMENT

Effective Date: April 24, 2026

This Seller Agreement governs participation by sellers and creators on the TenBelow marketplace operated by Innovative Codeworks LLC, doing business as TenBelow. In this Agreement, “TenBelow,” “Company,” “we,” “us,” and “our” mean Innovative Codeworks LLC. “Seller,” “Creator,” and “you” mean any individual or business approved to list, promote, or sell products through TenBelow.

By applying to sell, creating a seller account, onboarding to payout services, uploading listings, accepting orders, receiving payouts, or otherwise participating as a seller or creator on TenBelow, you agree to be bound by this Seller Agreement, the Terms of Service, the Privacy Policy, the Exchange Policy, and any other seller-facing rules or platform requirements made available by TenBelow.

Seller membership fees help support the operation, growth, improvement, and promotion of the TenBelow platform, including seller tools, buyer-facing improvements, and marketplace marketing initiatives, as determined by TenBelow in its discretion.

1. Seller Eligibility and Approval

To sell on TenBelow, you must:
- be at least eighteen (18) years old or the age of legal majority in your jurisdiction;
- have legal authority to enter into this Agreement;
- provide accurate onboarding, payout, verification, and tax-related information as requested;
- have the legal right to market, display, and sell the products and content you submit to TenBelow.

Seller participation on TenBelow is limited and subject to TenBelow approval. TenBelow may approve, deny, pause, suspend, limit, or revoke seller access at its discretion.

2. Nature of Seller Participation

TenBelow provides marketplace infrastructure, storefront tools, listing tools, order tools, payout coordination, optional promotional opportunities, and related services. Unless TenBelow expressly states otherwise in writing, TenBelow is not the manufacturer of your products, is not responsible for your inventory, and does not assume your obligations relating to product design, production, labeling, shipping, fulfillment, warranties, taxes, safety, or legal compliance.

You are solely responsible for the products you list and sell through the platform.

3. Seller Responsibilities

As a seller, you agree to:
- provide truthful, complete, and current seller and storefront information;
- list only products you have the legal right to sell;
- maintain accurate titles, descriptions, photos, videos, pricing, materials, dimensions, and shipping timelines;
- package and ship products reasonably and safely;
- fulfill accepted orders within the timeframe represented to buyers;
- respond to TenBelow support inquiries, exchange requests, and seller-side operational requests in a timely and professional manner;
- comply with all applicable laws, including consumer protection, product safety, intellectual property, advertising, tax, and shipping laws;
- avoid deceptive, misleading, abusive, fraudulent, or unlawful conduct.

4. Listing Standards

All listings must accurately reflect what the buyer will receive. A seller may not exaggerate product quality, use inaccurate or stolen images, misstate compatibility, conceal important limitations, or present mockups that materially misrepresent the actual item.

If a product is 3D printed, custom made, made to order, modified, or subject to normal production variation, you must clearly disclose relevant characteristics that a reasonable buyer would want to know before purchasing.

Listings may be submitted for TenBelow review before becoming visible in the marketplace. TenBelow may approve, reject, archive, remove, edit, hide, suspend, or return listings for revision when they are incomplete, inaccurate, misleading, low quality, duplicative, unsafe, infringing, inconsistent with marketplace standards, or otherwise risky for buyers or the platform. Admin review decisions may include notes or reasons visible to the seller.

5. Higher-Risk Product Categories

Certain product categories may present elevated safety, compliance, or marketplace-liability risk, including products involving lighting, electrical components, batteries, charging functions, internal or external wiring, heat-producing elements, powered decorative features, or similar characteristics.

If you list any higher-risk product, you must provide accurate and complete information sufficient for a reasonable buyer to understand:
- how the product is powered;
- whether it uses batteries, USB power, charging hardware, or external power sources;
- relevant materials and components where safety may be affected;
- intended use and any important limitations;
- foreseeable heat, charging, electrical, burn, or misuse risks where applicable;
- clear operating, setup, and care instructions where reasonably necessary;
- and any warning, restriction, or disclosure needed to prevent the listing from being misleading.

TenBelow may require additional documentation, instructions, warning language, sourcing details, component details, certification information, or other supporting materials before allowing higher-risk products to be listed or remain active.

TenBelow may prohibit or restrict certain higher-risk categories at its discretion and may remove, reject, or suspend listings where it believes a product may create safety concerns, legal exposure, or marketplace-integrity issues.

6. Prohibited Products and Conduct

You may not list, advertise, or sell products that are unlawful, dangerous, counterfeit, copied without authorization, infringing, deceptive, recalled, stolen, or otherwise prohibited by TenBelow.

No seller may list, promote, request, sell, trade, arrange, or attempt to route through TenBelow any product or activity that is illegal under United States law. This includes, without limitation, ghost guns, firearm parts, weapon components, unserialized weapons, explosives, ammunition, dangerous devices, controlled substances, stolen goods, counterfeit goods, recalled goods, or any item designed to cause harm or evade law enforcement, safety, or regulatory requirements.

You may not:
- misuse brand names, logos, entertainment properties, team marks, characters, or other protected material without authorization;
- submit false shipping information;
- submit false inventory or product details;
- manipulate orders, reviews, or exchange claims;
- evade platform fees or platform rules;
- use the platform for fraudulent or abusive conduct.

7. Seller Content and Platform License

You retain ownership of your original seller content, including listing photos, product descriptions, storefront branding, creator bio, product videos, and related materials, subject to the rights granted to TenBelow.

By uploading or submitting content to TenBelow, you grant Innovative Codeworks LLC a worldwide, non-exclusive, royalty-free, sublicensable license to host, store, reproduce, adapt, display, distribute, publish, repost, and otherwise use that content in connection with operating, improving, securing, moderating, and marketing TenBelow.

This includes use inside the app, on TenBelow social media channels, in creator spotlights, in featured campaigns, in launch materials, in emails, and in related promotional efforts.

You represent and warrant that you own or control all rights necessary to upload your content and sell your products, and that neither your content nor your products infringe the rights of any third party.

8. Seller Onboarding, Verification, and Payouts

To sell on TenBelow, you may be required to complete account verification, payout onboarding, tax-related setup, and related compliance steps through TenBelow and/or its payment partners.

You agree to provide accurate information for payout and verification purposes and to keep that information current. TenBelow may restrict selling privileges, hold payouts, or pause listings where onboarding, verification, tax setup, or payout eligibility is incomplete, inaccurate, or under review.

Payout timing may vary based on payment processing, order status, disputes, approved exchanges, risk review, chargebacks, policy compliance, or technical issues. TenBelow may hold, delay, reverse, or offset payouts where necessary to address marketplace risk, legal requirements, fraud concerns, or seller noncompliance.

9. Orders and Fulfillment

When a buyer places an order for one of your products and the transaction is accepted through the platform, you are responsible for fulfilling that order in accordance with your listing terms, platform rules, applicable law, and this Agreement.

You must ship orders within the stated timeframe. You may not mark an order as shipped before it has actually shipped, and you may not provide false tracking information.

You are responsible for correct item selection, reasonable packaging, shipment preparation, product accuracy, and sending the correct quantity, variation, and version of the product ordered.

10. Exchanges and Buyer Claims

TenBelow operates on an exchange-first model for eligible delivered-item issues. Sellers agree to comply with the Exchange Policy and all related operational instructions issued by TenBelow.

A buyer may request one exchange per purchased item for qualifying issues such as damage, defect, incorrect item, or material mismatch with the listing. TenBelow reviews exchange requests first and may request seller input before making a final determination.

If an exchange request relating to your order is forwarded to you, you must review it promptly and respond within the timeframe required by TenBelow. Your response must be honest, supported by the available evidence, and professional.

TenBelow may make the final determination on whether an exchange is approved, denied, or requires additional information. Sellers agree to comply with TenBelow’s exchange decisions and to fulfill approved replacement obligations within the timeframe directed by TenBelow.

Where the approved exchange involves seller fault, listing inaccuracy, shipment damage attributable to packaging or fulfillment, or a defective or incorrect item, the seller is responsible for the replacement item and applicable seller-side obligations associated with that approved remedy.

11. Refunds and Non-Exchange Outcomes

Because many TenBelow items are creator-made, made to order, or 3D printed, TenBelow’s standard remedy for eligible delivered-item issues is exchange or replacement rather than refund. Sellers may not advertise refund promises or policies that conflict with TenBelow’s platform structure unless expressly approved in writing by TenBelow.

Refunds may still be required in limited circumstances, including where required by law, where an order cannot be fulfilled or replaced, where a shipping-delay cancellation must be honored, where a seller fails to comply with an approved remedy, or where TenBelow determines that a refund is necessary to resolve a valid claim, marketplace failure, or legal obligation.

TenBelow may process or direct refunds, reversals, or payout offsets where necessary to comply with law, resolve a valid dispute, protect users, or maintain marketplace integrity.

12. Custom Requests

TenBelow may allow sellers to opt into custom request functionality. If you enable that feature, you are responsible for reviewing, responding to, and managing custom-request opportunities in a lawful and professional manner.

TenBelow does not guarantee that any custom request will result in a sale, paid project, or completed order. TenBelow may moderate, pause, remove, or route custom request activity where necessary.

13. Drops and Special Release Features

TenBelow may provide special release or promotional opportunities such as Weekly Drops or other featured release experiences. Participation in these features is subject to platform rules, editorial discretion, and operational capacity.

TenBelow may limit slots, review submissions, reject submissions, or remove participation where necessary. Inclusion in any featured or special-release experience is not guaranteed.

14. Product Safety and Compliance

You are solely responsible for ensuring that your products comply with all applicable laws, regulations, warnings, safety requirements, labeling requirements, and marketplace rules. You may not list unsafe, recalled, unlawfully labeled, electrically hazardous, fire-prone, noncompliant, or otherwise dangerous products on TenBelow.

This responsibility is especially important for products that may present elevated safety risk, including products involving lighting, electrical components, batteries, charging functions, internal or external wiring, heat-producing elements, or similar characteristics.

You may not market a higher-risk product as safe, certified, child-safe, nursery-safe, fire-safe, or otherwise risk-free unless you have a lawful and supportable basis for that claim.

If you learn that a listed or sold product may present a safety issue, electrical issue, overheating issue, charging issue, defect trend, recall-related concern, or other risk of injury, fire, burn, shock, or property damage, you must immediately notify TenBelow and fully cooperate with any removal, customer notification, exchange, refund, or corrective steps required by TenBelow or law.

TenBelow reserves the right to remove or reject listings, suspend access, hold payouts, require corrective labeling, require additional documentation, or terminate seller participation where TenBelow believes a product may create unreasonable risk, legal exposure, consumer harm, or marketplace integrity concerns.

15. Marketing, Promotion, and Visibility

TenBelow may feature your storefront, products, creator identity, and content through editorial or promotional placements, including creator spotlights, app placements, featured releases, social reposts, launch campaigns, and related promotional efforts.

Promotional placement is discretionary and may be based on listing quality, marketplace fit, buyer response, product quality, policy compliance, engagement, fulfillment quality, and business priorities. TenBelow does not guarantee traffic, impressions, sales, placement, or exposure.

If you promote your TenBelow listings through social media or external channels, you must do so truthfully and in compliance with applicable advertising law.

16. Taxes and Reporting

You are solely responsible for determining, reporting, and remitting taxes arising from your sales activity to the extent required by law and not otherwise handled by TenBelow or its payment partners. You are also responsible for providing any information reasonably requested for tax reporting, payment reporting, verification, or compliance purposes.

17. Suspension, Removal, and Termination

TenBelow may suspend, restrict, remove, or terminate your seller account, listings, storefront, payouts, or access to seller features at any time, with or without prior notice, if TenBelow believes you have violated this Agreement, created legal or operational risk, harmed buyers, infringed rights, engaged in fraud, failed to cooperate with exchange review, or acted inconsistently with the integrity of the marketplace.

TenBelow may also remove individual listings, reduce visibility, pause product sales, hold payouts, archive products, delete or disable seller accounts, remove a deleted seller’s active products from the marketplace catalog, or impose other seller restrictions short of full termination. TenBelow may retain historical records related to orders, exchanges, reviews, payments, audit logs, support issues, and security events where needed for legal, accounting, dispute-resolution, or safety reasons.

If TenBelow monitors, discovers, or receives a credible report that a seller account is involved with illegal products, ghost guns, gun parts, weapon components, dangerous devices, controlled substances, stolen goods, counterfeit goods, or other prohibited activity, TenBelow may permanently ban the seller from the app, delete or disable the account, remove all related listings, block future seller participation, preserve relevant records, and cooperate with law enforcement or regulatory authorities where appropriate.

18. Disclaimers

TENBELOW IS PROVIDED ON AN “AS IS” AND “AS AVAILABLE” BASIS TO THE MAXIMUM EXTENT PERMITTED BY LAW. INNOVATIVE CODEWORKS LLC DISCLAIMS ALL WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, TITLE, NON-INFRINGEMENT, ACCURACY, RELIABILITY, SECURITY, AND AVAILABILITY.

TENBELOW DOES NOT GUARANTEE ANY PARTICULAR LEVEL OF SALES, TRAFFIC, CONVERSION, USER GROWTH, PLATFORM AVAILABILITY, OR PROMOTIONAL EXPOSURE.

19. Limitation of Liability

TO THE MAXIMUM EXTENT PERMITTED BY LAW, INNOVATIVE CODEWORKS LLC, TENBELOW, AND THEIR AFFILIATES, MEMBERS, MANAGERS, OFFICERS, EMPLOYEES, CONTRACTORS, AND AGENTS SHALL NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, EXEMPLARY, OR PUNITIVE DAMAGES, OR FOR ANY LOSS OF PROFITS, REVENUE, DATA, GOODWILL, BUSINESS, OR OPPORTUNITY ARISING OUT OF OR RELATING TO YOUR SELLER PARTICIPATION, YOUR USE OF TENBELOW, ANY BUYER OR SELLER DISPUTE, OR ANY PLATFORM INTERRUPTION OR ENFORCEMENT ACTION.

TO THE MAXIMUM EXTENT PERMITTED BY LAW, TENBELOW’S TOTAL LIABILITY FOR ANY CLAIM ARISING OUT OF OR RELATING TO THIS AGREEMENT SHALL NOT EXCEED THE GREATER OF ONE HUNDRED U.S. DOLLARS (US $100.00) OR THE AMOUNT PAID BY YOU DIRECTLY TO TENBELOW IN THE TWELVE (12) MONTHS PRECEDING THE EVENT GIVING RISE TO THE CLAIM.

20. Indemnification

You agree to indemnify, defend, and hold harmless Innovative Codeworks LLC, TenBelow, and their affiliates, members, managers, officers, employees, contractors, and agents from and against any claims, liabilities, damages, losses, judgments, fines, penalties, costs, and expenses, including reasonable attorneys’ fees, arising out of or relating to your products, listings, storefront, content, marketing, shipping, customer interactions, exchange-related conduct, violation of law, violation of this Agreement, or infringement of any third-party right.

21. Governing Law and Venue

This Agreement is governed by the laws of the Commonwealth of Pennsylvania, without regard to conflict-of-law principles. Any dispute arising out of or relating to this Agreement or your participation as a seller on TenBelow shall be brought exclusively in the state or federal courts located in Pennsylvania, and you consent to personal jurisdiction and venue in those courts.

22. Changes to This Agreement

TenBelow may update this Seller Agreement from time to time. Revised versions become effective when posted in the app, made available through the platform, or otherwise communicated to sellers. Continued seller participation after an update constitutes acceptance of the revised Agreement.

23. Contact

Innovative Codeworks LLC
Doing Business As: TenBelow
Founder: Steven LeVere
admin@innovativecodeworks.com

By selling on TenBelow, you acknowledge that you have read, understood, and agreed to this Seller Agreement.
"""
        case .exchangePolicy:
            return """
EXCHANGE POLICY

Effective Date: April 24, 2026

This Exchange Policy explains how TenBelow handles exchange requests for eligible product issues on the platform. In this Policy, “TenBelow,” “Company,” “we,” “us,” and “our” mean Innovative Codeworks LLC, doing business as TenBelow. “Buyer” means the person who placed the order. “Seller” means the seller or creator who fulfilled or was expected to fulfill the product order.

Because many products sold through TenBelow are creator-made, 3D printed, made to order, or produced in small batches, TenBelow’s standard remedy for eligible delivered-item issues is exchange or replacement rather than refund.

1. General Rule

Buyers may request one exchange per purchased item for qualifying issues. Exchange requests are reviewed by TenBelow first and may be approved, denied, or returned for additional information.

2. Eligible Exchange Reasons

An exchange request may be eligible if the item:
- arrived damaged;
- arrived defective;
- is materially different from the listing description or listing images;
- is the wrong item, wrong version, wrong variation, or otherwise incorrect due to seller fulfillment error.

3. Ineligible Exchange Reasons

An exchange request is generally not eligible if:
- the buyer changed their mind;
- the buyer ordered the wrong item but the listing was accurate;
- the issue is normal wear and tear after delivery;
- the issue is minor variation normal to 3D printing or creator-made production and was disclosed or reasonably visible;
- the buyer damaged, modified, altered, or misused the item after delivery;
- the buyer fails to provide requested evidence within the required timeframe.

4. Request Deadline

The buyer must submit an exchange request within seven (7) calendar days after the carrier marks the item as delivered, unless TenBelow states otherwise for a specific case or applicable law requires otherwise.

5. Evidence Requirements

To request an exchange, the buyer must provide sufficient evidence showing the issue. This may include:
- clear photos;
- order information;
- a written explanation;
- and, where requested, video evidence.

TenBelow may deny exchange requests that do not include sufficient information to review the claim.

6. Review Process

Exchange requests are first reviewed by TenBelow. TenBelow may:
- approve the request;
- deny the request;
- ask the buyer for more information;
- seek the seller’s input before making a final decision.

The seller may be required to review supporting evidence and respond within the timeframe required by TenBelow. TenBelow may make the final determination on whether an exchange is approved, denied, or requires additional information.

7. Approved Exchanges

If an exchange is approved, the seller must fulfill the replacement obligation within the timeframe directed by TenBelow. The replacement item must reasonably match the original listing as ordered, unless TenBelow expressly approves another resolution.

Where the approved exchange involves seller fault, listing inaccuracy, shipment damage attributable to packaging or fulfillment, or a defective or incorrect item, the seller is responsible for the replacement item and applicable seller-side obligations associated with the approved remedy.

8. Safety-Related Claims and Urgent Product Issues

If a buyer reports that a product may present a fire hazard, overheating issue, charging issue, electrical issue, shock risk, burn risk, battery issue, or other urgent safety concern, TenBelow may treat the matter as a priority safety review rather than an ordinary exchange request.

In such situations, TenBelow may:
- pause or remove the listing;
- contact the seller for documentation or explanation;
- contact affected buyers;
- require additional photos or video;
- direct an exchange, replacement, return, refund, or other corrective action;
- hold payouts;
- or take any other action reasonably necessary to protect users and the marketplace.

TenBelow is not required to process a safety-related claim solely under the standard exchange workflow where a faster or broader response is reasonably necessary.

9. Return of Original Item

TenBelow may, in its discretion, decide whether the buyer must return the original item before or after a replacement is issued. In some situations, particularly lower-value items or where return handling is impractical, TenBelow may determine that a return is not required.

If return instructions are issued, the buyer must follow them in order to remain eligible for the exchange.

10. Refund Fallback

Refunds are generally not the standard remedy for delivered items on TenBelow. However, a refund may still be issued where:
- required by applicable law;
- an order cannot be fulfilled or replaced;
- a seller fails to comply with an approved exchange remedy;
- a valid shipping-delay cancellation or other legal cancellation right applies;
- TenBelow determines that a refund is necessary to resolve a valid claim, marketplace failure, or legal obligation.

11. Abuse and Misuse

TenBelow may deny, limit, or suspend exchange privileges where it believes a buyer or seller is abusing the exchange process, submitting false claims, misrepresenting evidence, or otherwise acting inconsistently with the integrity of the marketplace.

12. Platform Authority

TenBelow may review evidence, communicate with buyers and sellers, require documentation, direct exchange outcomes, pause payouts, remove listings, suspend accounts, or take any other action reasonably necessary to resolve exchange-related issues and protect the marketplace.

13. Contact

Innovative Codeworks LLC
Doing Business As: TenBelow
Founder: Steven LeVere
admin@innovativecodeworks.com
"""
        }
    }
}

/// Full-screen in-app legal text (matches `LegalDocumentView` bodies, not remote web pages).
struct LegalDocumentSheet: View {
    let document: LegalDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LegalDocumentView(document: document)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                            .accessibilityIdentifier("legal.sheet.done")
                    }
                }
        }
    }
}

struct LegalDocumentView: View {
    let document: LegalDocument

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                GlassCard(cornerRadius: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(document.title)
                            .font(.tbProductTitleXL)
                            .foregroundStyle(TBTheme.deepSky)
                            .accessibilityAddTraits(.isHeader)

                        Text(document.subtitle)
                            .font(.tbBodyStrong)
                            .foregroundStyle(TBTheme.icyBlue)
                    }
                }

                GlassCard(cornerRadius: 24) {
                    Text(document.bodyText)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .dynamicTypeSize(.xSmall ... .accessibility5)
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .accessibilityIdentifier("legal.document.\(document.id)")
        .background(TBTheme.cloudWhite.ignoresSafeArea())
        .navigationTitle(document.title)
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

